//
//  NeedClarificationTool.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import FoundationModels

struct NeedClarificationTool: Tool {
    let name = "need_clarification"
    let description = "Stellt eine Rückfrage, wenn Pflichtfelder fehlen."

    private let onAsk: @Sendable (String, [String]) -> Void
    init(onAsk: @escaping @Sendable (String, [String]) -> Void = { _, _ in }) {
        self.onAsk = onAsk
    }

    @Generable
    struct Arguments: Codable, Equatable, Sendable {
        let question: String
        let missing_fields: [String]
    }

    func call(arguments: Arguments) async throws -> GeneratedContent {
        await MainActor.run {
            onAsk(arguments.question, arguments.missing_fields)
        }
        return GeneratedContent(properties: ["ok": true])
    }
}
