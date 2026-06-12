//
//  AudioTTS.swift
//  AudioKit
//
//  Created by Hai My Dao on 13.02.26.
//

import AVFoundation
import Combine

public final class AudioTTS: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice

    override init() {
        self.voice =
            AVSpeechSynthesisVoice(language: "de-DE") ??
            AVSpeechSynthesisVoice(language: "de") ??
            AVSpeechSynthesisVoice(language: "en-US")!
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String,
               rate: Float = AVSpeechUtteranceDefaultSpeechRate,
               pitch: Float = 1.0,
               volume: Float = 1.0) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .spokenAudio,
                                    options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error (TTS): \(error)")
        }

        let u = AVSpeechUtterance(string: trimmed)
        u.voice = voice
        u.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        u.pitchMultiplier = min(max(pitch, 0.5), 2.0)
        u.volume = min(max(volume, 0.0), 1.0)

        synthesizer.speak(u)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate
    public func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart _: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }
    public func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
    public func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
