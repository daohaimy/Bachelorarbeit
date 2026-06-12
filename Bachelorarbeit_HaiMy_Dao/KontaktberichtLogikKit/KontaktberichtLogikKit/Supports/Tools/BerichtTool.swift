//
//  BerichtTool.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import FoundationModels

struct BerichtTool: Tool {
    let name = "create_kontaktbericht"
    let description = "Erzeuge einen Kontaktbericht aus Freitext."

    private let onCreate: @Sendable (Kontaktbericht, Bool) -> Void
    init(onCreate: @escaping @Sendable (Kontaktbericht, Bool) -> Void = { _, _ in }) {
        self.onCreate = onCreate
    }

    @Generable
    struct Arguments: Codable, Equatable, Sendable {
        let ansprechpartner: String
        let date_text: String?
        let date_iso: String?
        let typ: String
        let inhalt: String
    }

    func call(arguments: Arguments) async throws -> GeneratedContent {
        let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = berlin

        func parseRelativeDE(_ raw: String, now: Date) -> Date? {
            let s = raw.lowercased()
            let offset: Int
            if s.contains("vorgestern") { offset = -2 }
            else if s.contains("gestern") { offset = -1 }
            else if s.contains("heute") { offset = 0 }
            else { return nil }

            let base = cal.startOfDay(for: now)
            guard let day = cal.date(byAdding: .day, value: offset, to: base) else { return nil }
            var comps = cal.dateComponents([.year, .month, .day], from: day)

            // Uhrzeit: "15:30", "15.30", "15", "15 uhr"
            let pattern = #/(\d{1,2})(?:(?:[:.](\d{2}))|\s*uhr)?/#
            if let m = s.firstMatch(of: pattern) {
                let hour   = Int(String(m.1)) ?? 0
                let minute = m.2.flatMap { Int(String($0)) } ?? 0
                comps.hour   = Swift.max(0, Swift.min(23, hour))
                comps.minute = Swift.max(0, Swift.min(59, minute))
                comps.second = 0
            } else {
                let t = cal.dateComponents([.hour, .minute, .second], from: now)
                comps.hour = t.hour; comps.minute = t.minute; comps.second = t.second
            }
            return cal.date(from: comps)
        }

        func hasExplicitTZ(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.contains("Z") || t.range(of: #"([+-]\d{2}:\d{2}|[+-]\d{4})"#, options: .regularExpression) != nil
        }

        func parseDateISOorLocalBerlin(_ s: String, now: Date) -> Date? {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            // a) ISO mit expliziter TZ
            if hasExplicitTZ(trimmed) {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = iso.date(from: trimmed) { return d }
                iso.formatOptions = [.withInternetDateTime]
                if let d = iso.date(from: trimmed) { return d }
            }

            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.calendar = cal
            df.timeZone = berlin

            // b1) mit Uhrzeit (rein numerisch)
            for fmt in ["yyyy-MM-dd'T'HH:mm:ss",
                        "yyyy-MM-dd'T'HH:mm",
                        "dd.MM.yyyy HH:mm",
                        "yyyy-MM-dd HH:mm"] {
                df.dateFormat = fmt
                if let d = df.date(from: trimmed) { return d }
            }

            // b2) nur Datum (rein numerisch) -> aktuelle Uhrzeit ergänzen
            for fmt in ["yyyy-MM-dd", "dd.MM.yyyy"] {
                df.dateFormat = fmt
                if let dayOnly = df.date(from: trimmed) {
                    var comps = cal.dateComponents([.year, .month, .day], from: dayOnly)
                    let t = cal.dateComponents([.hour, .minute, .second], from: now)
                    comps.hour = t.hour; comps.minute = t.minute; comps.second = t.second
                    return cal.date(from: comps)
                }
            }

            // deutsche Datumsangaben mit Monatsnamen, z.B. "18. Mai 2024"
            do {
                let dfDE = DateFormatter()
                dfDE.locale   = Locale(identifier: "de_DE")
                dfDE.calendar = cal
                dfDE.timeZone = berlin

                // b3) Tag + Monatwort + Jahr -> aktuelle Uhrzeit ergänzen
                for fmt in ["d. MMMM yyyy",
                            "d MMMM yyyy",
                            "d. MMM yyyy",
                            "d MMM yyyy"] {
                    dfDE.dateFormat = fmt
                    if let dayOnly = dfDE.date(from: trimmed) {
                        var comps = cal.dateComponents([.year, .month, .day], from: dayOnly)
                        let t = cal.dateComponents([.hour, .minute, .second], from: now)
                        comps.hour = t.hour; comps.minute = t.minute; comps.second = t.second
                        return cal.date(from: comps)
                    }
                }

                // Optional: ohne Jahr -> Jahr automatisch ergänzen
                // Regel:
                // - Standard: aktuelles Jahr
                // - Wenn Tag+Monat in diesem Jahr noch in der Zukunft liegen -> nimm letztes Jahr
                for fmt in ["d. MMMM",
                            "d MMMM",
                            "d. MMM",
                            "d MMM"] {
                    dfDE.dateFormat = fmt
                    if let partial = dfDE.date(from: trimmed) {
                        // Monat & Tag aus dem geparsten Datum holen
                        var comps = cal.dateComponents([.month, .day], from: partial)

                        // aktuelles Jahr + aktuelle Uhrzeit dazunehmen
                        let nowComps = cal.dateComponents([.year, .hour, .minute, .second], from: now)
                        comps.year   = nowComps.year
                        comps.hour   = nowComps.hour
                        comps.minute = nowComps.minute
                        comps.second = nowComps.second

                        // Erstkandidat: Tag+Monat in diesem Jahr
                        guard var candidate = cal.date(from: comps) else { return nil }

                        // Wenn das Datum in der Zukunft liegt -> Jahr auf letztes Jahr setzen
                        if candidate > now {
                            comps.year = (nowComps.year ?? 0) - 1
                            candidate = cal.date(from: comps) ?? candidate
                        }

                        return candidate
                    }
                }
                
                // Nur Tag+Monat numerisch ohne Jahr, z.B. "18.05." oder "18.5."
                for fmt in ["d.M.", "dd.MM."] {
                    df.dateFormat = fmt
                    if let partial = df.date(from: trimmed) {
                        var comps = cal.dateComponents([.month, .day], from: partial)

                        let nowComps = cal.dateComponents([.year, .hour, .minute, .second], from: now)
                        comps.year   = nowComps.year
                        comps.hour   = nowComps.hour
                        comps.minute = nowComps.minute
                        comps.second = nowComps.second

                        guard var candidate = cal.date(from: comps) else { return nil }

                        if candidate > now {
                            comps.year = (nowComps.year ?? 0) - 1
                            candidate = cal.date(from: comps) ?? candidate
                        }

                        return candidate
                    }
                }


            }

            // c) Zeit-Only (wie gehabt)
            for fmt in ["HH:mm", "HH.mm", "HH 'uhr'", "HH"] {
                df.dateFormat = fmt
                if let timeOnly = df.date(from: trimmed) {
                    var comps = cal.dateComponents([.year, .month, .day], from: now)
                    let t = cal.dateComponents([.hour, .minute, .second], from: timeOnly)
                    comps.hour   = t.hour
                    comps.minute = t.minute
                    comps.second = t.second ?? 0
                    return cal.date(from: comps)
                }
            }

            // d) Unix epoch
            if let ts = Double(trimmed) {
                return Date(timeIntervalSince1970: ts > 10_000_000_000 ? ts/1000 : ts)
            }

            // e) letzter Versuch: ISO ohne ms
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: trimmed) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: trimmed) { return d }

            return nil
        }


