//
//  LastBerichtTool.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import FoundationModels

struct LastBerichtTool: Tool {
    let name = "kontaktbericht_list_action"
    let description = "Führe eine Aktion auf der Kontaktberichtliste aus, z. B. den letzten Kontaktbericht anzeigen."

    private let onShowLast: @MainActor @Sendable () -> Void
    private let onNoMatch: @MainActor @Sendable (_ message: String) -> Void

    init(
        onShowLast: @escaping @MainActor @Sendable () -> Void = { },
        onNoMatch: @escaping @MainActor @Sendable (_ message: String) -> Void = { _ in }
    ) {
        self.onShowLast = onShowLast
        self.onNoMatch = onNoMatch
    }

    @Generable
    struct Arguments: Codable, Equatable, Sendable {
        /// Erwartete Werte:
        /// - "show_last"
        /// - "none"
        let action: String
    }

    func call(arguments: Arguments) async throws -> GeneratedContent {
        let normalized = arguments.action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "show_last":
            await onShowLast()
            return GeneratedContent(properties: [
                "action": "show_last",
                "status": "ok"
            ])

        case "none":
            await onNoMatch("Die Anfrage konnte keiner Aktion zugeordnet werden.")
            return GeneratedContent(properties: [
                "action": "none",
                "status": "no_match"
            ])

        default:
            await onNoMatch("Unerwartete Aktion: \(arguments.action)")
            return GeneratedContent(properties: [
                "action": normalized,
                "status": "unknown_action"
            ])
        }
    }
}
