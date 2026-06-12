//
//  AudioKitFFI.swift
//  AudioKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import Darwin
import Dispatch

@_cdecl("ak_free")
public func ak_free(_ ptr: UnsafeMutablePointer<CChar>?) {
    guard let ptr else { return }
    free(ptr)
}

private func cstr(_ s: String) -> UnsafeMutablePointer<CChar>? { strdup(s) }

private func encode(_ obj: Any) -> UnsafeMutablePointer<CChar>? {
    if let data = try? JSONSerialization.data(withJSONObject: obj),
       let s = String(data: data, encoding: .utf8) {
        return cstr(s)
    }
    return cstr("{\"error\":\"encode_failed\"}")
}

private func decodeDict(_ c: UnsafePointer<CChar>?) -> [String: Any] {
    guard let c else { return [:] }
    let str = String(cString: c)
    guard let data = str.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let dict = obj as? [String: Any] else { return [:] }
    return dict
}

private func runBlocking<T>(_ work: @escaping () async -> T) -> T {
    let sem = DispatchSemaphore(value: 0)
    var out: T! = nil
    Task { out = await work(); sem.signal() }
    sem.wait()
    return out
}

@MainActor
private final class AKContext {
    static let shared = AKContext()
    let kit = AudioKitFacade.shared
    private init() {}
}

// exported functions

@_cdecl("ak_request_permissions_json")
public func ak_request_permissions_json() -> UnsafeMutablePointer<CChar>? {

    let sem = DispatchSemaphore(value: 0)
    var result = false

    Task { @MainActor in
        result = await AKContext.shared.kit.requestPermissions()
        sem.signal()
    }

    sem.wait()

    return cstr("{\"ok\":\(result ? "true" : "false")}")
}



@_cdecl("ak_toggle_mic_json")
public func ak_toggle_mic_json(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let dict = decodeDict(input)
    let target = (dict["target"] as? String) ?? "freeText"

    runBlocking { @MainActor in
        if target == "followup" {
            AKContext.shared.kit.toggleFollowupMic()
        } else {
            AKContext.shared.kit.toggleFreeTextMic()
        }
    }
    return encode(["ok": true])
}


@_cdecl("ak_stop_stt_json")
public func ak_stop_stt_json() -> UnsafeMutablePointer<CChar>? {
    Task { @MainActor in AKContext.shared.kit.stopAll() }
    return encode(["ok": true])
}

@_cdecl("ak_speak_json")
public func ak_speak_json(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let dict = decodeDict(input)
    let text = (dict["text"] as? String) ?? ""
    Task { @MainActor in AKContext.shared.kit.speak(text) }
    return encode(["ok": true])
}

@_cdecl("ak_stop_speak_json")
public func ak_stop_speak_json() -> UnsafeMutablePointer<CChar>? {
    Task { @MainActor in AKContext.shared.kit.stopSpeak() }
    return encode(["ok": true])
}


private struct AudioStateDTO: Codable, Sendable {
    var isAuthorized: Bool
    var activeMic: String // "freeText" | "followup" | "none"
    var isRecording: Bool
    var isSpeaking: Bool
    var transcript: String
    var error: String?
}


@_cdecl("ak_get_state_json")
public func ak_get_state_json() -> UnsafeMutablePointer<CChar>? {
    let dto = runMainBlocking { @MainActor in
        let kit = AKContext.shared.kit

        let mic: String = {
            switch kit.activeMic {
            case .freeText: return "freeText"
            case .followup: return "followup"
            case .none: return "none"
            }
        }()

        return AudioStateDTO(
            isAuthorized: kit.isAuthorized,
            activeMic: mic,
            isRecording: kit.isRecording,
            isSpeaking: kit.isSpeaking,
            transcript: kit.transcript,
            error: kit.lastError
        )
    }

    return encodeDTO(dto)
}

private func runMainBlocking<T: Sendable>(_ work: @escaping @MainActor @Sendable () async -> T) -> T {
    let sem = DispatchSemaphore(value: 0)
    var out: T! = nil
    Task { @MainActor in
        out = await work()
        sem.signal()
    }
    sem.wait()
    return out
}

private func encodeDTO<T: Encodable>(_ value: T) -> UnsafeMutablePointer<CChar>? {
    do {
        let data = try JSONEncoder().encode(value)
        return cstr(String(data: data, encoding: .utf8) ?? "{}")
    } catch {
        return cstr("{\"error\":\"encode_failed\"}")
    }
}

