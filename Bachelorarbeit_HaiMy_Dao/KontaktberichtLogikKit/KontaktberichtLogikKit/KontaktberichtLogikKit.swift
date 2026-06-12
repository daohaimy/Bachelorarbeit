//
//  KontaktberichtLogikKit.swift
//  KontaktberichtLogikKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import Darwin
//import FoundationModels

// MARK: - C memory

@_cdecl("kb_free")
public func kb_free(_ ptr: UnsafeMutablePointer<CChar>?) {
    guard let ptr else { return }
    free(ptr)
}

private func cstr(_ s: String) -> UnsafeMutablePointer<CChar>? {
    strdup(s)
}

// MARK: - JSON helpers
private func encodeErrorJSON(_ message: String) -> UnsafeMutablePointer<CChar>? {
    let obj: [String: String] = ["error": message]
    if let data = try? JSONSerialization.data(withJSONObject: obj),
       let s = String(data: data, encoding: .utf8) {
        return cstr(s)
    }
    return cstr("{\"error\":\"unknown\"}")
}


private func decodeJSON<T: Decodable>(_ type: T.Type, _ c: UnsafePointer<CChar>?) throws -> T {
    guard let c else { throw NSError(domain: "kb", code: 1) }
    let str = String(cString: c)
    return try JSONDecoder().decode(type, from: Data(str.utf8))
}

private func encodeJSON<T: Encodable>(_ value: T) -> UnsafeMutablePointer<CChar>? {
    do {
        let data = try JSONEncoder().encode(value)
        return cstr(String(data: data, encoding: .utf8) ?? "{}")
    } catch {
        return cstr("{\"error\":\"encode_failed\"}")
    }
}

