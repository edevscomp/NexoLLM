import AVFoundation
import XCTest
@testable import NexoLLM

/// Opt-in end-to-end check of the Audio Context engine (needs a Whisper model and two 16 kHz WAV files):
///   NEXO_WHISPER_DIR=/path/with/ggml-small-q5_1.bin+it.wav+en.wav swift test --filter WhisperLiveTests
final class WhisperLiveTests: XCTestCase {
    private func samples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    }

    func testTranscribesItalianAndEnglishOnDevice() throws {
        guard let dir = ProcessInfo.processInfo.environment["NEXO_WHISPER_DIR"] else { throw XCTSkip("set NEXO_WHISPER_DIR") }
        let base = URL(fileURLWithPath: dir)
        let model = try FileManager.default.contentsOfDirectory(atPath: dir).first { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }
        let engine = WhisperEngine()
        defer { engine.shutdown() }
        let loaded = expectation(description: "load")
        var ok = false
        engine.load(path: base.appendingPathComponent(try XCTUnwrap(model)).path) { ok = $0; loaded.fulfill() }
        wait(for: [loaded], timeout: 60)
        XCTAssertTrue(ok)
        for (file, lang, word) in [("it.wav", "it", "derivat"), ("en.wav", "en", "derivative")] {
            let audio = try samples(base.appendingPathComponent(file))
            let done = expectation(description: file)
            var result: WhisperEngine.Result?
            let t0 = Date()
            engine.transcribe(audio, language: nil) { result = $0; done.fulfill() }
            wait(for: [done], timeout: 60)
            FileHandle.standardError.write(Data(("WHISPER-RESULT \(file): " + String(format: "%.2fs", Date().timeIntervalSince(t0)) + " [\(result?.language ?? "-")] \(result?.text ?? "nil")\n").utf8))
            print("whisper \(file): \(String(format: "%.2fs", Date().timeIntervalSince(t0))) [\(result?.language ?? "-")] \(result?.text ?? "nil")")
            XCTAssertEqual(result?.language, lang)
            XCTAssertTrue(result?.text.lowercased().contains(word) == true, result?.text ?? "nil")

            // The same phrase as heard from two meters away in an echoey room: −40 dB, three reflections and
            // room noise, then through the far-field gain control exactly as the microphone path does.
            var far = audio.map { $0 * 0.01 }
            for (delay, gain) in [(480, Float(0.6)), (1120, 0.4), (2400, 0.25)] {
                for i in stride(from: far.count - 1, through: delay, by: -1) { far[i] += audio[i - delay] * 0.01 * gain }
            }
            var seed: UInt32 = 1
            far = far.map { v in seed = seed &* 1_664_525 &+ 1_013_904_223; return v + (Float(seed >> 8) / Float(1 << 24) - 0.5) * 0.0006 }
            let agc = AmbientGain()
            let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            var boosted: [Float] = []
            for k in stride(from: 0, to: far.count, by: 2048) {
                let n = min(2048, far.count - k)
                let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
                b.frameLength = AVAudioFrameCount(n)
                for i in 0..<n { b.floatChannelData![0][i] = far[k + i] }
                let out = agc.process(b).buffer
                boosted += Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: n))
            }
            let farDone = expectation(description: file + " far")
            var farResult: WhisperEngine.Result?
            engine.transcribe(boosted, language: nil) { farResult = $0; farDone.fulfill() }
            wait(for: [farDone], timeout: 60)
            FileHandle.standardError.write(Data("WHISPER-RESULT \(file) far-field: [\(farResult?.language ?? "-")] \(farResult?.text ?? "nil")\n".utf8))
            XCTAssertEqual(farResult?.language, lang)
            XCTAssertTrue(farResult?.text.lowercased().contains(word) == true, farResult?.text ?? "nil")

            // The microphone path cuts this phrase out of the stream on its own (speech detection after the gain).
            var seg = SpeechSegmenter(threshold: 0.02)
            var cut: [Float]?
            for chunk in stride(from: 0, to: boosted.count, by: 4000).map({ Array(boosted[$0..<min(boosted.count, $0 + 4000)]) })
                + [[Float](repeating: 0, count: 16_000)] {
                if case .final(let s) = seg.append(chunk) { cut = (cut ?? []) + s }
            }
            XCTAssertNotNil(cut, "the segmenter never closed the phrase")
            XCTAssertGreaterThan(cut?.count ?? 0, boosted.count / 2)
        }
    }
}
