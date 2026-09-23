import Foundation
import Speech
import AVFoundation

protocol SpeechRecognitionServiceProtocol {
    func requestAuthorization() async -> Bool
    func startRecording() async throws -> String
    func stopRecording()
}

final class SpeechRecognitionService: SpeechRecognitionServiceProtocol {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording() async throws -> String {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.notAvailable
        }

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        self.recognitionRequest = recognitionRequest

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        return try await withCheckedThrowingContinuation { continuation in
            let task = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let error = error {
                    audioEngine.stop()
                    node.removeTap(onBus: 0)
                    continuation.resume(throwing: error)
                    return
                }

                if let result = result, result.isFinal {
                    audioEngine.stop()
                    node.removeTap(onBus: 0)
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
            self.recognitionTask = task
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        if let node = audioEngine?.inputNode {
            node.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
    }

    enum SpeechError: LocalizedError {
        case notAvailable

        var errorDescription: String? {
            switch self {
            case .notAvailable: return "语音识别不可用"
            }
        }
    }
}
