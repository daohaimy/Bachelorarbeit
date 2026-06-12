//
//  KontaktberichtAudioService.swift
//  AudioKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation

public enum MicTarget { case freeText, followup }

public protocol KontaktberichtAudioServiceProtocol {
    var stt: AudioSTT { get }
    var tts: AudioTTS { get }
    var activeMic: MicTarget? { get }

    func toggleFreeTextMic()
    func toggleFollowupMic()

    func handleTranscriptChange(
        _ newValue: String,
        onFreeText: (String) -> Void,
        onFollowup: (String) -> Void
    )

    func handlePendingQuestionChanged(ttsAutoSpeak: Bool, question: String?)
    func handleTtsSpeakingChanged(onResumeMic: (MicTarget) -> Void)
}

@MainActor
public final class KontaktberichtAudioService: KontaktberichtAudioServiceProtocol {
    public init() {}
    
    public private(set) var stt = AudioSTT(locale: .init(identifier: "de-DE"))
    public private(set) var tts = AudioTTS()

    public private(set) var activeMic: MicTarget?
    private var lastMicBeforeTts: MicTarget?
    private var resumeSttAfterTts = false

    // MARK: - Mic toggles

    public func toggleFreeTextMic() {
        if tts.isSpeaking { tts.stop() }

        if activeMic == .freeText, stt.isRecording {
            // Aufnahme beenden
            stt.stop()
            activeMic = nil
        } else {
            // ggf. andere Aufnahme stoppen
            if stt.isRecording { stt.stop() }
            stt.resetTranscript()
            activeMic = .freeText
            stt.start()
        }
    }

    public func toggleFollowupMic() {
        if tts.isSpeaking { tts.stop() }

        if activeMic == .followup, stt.isRecording {
            stt.stop()
            activeMic = nil
        } else {
            if stt.isRecording { stt.stop() }
            stt.resetTranscript()
            activeMic = .followup
            stt.start()
        }
    }

    // MARK: - STT Transcript nach außen geben

    public func handleTranscriptChange(
        _ newValue: String,
        onFreeText: (String) -> Void,
        onFollowup: (String) -> Void
    ) {
        guard stt.isRecording else { return }
        switch activeMic {
        case .freeText:  onFreeText(newValue)
        case .followup:  onFollowup(newValue)
        case .none:      break
        }
    }

    // MARK: - TTS / Frage vorlesen

    public func handlePendingQuestionChanged(ttsAutoSpeak: Bool, question: String?) {
        guard ttsAutoSpeak, let q = question else { return }

        if stt.isRecording {
            stt.stop()
            lastMicBeforeTts = activeMic
            resumeSttAfterTts = true
        }
        tts.speak(q)
    }

    public func handleTtsSpeakingChanged(onResumeMic: (MicTarget) -> Void) {
        if !tts.isSpeaking, resumeSttAfterTts {
            resumeSttAfterTts = false
            if let toResume = lastMicBeforeTts {
                activeMic = toResume
                onResumeMic(toResume)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.stt.start()
                }
            }
            lastMicBeforeTts = nil
        }
    }
    
    public func stopAll() {
        stt.stop()
        tts.stop()
        activeMic = nil
        lastMicBeforeTts = nil
        resumeSttAfterTts = false
    }
}
