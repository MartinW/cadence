import Foundation

/// Wraps raw PCM bytes in a minimal RIFF/WAVE header so AVAudioPlayer can
/// play them. We only ever consume PCM16 from gpt-4o-audio-preview, so the
/// header is a fixed 44 bytes — no need for a general-purpose WAV writer.
///
/// Reference: http://soundfile.sapp.org/doc/WaveFormat/
enum WAVPacker {
    static func wrap(
        pcmData: Data,
        sampleRate: UInt32,
        channels: UInt16,
        bitsPerSample: UInt16 = 16
    ) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let riffSize = dataSize + 36 // 44-byte header minus the leading "RIFF" + size = 36

        var header = Data(capacity: 44)
        header.append("RIFF".asciiBytes)
        header.append(le32(riffSize))
        header.append("WAVE".asciiBytes)
        header.append("fmt ".asciiBytes)
        header.append(le32(16)) // fmt chunk size for PCM
        header.append(le16(1)) // audio format = PCM
        header.append(le16(channels))
        header.append(le32(sampleRate))
        header.append(le32(byteRate))
        header.append(le16(blockAlign))
        header.append(le16(bitsPerSample))
        header.append("data".asciiBytes)
        header.append(le32(dataSize))

        var output = Data(capacity: header.count + pcmData.count)
        output.append(header)
        output.append(pcmData)
        return output
    }

    private static func le16(_ value: UInt16) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 2)
    }

    private static func le32(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 4)
    }
}

private extension String {
    var asciiBytes: Data {
        // RIFF/WAVE/fmt /data are all ASCII-safe; force-unwrap is fine.
        data(using: .ascii)!
    }
}
