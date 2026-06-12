//
//  KontaktberichtLLMService.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import FoundationModels

// Ergebnis, das ViewModel vom Service bekommt
struct LLMResult {
    var bericht: Kontaktbericht
    var pendingQuestion: String?
    var pendingMissing: [String]
    var toolDidCreate: Bool
    var toolDidClarify: Bool
}

protocol KontaktberichtLLMServiceProtocol {
    func configure(directory: AnsprechpartnerDirectory)
    func extract(from freeText: String) async throws -> LLMResult
    func answerFollowup(
        originalFreeText: String,
        followupAnswer: String,
        currentBericht: Kontaktbericht
    ) async throws -> (result: LLMResult, newOriginalFreeText: String)
}

final class KontaktberichtLLMService: KontaktberichtLLMServiceProtocol {
    private var session: LanguageModelSession?
    private var ansprechpartnerDirectory: AnsprechpartnerDirectory?

    // Zustände, die bisher im ViewModel lagen
    private var originalFreeText: String = ""

    private var currentBerichtInternal = Kontaktbericht(ansprechpartner: "", typ: .telefon, inhalt: "")

    private var pendingQuestionInternal: String?
    private var pendingMissingInternal: [String] = []
    private var queuedQuestion: String?
    private var queuedMissing: [String] = []

    private var toolDidCreateInternal = false
    private var toolDidClarifyInternal = false

    // Prompt
    static let llmInstructions = """
                        Rolle & Ziel: Du extrahierst Felder eines Kontaktberichts aus deutschem Freitext.
                        Antworte ausschließlich per Tool-Aufruf (kein Fließtext).

                        Gesprächsinhalt: die Inhalt in einem kurzen Satz zusammenfassen. Falls es keine Inhalt im Text gibt, dann einfach leer lassen.
                        """


    // MARK: - Public API

    func configure(directory: AnsprechpartnerDirectory) {
        self.ansprechpartnerDirectory = directory
        setupLanguageModelSession()
    }

    func extract(from freeText: String) async throws -> LLMResult {
        guard let session else {
            throw LLMError.sessionNotInitialized
        }

        originalFreeText = freeText

        // internen Zustand resetten
        currentBerichtInternal = Kontaktbericht(ansprechpartner: "", typ: .telefon, inhalt: "")
        pendingQuestionInternal = nil
        pendingMissingInternal = []
        queuedQuestion = nil
        queuedMissing = []
        toolDidCreateInternal = false
        toolDidClarifyInternal = false

        try await session.respond(to: freeText)

        return LLMResult(
            bericht: currentBerichtInternal,
            pendingQuestion: pendingQuestionInternal,
            pendingMissing: pendingMissingInternal,
            toolDidCreate: toolDidCreateInternal,
            toolDidClarify: toolDidClarifyInternal
        )
    }

