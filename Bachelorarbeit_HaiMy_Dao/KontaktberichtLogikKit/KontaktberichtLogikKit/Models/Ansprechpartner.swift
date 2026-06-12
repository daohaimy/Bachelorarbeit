//
//  Ansprechpartner.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import Combine
import FoundationModels


public struct Ansprechpartner: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    
    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public final class AnsprechpartnerDirectory {
    @Published public var contacts: [Ansprechpartner] = [
        Ansprechpartner(name: "Anna Müller"),
        Ansprechpartner(name: "Henri Schneider"),
        Ansprechpartner(name: "Jonas Schmidt"),
        Ansprechpartner(name: "Max Mustermann"),
        Ansprechpartner(name: "Tim Kröger"),
        Ansprechpartner(name: "Peter Müller"),
    ]

    public init() {}
}

extension Array where Element == Ansprechpartner {
    
    /// Alle Kontakte, die zum eingegebenen Namen passen.
    /// Matching-Regel:
    /// - exakte Übereinstimmung (case-insensitive)
    /// - sonst: alle eingegebenen Tokens (z.B. "henri", "müller") müssen im Kontaktnamen vorkommen
    ///   -> "Henri" findet "Henri Schneider"
    ///   -> "Müller" findet "Anna Müller" und "Peter Müller"
    func matchingContacts(for raw: String) -> [Ansprechpartner] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Höflichkeitsfloskeln rausfiltern
        let stopwords: Set<String> = ["herr", "frau", "dr", "doktor", "prof", "prof."]

        let rawTokens = trimmed
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
            .filter { !stopwords.contains($0) }

        guard !rawTokens.isEmpty else { return [] }

        // 1. exakte Übereinstimmung auf den kompletten Namen
        if let exact = first(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return [exact]
        }

        // 2. Token-basiert: alle eingegebenen Tokens müssen im Kontaktnamen vorkommen
        return filter { contact in
            let contactTokens = contact.name
                .lowercased()
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)

            return rawTokens.allSatisfy { token in
                contactTokens.contains(token)
            }
        }
    }

    /// Liefert den Namen nur dann zurück, wenn genau ein Kontakt passt.
    /// Bei 0 oder >1 Treffern -> nil.
    func resolveNameIfUnique(from raw: String) -> String? {
        let matches = matchingContacts(for: raw)
        return matches.count == 1 ? matches[0].name : nil
    }
}
