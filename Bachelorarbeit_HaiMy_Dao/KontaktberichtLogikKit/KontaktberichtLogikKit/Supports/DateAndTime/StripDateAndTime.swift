//
//  StripDateAndTime.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation

func stripDateAndTime(from text: String) -> String {
    var result = text
    let patterns: [String] = [
        // relative Angaben: "gestern", "gestern um 11 Uhr", "heute um 9:30 Uhr"
        #"(?i)\b(vorgestern|gestern|heute)\b(\s+um\s+\d{1,2}([:.]\d{2})?\s*uhr)?"#,

        // "am 1.7.2024", "am 01.07.24"
        #"(?i)\bam\s+\d{1,2}\.\s*\d{1,2}\.\s*\d{2,4}\b"#,

        // "am 1.7." oder "am 1.7"
        #"(?i)\bam\s+\d{1,2}\.\s*\d{1,2}\.?"#,

        // "am 1. Juli 2024" / "am 1. Juli"
        #"(?i)\bam\s+\d{1,2}\.?\s+[A-Za-zäöüÄÖÜ]+(\s+\d{4})?"#,

        // "um 11:30 Uhr", "um 11 Uhr"
        #"(?i)\bum\s+\d{1,2}([:.]\d{2})?\s*uhr\b"#,

        // "gegen 11 Uhr"
        #"(?i)\bgegen\s+\d{1,2}([:.]\d{2})?\s*uhr\b"#,

        // alleinstehend "11:30 Uhr" / "11.30 Uhr"
        #"(?i)\b\d{1,2}[:.]\d{2}\s*uhr\b"#
    ]

    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = regex.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: ""
        )
    }

    // Mehrere Leerzeichen zusammenziehen und sauber trimmen
    result = result.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
    )

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}
