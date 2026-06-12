//
//  ExtractDateFromText.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation

func extractDateFromOriginalText(freeText: String, kontaktbericht: Kontaktbericht, now: Date = Date()) -> (date: Date, didSet: Bool) {
    let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = berlin

    let text = freeText.lowercased()

    // gibt zusätzlich zurück, ob eine Uhrzeit EXPLIZIT im Text vorkam
    func extractTimeComponents() -> (components: DateComponents, explicit: Bool) {
        // nur Zeiten wie "15:30", "15.30" oder "15 uhr"
        let pattern = #/(\d{1,2})(?:[:.](\d{2})|\s*uhr)/#
        if let m = text.firstMatch(of: pattern) {
            let hour   = Int(String(m.1)) ?? 0
            let minute = m.2.flatMap { Int(String($0)) } ?? 0

            var comps = DateComponents()
            comps.hour   = max(0, min(23, hour))
            comps.minute = max(0, min(59, minute))
            comps.second = 0
            return (comps, true)
        } else {
            // keine Uhrzeit gefunden -> aktuelle Uhrzeit
            let t = cal.dateComponents([.hour, .minute, .second], from: now)
            return (t, false)
        }
    }

    // 1) Relative Angaben: gestern / vorgestern / heute
    func parseRelative() -> Date? {
        let offset: Int
        if text.contains("vorgestern") { offset = -2 }
        else if text.contains("gestern") { offset = -1 }
        else if text.contains("heute") { offset = 0 }
        else { return nil }

        let base = cal.startOfDay(for: now)
        guard let day = cal.date(byAdding: .day, value: offset, to: base) else { return nil }

        var comps = cal.dateComponents([.year, .month, .day], from: day)
        let (timeComps, _) = extractTimeComponents()
        comps.hour   = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = timeComps.second

        return cal.date(from: comps)
    }

    // 2) Tag.Monat.Jahr (z.B. "18.05.2024")
    func parseNumericDayMonthYear() -> Date? {
        let pattern = #/(\d{1,2})\.(\d{1,2})\.(\d{4})/#
        guard let m = text.firstMatch(of: pattern) else { return nil }

        guard let day = Int(m.1),
              let month = Int(m.2),
              let year = Int(m.3) else { return nil }

        var comps = DateComponents()
        comps.year  = year
        comps.month = month
        comps.day   = day

        let (timeComps, _) = extractTimeComponents()
        comps.hour   = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = timeComps.second

        return cal.date(from: comps)
    }

    // 3) Nur Tag.Monat (ohne Jahr), z.B. "18.05." oder "18.5."
    func parseNumericDayMonthWithoutYear() -> Date? {
        let pattern = #/(\d{1,2})\.(\d{1,2})\.?/#

        guard let m = text.firstMatch(of: pattern) else { return nil }
        guard let day = Int(m.1), let month = Int(m.2) else { return nil }

        var comps = DateComponents()
        let nowComps = cal.dateComponents([.year], from: now)
        comps.year  = nowComps.year
        comps.month = month
        comps.day   = day

        let (timeComps, _) = extractTimeComponents()
        comps.hour   = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = timeComps.second

        guard var candidate = cal.date(from: comps) else { return nil }

        // Wenn das Datum in der Zukunft liegt -> letztes Jahr
        if candidate > now {
            comps.year = (nowComps.year ?? 0) - 1
            candidate = cal.date(from: comps) ?? candidate
        }

        return candidate
    }

    // 4) "18. Mai 2024" oder "18. Mai" usw.
    func parseDayMonthWithName() -> Date? {
        // z.B. "18. Mai 2024", "18 Mai 2024", "18. Mai", "18 Mai"
        let pattern = #/(\d{1,2})\.?\s+([A-Za-zäöüÄÖÜ]+)(?:\s+(\d{4}))?/#

        // Alle "Tag + Wort"-Treffer im Text holen
        for m in text.matches(of: pattern) {
            guard let day = Int(m.1) else { continue }
            let rawMonthName = String(m.2)

            // Monatsnamen normalisieren
            func normalizeMonthName(_ s: String) -> String {
                var x = s.lowercased()
                x = x.replacingOccurrences(of: "ä", with: "ae")
                x = x.replacingOccurrences(of: "ö", with: "oe")
                x = x.replacingOccurrences(of: "ü", with: "ue")
                return x
            }

            let monthMap: [String: Int] = [
                "januar": 1, "jan": 1,
                "februar": 2, "feb": 2,
                "maerz": 3, "märz": 3, "mrz": 3,
                "april": 4, "apr": 4,
                "mai": 5,
                "juni": 6, "jun": 6,
                "juli": 7, "jul": 7,
                "august": 8, "aug": 8,
                "september": 9, "sep": 9, "sept": 9,
                "oktober": 10, "okt": 10,
                "november": 11, "nov": 11,
                "dezember": 12, "dez": 12
            ]

            let key = normalizeMonthName(rawMonthName)
            guard let month = monthMap[key] else {
                continue   // nächsten Treffer probieren (z.B. "11 uhr" überspringen)
            }

            var comps = DateComponents()
            let nowComps = cal.dateComponents([.year], from: now)

            if let yearStr = m.3, let year = Int(yearStr) {
                comps.year = year
            } else {
                comps.year = nowComps.year
            }

            comps.month = month
            comps.day   = day

            let (timeComps, _) = extractTimeComponents()
            comps.hour   = timeComps.hour
            comps.minute = timeComps.minute
            comps.second = timeComps.second

            guard var candidate = cal.date(from: comps) else { continue }

            // Nur wenn kein Jahr im Text stand -> "in Zukunft?"-Check
            if m.3 == nil, candidate > now {
                comps.year = (nowComps.year ?? 0) - 1
                candidate = cal.date(from: comps) ?? candidate
            }

            // Erster gültiger Treffer -> fertig
            return candidate
        }

        // Nichts Gültiges gefunden
        return nil
    }

    // Reihenfolge der Versuche

    if let d = parseRelative() {
        return (d, true)
    }

    if let d = parseNumericDayMonthYear() {
        return (d, true)
    }

    if let d = parseNumericDayMonthWithoutYear() {
        return (d, true)
    }

    if let d = parseDayMonthWithName() {
        return (d, true)
    }

    // 5) Nur Uhrzeit ohne Datum:
    let (timeOnly, hasExplicitTime) = extractTimeComponents()
    if hasExplicitTime {
        var baseComps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: kontaktbericht.date
        )

        baseComps.hour   = timeOnly.hour
        baseComps.minute = timeOnly.minute
        baseComps.second = timeOnly.second

        if let combined = cal.date(from: baseComps) {
            return (combined, true)
        }
    }

    // Nichts erkannt -> bestehendes Datum unverändert lassen
    return (kontaktbericht.date, false)
}