private func runBlocking<T>(_ work: @escaping () async throws -> T) -> Result<T, Error> {
    let sem = DispatchSemaphore(value: 0)
    var result: Result<T, Error>!
    Task {
        do { result = .success(try await work()) }
        catch { result = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return result
}

// MARK: - DTOs (FFI-stabil)

struct KontaktberichtDTO: Codable {
    var id: String?
    var ansprechpartner: String
    var typ: String
    var inhalt: String
    var dateISO: String?
}

struct LLMResultDTO: Codable {
    var bericht: KontaktberichtDTO
    var pendingQuestion: String?
    var pendingMissing: [String]
    var toolDidCreate: Bool
    var toolDidClarify: Bool
}

struct ExtractInDTO: Codable {
    var freeText: String
}

struct FollowupInDTO: Codable {
    var originalFreeText: String
    var followupAnswer: String
    var currentBericht: KontaktberichtDTO
}

struct FollowupOutDTO: Codable {
    var result: LLMResultDTO
    var newOriginalFreeText: String
}

struct SaveInDTO: Codable {
    var bericht: KontaktberichtDTO
}

// MARK: - Mapping (DTO <-> Model)

private func dtoFromModel(_ bericht: Kontaktbericht) -> KontaktberichtDTO {
    let dateISO: String? = bericht.date.ISO8601Format()
    let idString = String(describing: bericht.id) // falls UUID: "\(uuid)"
    return KontaktberichtDTO(
        id: idString,
        ansprechpartner: bericht.ansprechpartner,
        typ: bericht.typ.rawValue,
        inhalt: bericht.inhalt,
        dateISO: dateISO
    )
}

private func modelFromDTO(_ dto: KontaktberichtDTO) -> Kontaktbericht {
    let typ: Gespraechstyp = Gespraechstyp(rawValue: dto.typ) ?? .telefon
    var bericht = Kontaktbericht(ansprechpartner: dto.ansprechpartner, typ: typ, inhalt: dto.inhalt)

    if let dateISO = dto.dateISO,
       let d = ISO8601DateFormatter().date(from: dateISO) {
        bericht.date = d
    }
    return bericht
}

struct ListOutDTO: Codable {
    var items: [KontaktberichtDTO]
}

struct DeleteInDTO: Codable {
    var id: String
}

// MARK: - Singleton Services

private final class KBContext {
    static let shared = KBContext()

    let store = KontaktberichtStore()
    let speicher = KontaktberichtSpeicherService()
    let llm = KontaktberichtLLMService()

    private var configured = false

    private init() {}

    func ensureConfigured() {
        if configured { return }

        let dir = AnsprechpartnerDirectory()
        llm.configure(directory: dir)
        configured = true
    }
}

// MARK: - Exported C ABI

/// freeText -> LLMResult (JSON)
@_cdecl("kb_extract_json")
public func kb_extract_json(_ inputJson: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    do {
        let input = try decodeJSON(ExtractInDTO.self, inputJson)
        KBContext.shared.ensureConfigured()

        let r = runBlocking {
            try await KBContext.shared.llm.extract(from: input.freeText)
        }

        switch r {
        case .success(let res):
            let dto = LLMResultDTO(
                bericht: dtoFromModel(res.bericht),
                pendingQuestion: res.pendingQuestion,
                pendingMissing: res.pendingMissing,
                toolDidCreate: res.toolDidCreate,
                toolDidClarify: res.toolDidClarify
            )
            return encodeJSON(dto)
        case .failure(let e):
            return encodeErrorJSON(String(describing: e))
        }
    } catch {
        return encodeErrorJSON("decode_failed")
    }
}

/// followupAnswer -> (LLMResult + newOriginalFreeText) (JSON)
@_cdecl("kb_answer_followup_json")
public func kb_answer_followup_json(_ inputJson: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    do {
        let input = try decodeJSON(FollowupInDTO.self, inputJson)
        KBContext.shared.ensureConfigured()

        let current = modelFromDTO(input.currentBericht)

        let r = runBlocking {
            try await KBContext.shared.llm.answerFollowup(
                originalFreeText: input.originalFreeText,
                followupAnswer: input.followupAnswer,
                currentBericht: current
            )
        }

        switch r {
        case .success(let tuple):
            let res = tuple.result
            let out = FollowupOutDTO(
                result: LLMResultDTO(
                    bericht: dtoFromModel(res.bericht),
                    pendingQuestion: res.pendingQuestion,
                    pendingMissing: res.pendingMissing,
                    toolDidCreate: res.toolDidCreate,
                    toolDidClarify: res.toolDidClarify
                ),
                newOriginalFreeText: tuple.newOriginalFreeText
            )
            return encodeJSON(out)
        case .failure(let e):
            return encodeErrorJSON(String(describing: e))
        }
    } catch {
        return encodeErrorJSON("decode_failed")
    }
}

/// Speichern in Store
@_cdecl("kb_save_json")
public func kb_save_json(_ inputJson: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    do {
        let input = try decodeJSON(SaveInDTO.self, inputJson)
        let bericht = modelFromDTO(input.bericht)

        KBContext.shared.speicher.save(bericht, store: KBContext.shared.store)
        return cstr("{\"ok\":true}")
    } catch {
        return encodeErrorJSON("decode_failed")
    }
}

@_cdecl("kb_list_json")
public func kb_list_json() -> UnsafeMutablePointer<CChar>? {
    KBContext.shared.ensureConfigured()

    // store.items -> DTO
    let items = KBContext.shared.store.items.map(dtoFromModel)

    // optional: sort by date desc
    let sorted = items.sorted { (a, b) in
        (a.dateISO ?? "") > (b.dateISO ?? "")
    }

    return encodeJSON(ListOutDTO(items: sorted))
}

@_cdecl("kb_delete_json")
public func kb_delete_json(_ inputJson: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    do {
        let input = try decodeJSON(DeleteInDTO.self, inputJson)

        // finde Index im Store anhand id-string
        if let idx = KBContext.shared.store.items.firstIndex(where: { String(describing: $0.id) == input.id }) {
            // Store-API verwenden (items ist private(set))
            KBContext.shared.store.remove(at: IndexSet(integer: idx))
            return cstr("{\"ok\":true}")
        } else {
            return cstr("{\"ok\":false,\"error\":\"not_found\"}")
        }

    } catch {
        return encodeErrorJSON("decode_failed")
    }
}