    func answerFollowup(
        originalFreeText: String,
        followupAnswer: String,
        currentBericht: Kontaktbericht
    ) async throws -> (result: LLMResult, newOriginalFreeText: String) {

        guard let session else {
            throw LLMError.sessionNotInitialized
        }

        // neuen Originaltext bauen
        let newOriginal = (originalFreeText + " " + followupAnswer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.originalFreeText = newOriginal

        // Zustand resetten, Bericht übernehmen
        currentBerichtInternal = currentBericht
        pendingQuestionInternal = nil
        pendingMissingInternal = []
        queuedMissing = []
        queuedQuestion = nil
        toolDidCreateInternal = false
        toolDidClarifyInternal = false

        try await session.respond(to: followupAnswer)

        // ggf. noch die queuedQuestion -> pendingQuestion umhängen
        if pendingQuestionInternal == nil,
           let nextQ = queuedQuestion,
           !queuedMissing.isEmpty {
            pendingQuestionInternal = nextQ
            pendingMissingInternal = queuedMissing
            queuedQuestion = nil
            queuedMissing = []
        }

        let result = LLMResult(
            bericht: currentBerichtInternal,
            pendingQuestion: pendingQuestionInternal,
            pendingMissing: pendingMissingInternal,
            toolDidCreate: toolDidCreateInternal,
            toolDidClarify: toolDidClarifyInternal
        )

        return (result, newOriginal)
    }

    // MARK: - Session Setup

    private func setupLanguageModelSession() {
        guard let directory = ansprechpartnerDirectory else { return }

        let createTool = BerichtTool(onCreate: { [weak self] newReport, didSetDate in
            guard let self else { return }
            self.handleCreateTool(newReport: newReport,
                                  didSetDate: didSetDate,
                                  directory: directory)
        })

        let clarifyTool = NeedClarificationTool(onAsk: { [weak self] _, missing in
            self?.handleClarifyTool(missing: missing)
        })

        self.session = LanguageModelSession(
            tools: [createTool, clarifyTool],
            instructions: { Self.llmInstructions }
        )
    }

    // MARK: - Tool-Handler (ehemals im ViewModel)

    private func handleCreateTool(
        newReport: Kontaktbericht,
        didSetDate: Bool,
        directory: AnsprechpartnerDirectory
    ) {
        toolDidCreateInternal = true

        var merged = currentBerichtInternal

        let (parsedDate, ownDidSet) = extractDateFromOriginalText(
            freeText: originalFreeText,
            kontaktbericht: merged
        )

        if ownDidSet {
            merged.date = parsedDate
        }

        // Ansprechpartner-Logik
        let rawName = newReport.ansprechpartner.trimmingCharacters(in: .whitespacesAndNewlines)

        if !rawName.isEmpty {
            let candidates = directory.contacts.matchingContacts(for: rawName)

            if candidates.count == 1 {
                // eindeutiger Treffer -> offiziellen Namen setzen
                merged.ansprechpartner = candidates[0].name

            } else if candidates.count > 1 {
                // Mehrdeutig -> Ansprechpartner NICHT setzen und Rückfrage stellen
                merged.ansprechpartner = ""

                toolDidClarifyInternal = true
                pendingMissingInternal = ["ansprechpartner"]

                let names = candidates.map { $0.name }
                let optionsText: String
                switch names.count {
                case 2:
                    optionsText = "\(names[0]) oder \(names[1])"
                default:
                    let allButLast = names.dropLast().joined(separator: ", ")
                    if let last = names.last {
                        optionsText = allButLast + " oder " + last
                    } else {
                        optionsText = names.joined(separator: ", ")
                    }
                }

                pendingQuestionInternal = "Wen genau meinst du? \(optionsText)?"

            } else {
                // Kein Treffer in der Liste -> nach Ansprechpartner fragen
                merged.ansprechpartner = ""

                toolDidClarifyInternal = true
                pendingMissingInternal = ["ansprechpartner"]
                pendingQuestionInternal = """
                Ansprechpartner nicht gefunden.
                Wer ist nochmal der Ansprechpartner?
                """
            }
        }

        // Typ-Logik
        merged.typ = newReport.typ

        let lowerText = originalFreeText.lowercased()

        func typExplizitImText(_ typ: Gespraechstyp) -> Bool {
            switch typ {
            case .telefon:
                return lowerText.contains("telefon") ||
                lowerText.contains("telefoniert") ||
                lowerText.contains("angerufen") ||
                lowerText.contains("anruf")
            case .email:
                return lowerText.contains("e-mail") ||
                lowerText.contains("email") ||
                lowerText.contains("mail")
            case .messegespraech:
                return lowerText.contains("messe") ||
                lowerText.contains("messegespräch") ||
                lowerText.contains("messegespraech")
            case .kundenbesuch:
                return lowerText.contains("kundenbesuch") ||
                lowerText.contains("vor ort") ||
                lowerText.contains("beim kunden")
            case .chance:
                return lowerText.contains("chance") ||
                lowerText.contains("opportunity") ||
                lowerText.contains("verkaufschance")
            }
        }

        if !typExplizitImText(newReport.typ) {
            toolDidClarifyInternal = true
            var missing = Set(pendingMissingInternal)
            missing.insert("typ")
            pendingMissingInternal = Array(missing)

            let typFrage = """
            Welcher Gesprächstyp war es: Telefon, E-Mail, Messegespräch, Kundenbesuch oder Chance?
            """

            if let existing = pendingQuestionInternal, !existing.isEmpty {
                // es gibt schon z.B. eine Ansprechpartner-Frage -> Typ nur vormerken
                if queuedQuestion == nil {
                    queuedQuestion = typFrage
                    queuedMissing = ["typ"]
                } else {
                    var m = Set(queuedMissing)
                    m.insert("typ")
                    queuedMissing = Array(m)
                }
            } else {
                pendingMissingInternal = ["typ"]
                pendingQuestionInternal = typFrage

                queuedQuestion = nil
                queuedMissing = []
            }
        }

        // Inhalt
        if !newReport.inhalt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.inhalt = stripDateAndTime(from: newReport.inhalt)
        }

        currentBerichtInternal = merged
    }

    private func handleClarifyTool(missing: [String]) {
        toolDidClarifyInternal = true

        if pendingQuestionInternal != nil || !pendingMissingInternal.isEmpty {
            return
        }

        let relevant = missing.filter { $0 == "ansprechpartner" || $0 == "typ" }
        pendingMissingInternal = relevant

        guard !relevant.isEmpty else {
            pendingQuestionInternal = nil
            return
        }
    }

    enum LLMError: Error {
        case sessionNotInitialized
    }
}