        let now = Date()
        var didSetDate = false
        var resolvedDate: Date

        let relativeRaw: String? = {
            // 1) Normalfall: relative Angabe in date_text (so wie in deinen Anweisungen)
            if let text = arguments.date_text {
                let lower = text.lowercased()

                if lower.contains("gestern")
                    || lower.contains("vorgestern")
                    || lower.contains("heute") {

                    // Zeit nur in date_iso? -> anhängen (z.B. "gestern" + "14:00")
                    if let iso = arguments.date_iso,
                       iso.range(of: #"^\s*\d{1,2}([:.]\d{2})?\s*(uhr)?\s*$"#,
                                 options: .regularExpression) != nil {
                        return text + " " + iso
                    }

                    return text
                }
            }

            // 2) Fallback: LLM hat die relative Formulierung fälschlich in date_iso gepackt
            if let isoText = arguments.date_iso {
                let lower = isoText.lowercased()
                if lower.contains("gestern")
                    || lower.contains("vorgestern")
                    || lower.contains("heute") {
                    return isoText
                }
            }

            return nil
        }()


        if let rel = relativeRaw, let d = parseRelativeDE(rel, now: now) {
            // z.B. "gestern 9:52" -> gestern 09:52
            resolvedDate = d
            didSetDate = true
        } else if let iso = arguments.date_iso,
                  let d = parseDateISOorLocalBerlin(iso, now: now) {
            // absolute oder "normale" ISO-Angaben
            resolvedDate = d
            didSetDate = true
        } else {
            // Fallback: jetzt, aber als "nicht explizit gesetzt" markieren
            resolvedDate = now
            didSetDate = true
        }

        let typResolved: Gespraechstyp = {
        let raw = arguments.typ.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // direkter RawValue match
        if let t = Gespraechstyp(rawValue: raw) { return t }

        // Fallbacks (falls KI "Telefonat", "persönlich", "Mail" etc schreibt)
        if raw.contains("kundenbesuch") || raw.contains("kundenbesuch") { return .kundenbesuch }
        if raw.contains("mail") || raw.contains("e-mail") { return .email }
        if raw.contains("messe") { return .messegespraech }
        if raw.contains("chance") { return .chance }
        return .telefon
    }()


        let bericht = await Kontaktbericht(
            ansprechpartner: arguments.ansprechpartner,
            date: resolvedDate,
            typ: typResolved,
            inhalt: arguments.inhalt
        )
        let didSetDateCopy = didSetDate

        await MainActor.run { onCreate(bericht, didSetDateCopy) }

        let isoOut = ISO8601DateFormatter()
        isoOut.timeZone = berlin
        isoOut.formatOptions = [.withInternetDateTime]

        return GeneratedContent(properties: [
            "ansprechpartner": bericht.ansprechpartner,
            "date_iso": isoOut.string(from: bericht.date),
            "typ": bericht.typ.rawValue,
            "inhalt": bericht.inhalt
        ])
    }
}

