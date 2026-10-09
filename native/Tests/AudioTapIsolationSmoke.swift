import AVFoundation
import Foundation

private final class BackgroundAudioTap: @unchecked Sendable {
    private let callback: (AVAudioPCMBuffer, AVAudioTime) -> Void
    private let buffer: AVAudioPCMBuffer
    private let time: AVAudioTime
    private let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var callbackRanOnMainThread = false

    init(callback: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void, buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        self.callback = callback
        self.buffer = buffer
        self.time = time
    }

    func invoke() {
        callback(buffer, time)
        lock.lock()
        callbackRanOnMainThread = Thread.isMainThread
        lock.unlock()
        finished.signal()
    }

    func waitForCallback() -> DispatchTimeoutResult {
        finished.wait(timeout: .now() + .seconds(2))
    }

    var ranOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return callbackRanOnMainThread
    }
}

@main
struct AudioTapIsolationSmoke {
    @MainActor
    static func main() throws {
        let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)!
        converter.primeMethod = .none

        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 1024)!
        buffer.frameLength = 1024
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = 0.1 * sin(2 * .pi * 440 * Float(index) / 48_000)
        }

        let speechObserved = DispatchSemaphore(value: 0)
        let failureObserved = DispatchSemaphore(value: 0)
        var measuredLevel: Double = 0
        let processor = NativeAudioTapProcessor(
            converter: converter,
            targetFormat: targetFormat,
            moonshine: MoonshineEngine(),
            stream: 1,
            callbacks: DispatchGroup(),
            onSpeech: { speechObserved.signal() },
            onLevel: { measuredLevel = $0 },
            onFailure: { _ in failureObserved.signal() }
        )
        let backgroundTap = BackgroundAudioTap(
            callback: processor.tapBlock,
            buffer: buffer,
            time: AVAudioTime(sampleTime: 0, atRate: 48_000)
        )

        DispatchQueue(label: "org.vocoapp.Voco.audio-callback-smoke").async {
            backgroundTap.invoke()
        }

        guard backgroundTap.waitForCallback() == .success else {
            throw NativeError.unavailable("The audio tap callback did not return from its background queue.")
        }
        guard !backgroundTap.ranOnMainThread else {
            throw NativeError.unavailable("The audio tap callback ran on the main thread.")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard speechObserved.wait(timeout: .now()) == .success else {
            throw NativeError.unavailable("The converted speech audio did not trigger the main-actor speech callback.")
        }
        guard measuredLevel > 0.4, measuredLevel <= 1 else {
            throw NativeError.unavailable("The audio tap did not deliver the expected normalized microphone level.")
        }
        guard failureObserved.wait(timeout: .now()) == .timedOut else {
            throw NativeError.unavailable("The audio callback reported an unexpected failure.")
        }
        print("audio tap callback converted audio off-main and delivered speech notification on the main actor")
    }
}
