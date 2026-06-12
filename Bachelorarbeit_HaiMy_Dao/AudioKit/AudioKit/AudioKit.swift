//
//  AudioKit.swift
//  AudioKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import Combine

@MainActor
public final class AudioKitFacade: ObservableObject {

    public static let shared = AudioKitFacade()

    public let service: KontaktberichtAudioService

    // Für UI/Caller praktisch:
    @Published public private(set) var transcript: String = ""
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var activeMic: MicTarget? = nil
    @Published public private(set) var lastError: String? = nil

    private var cancellables = Set<AnyCancellable>()

    public init(service: KontaktberichtAudioService? = nil) {
            self.service = service ?? KontaktberichtAudioService()
            wire()
        }

    // MARK: - Permissions

    public func requestPermissions() async -> Bool {
        await service.stt.requestPermissions()
        syncState()
        if let err = service.stt.errorText { lastError = err }
        return service.stt.isAuthorized
    }

    // MARK: - Mic

    public func toggleFreeTextMic() {
        service.toggleFreeTextMic()
        syncState()
    }

    public func toggleFollowupMic() {
        service.toggleFollowupMic()
        syncState()
    }

    public func stopAll() {
        service.stopAll()
        syncState()
    }

    // MARK: - TTS

    public func speak(_ text: String) {
        service.tts.speak(text)
        syncState()
    }

    public func stopSpeak() {
        service.tts.stop()
        syncState()
    }

    public func speakPendingQuestionAuto(question: String?, auto: Bool = true) {
        service.handlePendingQuestionChanged(ttsAutoSpeak: auto, question: question)
        syncState()
    }

    // MARK: - Internal wiring

    private func wire() {
        service.stt.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] t in
                guard let self else { return }
                self.transcript = t
            }
            .store(in: &cancellables)

        service.stt.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] r in
                self?.isRecording = r
            }
            .store(in: &cancellables)

        service.stt.$errorText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] e in
                if let e { self?.lastError = e }
            }
            .store(in: &cancellables)

        service.tts.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in
                guard let self else { return }
                self.isSpeaking = s

                // Resume-Logik wie in Service:
                self.service.handleTtsSpeakingChanged { resumedMic in
                    self.activeMic = resumedMic
                }
            }
            .store(in: &cancellables)

        // initial
        syncState()
    }

    private func syncState() {
        isAuthorized = service.stt.isAuthorized
        activeMic = service.activeMic
        // isRecording/isSpeaking werden ohnehin durch Combine aktualisiert
    }
}
