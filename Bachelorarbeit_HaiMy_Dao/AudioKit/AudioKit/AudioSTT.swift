//
//  AudioSTT.swift
//  AudioKit
//
//  Created by Hai My Dao on 13.02.26.
//

import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
public final class AudioSTT: NSObject, ObservableObject {

    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var isAuthorized: Bool = false
    @Published var errorText: String?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale = Locale(identifier: "de-DE")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    public func requestPermissions() async {
        // Speech
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    switch status {
                    case .authorized: self?.isAuthorized = true
                    case .denied:     self?.errorText = "Spracherkennung wurde verweigert."
                    case .restricted: self?.errorText = "Spracherkennung auf diesem Gerät eingeschränkt."
                    case .notDetermined: self?.errorText = "Spracherkennung nicht freigegeben."
                    @unknown default: self?.errorText = "Unbekannter Speech-Status."
                    }
                    continuation.resume()
                }
            }
        }

        // Mikrofon
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            let micGranted: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                if #available(iOS 17.0, *) {
                    AVAudioApplication.requestRecordPermission { granted in
                        cont.resume(returning: granted)
                    }
                } else {
                    audioSession.requestRecordPermission { granted in
                        cont.resume(returning: granted)
                    }
                }
            }
            if !micGranted {
                errorText = "Mikrofonzugriff verweigert."
                isAuthorized = false
            }
        } catch {
            errorText = "Audio-Session Fehler: \(error.localizedDescription)"
            isAuthorized = false
        }
    }

    public func start() {
        guard !isRecording else { return }
        errorText = nil

        guard isAuthorized else {
            errorText = "Keine Berechtigung für Spracherkennung/Mikrofon."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Spracherkennung ist derzeit nicht verfügbar."
            return
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            errorText = "AudioEngine konnte nicht starten: \(error.localizedDescription)"
            cleanupAudio()
            return
        }

        task = recognizer.recognitionTask(with: request!) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                self.transcript = result.bestTranscription.formattedString
            }
            if let error = error {
                self.errorText = "STT-Fehler: \(error.localizedDescription)"
                self.stop()
            }
        }

        isRecording = true
    }

    public func stop() {
        guard isRecording else { return }
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        cleanupAudio()
        isRecording = false
    }

    public func resetTranscript() { transcript = "" }

    private func cleanupAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

