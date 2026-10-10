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
        for (band, frequency) in [110.0, 180, 260, 380, 550, 790, 1_160, 1_680, 2_440, 3_500, 5_000].enumerated() {
            let tone = (0..<1024).map { Float(0.02 * sin(2 * .pi * frequency * Double($0) / 16_000)) }
            let meter = tone.withUnsafeBufferPointer { AudioMeter.measure($0, sampleRate: 16_000) }
            let strongest = meter.waveform.enumerated().max { $0.element < $1.element }!
            guard strongest.offset == band, strongest.element > 0.3,
                  meter.waveform.enumerated().filter({ $0.offset != band }).allSatisfy({ $0.element < strongest.element * 0.65 }) else {
                throw NativeError.unavailable("The microphone waveform did not isolate the measured \(frequency)Hz tone in bar \(band).")
            }
        }
        let noise = Array(repeating: Float(0.001), count: 704).withUnsafeBufferPointer { AudioMeter.measure($0, sampleRate: 16_000) }
        guard noise.level == 0, noise.waveform.allSatisfy({ $0 == 0 }) else {
            throw NativeError.unavailable("The microphone noise floor did not settle to silence.")
        }
        let quietTone = (0..<340).map { Float(0.006 * sin(2 * .pi * 440 * Double($0) / 16_000)) }
        let quietMeter = quietTone.withUnsafeBufferPointer { AudioMeter.measure($0, sampleRate: 16_000) }
        guard quietMeter.waveform[3] > 0.02 else {
            throw NativeError.unavailable("Quiet speech did not remain visible in its measured frequency band.")
        }
        let meterStart = ContinuousClock.now
        for _ in 0..<100 {
            _ = quietTone.withUnsafeBufferPointer { AudioMeter.measure($0, sampleRate: 16_000) }
        }
        let meterDuration = meterStart.duration(to: .now)
        guard meterDuration < .milliseconds(300) else {
            throw NativeError.unavailable("Frequency metering took too long for real-time microphone feedback.")
        }
        print("eleven measured frequency bands and silence: PASS; 100 microphone frames: \(meterDuration)")
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
        var measuredWaveform: [Double] = []
        let processor = NativeAudioTapProcessor(
            converter: converter,
            targetFormat: targetFormat,
            engine: MoonshineEngine(),
            stream: SpeechStreamID(),
            callbacks: DispatchGroup(),
            onSpeech: { speechObserved.signal() },
            onLevel: { level, waveform in measuredLevel = level; measuredWaveform = waveform },
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
        guard measuredWaveform.count == 11, measuredWaveform.allSatisfy({ $0 >= 0 && $0 <= 1 }),
              measuredWaveform[3] > 0.7, measuredWaveform[3] > measuredWaveform[9] * 2 else {
            throw NativeError.unavailable("The converted microphone buffer did not preserve independent frequency measurements.")
        }
        guard failureObserved.wait(timeout: .now()) == .timedOut else {
            throw NativeError.unavailable("The audio callback reported an unexpected failure.")
        }
        print("audio tap callback converted audio off-main and delivered speech notification on the main actor")
    }
}
