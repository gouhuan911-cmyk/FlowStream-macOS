import Foundation

// MARK: - 编解码与容器枚举

enum VideoCodec: String, CaseIterable, Codable, Sendable {
    case h264
    case hevc
    case mpeg4
    case vp8
    case vp9
    case av1
    case prores
    case mjpeg
    case dnxhd
    case wmv2
    case mpeg2   // DVD / 蓝光 BDAV / 数字电视广播
    case mpeg1   // VCD / 老式车载播放器

    var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC / H.265"
        case .mpeg4: return "MPEG-4"
        case .vp8: return "VP8"
        case .vp9: return "VP9"
        case .av1: return "AV1"
        case .prores: return "ProRes"
        case .mjpeg: return "MJPEG"
        case .dnxhd: return "DNxHD"
        case .wmv2: return "WMV2"
        case .mpeg2: return "MPEG-2"
        case .mpeg1: return "MPEG-1"
        }
    }

    /// VideoToolbox 硬件编码器名称。nil 表示无硬件编码器，只能软编。
    var hardwareEncoder: String? {
        switch self {
        case .h264: return "h264_videotoolbox"
        case .hevc: return "hevc_videotoolbox"
        case .prores: return "prores_videotoolbox"
        default: return nil
        }
    }

    /// 软件编码器名称。
    var softwareEncoder: String? {
        switch self {
        case .h264: return "libx264"
        case .hevc: return "libx265"
        case .mpeg4: return "mpeg4"
        case .vp8: return "libvpx"
        case .vp9: return "libvpx-vp9"
        case .av1: return "libaom-av1"
        case .prores: return "prores_ks"
        case .mjpeg: return "mjpeg"
        case .dnxhd: return "dnxhd"
        case .wmv2: return "wmv2"
        case .mpeg2: return "mpeg2video"
        case .mpeg1: return "mpeg1video"
        }
    }

    /// 是否支持 -crf 恒定质量模式。
    /// 实测：mpeg4 与 prores_ks 传 -crf 只会被 ffmpeg 静默忽略并打印
    /// "Codec AVOption crf ... has not been used for any stream"，导致质量参数完全失效。
    var supportsCRF: Bool {
        switch self {
        case .h264, .hevc, .vp9, .av1: return true
        default: return false
        }
    }

    /// 是否使用 -q:v 质量档（1-31，越小越好）。
    /// mpeg1/2/4、mjpeg、wmv2 都不接受 -crf，只认 -q:v。
    var usesQScale: Bool {
        switch self {
        case .mpeg1, .mpeg2, .mpeg4, .mjpeg, .wmv2: return true
        default: return false
        }
    }

    /// 输出像素格式。nil 表示交给 ffmpeg 自动选择。
    /// ProRes 不支持 yuv420p，强制指定会被忽略并回退，应显式给 10bit 422。
    ///
    /// **8-bit 只是默认值**：源是 10-bit/HDR 时会改用 `highBitDepthPixelFormat`，
    /// 见 `ConversionPlanner.videoTranscodeArgs`，别在这里无脑改。
    var outputPixelFormat: String? {
        switch self {
        case .prores: return "yuv422p10le"
        case .dnxhd: return "yuv422p"
        default: return "yuv420p"
        }
    }

    /// 该编码器是否支持 10-bit 输出。
    ///
    /// **刻意不含 H.264**：libx264 虽然能输出 yuv420p10le，但要求 High10 profile，
    /// 绝大多数播放器、手机、浏览器和剪辑软件都不支持，用户拿到的是"放不出来"的文件。
    /// 10-bit 只在 HEVC / VP9 / AV1 上是安全的。
    var supportsHighBitDepth: Bool {
        switch self {
        case .hevc, .vp9, .av1: return true
        default: return false
        }
    }

    /// 高 bit 深度场景下的输出像素格式。
    var highBitDepthPixelFormat: String? {
        switch self {
        case .prores: return "yuv422p10le"
        case .hevc, .vp9, .av1: return "yuv420p10le"
        default: return outputPixelFormat  // H.264 等一律 8-bit
        }
    }
}

enum AudioCodec: String, CaseIterable, Codable, Sendable {
    case aac
    case mp3
    case flac
    case opus
    case alac
    case ac3
    case vorbis
    case wmav2
    case pcm_s16le
    case mp2        // MPEG-PS / TS 的标准音轨，MPG 容器必配
    case pcm_s16be  // AIFF 大端 PCM

    var displayName: String {
        switch self {
        case .aac: return "AAC"
        case .mp3: return "MP3"
        case .flac: return "FLAC"
        case .opus: return "Opus"
        case .alac: return "ALAC"
        case .ac3: return "AC-3"
        case .vorbis: return "Vorbis"
        case .wmav2: return "WMA"
        case .pcm_s16le: return "PCM"
        case .mp2: return "MP2"
        case .pcm_s16be: return "PCM（大端）"
        }
    }

    var softwareEncoder: String {
        switch self {
        case .aac: return "aac"
        case .mp3: return "libmp3lame"
        case .flac: return "flac"
        case .opus: return "libopus"
        case .alac: return "alac"
        case .ac3: return "ac3"
        case .vorbis: return "libvorbis"
        case .wmav2: return "wmav2"
        case .pcm_s16le: return "pcm_s16le"
        case .mp2: return "mp2"
        case .pcm_s16be: return "pcm_s16be"
        }
    }
}

enum ContainerFormat: String, CaseIterable, Codable, Sendable {
    case mp4
    case mov
    case mkv
    case webm
    case avi
    case gif
    case ts
    case flv
    case wmv
    case m4v    // iTunes / Apple TV 用的 MP4 变体
    case m2ts   // 蓝光 BDAV / AVCHD 摄像机
    case mpg    // MPEG-PS，老电视 / 车载 / DVD 播放机
    case mp3
    case m4a
    case wav
    case flac
    case opus
    case ogg
    case aiff   // Apple 无损音频

    var displayName: String { rawValue.uppercased() }

    var fileExtension: String { rawValue }

    var isAudioOnly: Bool {
        switch self {
        case .mp3, .m4a, .wav, .flac, .opus, .ogg, .aiff: return true
        default: return false
        }
    }

    /// 是否属于 MP4 家族：决定要不要加 faststart / hvc1 tag。
    var isMP4Family: Bool {
        switch self {
        case .mp4, .mov, .m4v: return true
        default: return false
        }
    }

    /// 容器是否能妥善承载多条音轨。
    ///
    /// AVI 名义上支持多轨但各播放器实现混乱（经常只能听到第一条），
    /// WebM 的多音轨支持至今不完善，这两类只保留第一条，避免产出"看起来有实际听不到"的文件。
    var supportsMultipleAudioTracks: Bool {
        switch self {
        case .mkv, .mp4, .mov, .m4v, .m2ts, .ts: return true
        default: return false
        }
    }

    /// 该容器允许直拷（-c copy）的视频编码集合（用 ffprobe 原始 codec 名）。
    /// 这是"秒转"判定的核心数据。
    ///
    /// 用原始名而非枚举，是为了正确处理未枚举的编码：
    /// 若把 "mpeg2video"、"vc1" 等归并成 .mpeg4，会得出"可以直拷进 MP4"的错误结论。
    var copyableVideoCodecNames: Set<String> {
        switch self {
        case .mp4, .mov:
            return ["h264", "hevc", "mpeg4", "mjpeg", "av1", "prores"]
        case .mkv:
            // Matroska 几乎通吃，这里覆盖常见视频编码（含未做成枚举的旧格式）
            return ["h264", "hevc", "mpeg4", "mjpeg", "av1", "prores",
                    "vp8", "vp9", "mpeg1video", "mpeg2video", "vc1", "wmv3",
                    "rv40", "theora", "ffv1", "h263", "dvvideo", "rawvideo", "png"]
        case .webm:
            return ["vp8", "vp9", "av1"]
        case .avi:
            // AVI 对 H.264/HEVC 直拷支持极差（播放器普遍认不出），刻意不放行，强制转码
            return ["mpeg4", "mjpeg", "mpeg1video", "mpeg2video", "h263",
                    "dvvideo", "rawvideo", "huffyuv"]
        case .ts:
            return ["h264", "hevc", "mpeg4", "mpeg2video"]
        case .flv:
            return ["h264"]
        case .wmv:
            return ["wmv2", "wmv3", "vc1"]
        case .m4v:
            // 就是 MP4，只是扩展名不同，规则完全一致
            return ["h264", "hevc", "mpeg4", "mjpeg", "av1"]
        case .m2ts:
            // BDAV 规范：主要装 H.264 / MPEG-2 / VC-1
            return ["h264", "hevc", "mpeg2video", "vc1"]
        case .mpg:
            // MPEG-PS 只认 MPEG-1/2 视频，H.264 进去播放器不认
            return ["mpeg1video", "mpeg2video"]
        case .gif:
            return []
        case .mp3, .m4a, .wav, .flac, .opus, .ogg, .aiff:
            return []
        }
    }

    var copyableAudioCodecNames: Set<String> {
        switch self {
        case .mp4, .mov, .m4a:
            return ["aac", "alac", "ac3", "eac3", "mp3"]
        case .mkv:
            return ["aac", "alac", "ac3", "eac3", "mp3", "flac", "opus",
                    "vorbis", "dts", "truehd", "pcm_s16le", "pcm_s24le"]
        case .webm:
            return ["opus", "vorbis"]
        case .avi:
            return ["mp3", "ac3", "pcm_s16le"]
        case .ts:
            return ["aac", "ac3", "mp3", "mp2"]
        case .flv:
            return ["aac", "mp3"]
        case .wmv:
            return ["wma2", "wmapro", "wmavoice", "mp3"]
        case .m4v:
            return ["aac", "alac", "ac3", "eac3", "mp3"]
        case .m2ts:
            return ["aac", "ac3", "mp3", "mp2", "pcm_s16le"]
        case .mpg:
            return ["mp2", "mp3", "ac3", "pcm_s16le"]
        case .mp3:
            return ["mp3"]
        case .wav:
            return ["pcm_s16le", "pcm_s24le", "pcm_u8"]
        case .flac:
            return ["flac"]
        case .opus:
            return ["opus"]
        case .ogg:
            return ["vorbis", "opus"]
        case .aiff:
            // AIFF 标准是大端 PCM
            return ["pcm_s16be", "pcm_s24be", "pcm_s16le"]
        case .gif:
            return []
        }
    }
}

// MARK: - 探测结果模型

struct VideoStreamInfo: Sendable {
    let codec: VideoCodec
    let rawCodecName: String
    let width: Int
    let height: Int
    let frameRate: Double
    let bitRate: Int64
    /// 是否为内嵌封面图（attached_pic）。封面不是真正的视频轨，必须排除。
    let isAttachedPic: Bool
    /// ffprobe 原始像素格式名，如 yuv420p / yuv420p10le。
    /// 用于判断源是否 10-bit —— HDR 素材转码若被降到 8-bit 会出现色带。
    let pixelFormat: String?

    /// 是否高 bit 深度（10/12-bit）。
    /// iPhone 的杜比视界、相机 HLG、蓝光原盘都是 10-bit。
    var isHighBitDepth: Bool {
        guard let pixelFormat else { return false }
        return pixelFormat.contains("p10") || pixelFormat.contains("p12")
            || pixelFormat.contains("p16")
    }

    /// 直拷判定用原始 codec 名比较，避免未知编码被错误归并。
    /// 例：ffprobe 报 "mpeg2video"，若 fallback 成 .mpeg4 就会得出错误的直拷结论。
    func isSameCodec(as target: VideoCodec) -> Bool {
        rawCodecName == target.rawValue
    }

    var resolutionLabel: String { "\(width)×\(height)" }
}

struct AudioStreamInfo: Sendable {
    let codec: AudioCodec
    let rawCodecName: String
    let sampleRate: Int
    let channels: Int
    let bitRate: Int64
}

struct MediaInfo: Sendable {
    let url: URL
    let duration: Double
    let sizeBytes: Int64
    let containerNames: [String]
    let video: VideoStreamInfo?
    let audio: AudioStreamInfo?
    let subtitleCount: Int
    /// 各字幕轨的原始编码名（subrip / mov_text / hdmv_pgs_subtitle …）。
    /// 决定字幕能否保留：MP4 只收文本字幕，图文字幕（PGS/DVD）转进去会直接失败。
    let subtitleCodecNames: [String]
    /// 音轨数量。>1 表示多语言音轨（中/英/日），全部保留，只取第一条会静默丢轨。
    let audioStreamCount: Int

    var fileName: String { url.lastPathComponent }

    var durationLabel: String {
        let total = Int(duration.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    var sizeLabel: String {
        let mb = Double(sizeBytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    var primaryContainer: ContainerFormat? {
        ContainerFormat(rawValue: url.pathExtension.lowercased())
    }

    /// 是否存在可用于转码的视频轨（排除内嵌封面图）。
    /// 音频文件即便带封面，也应视为"无视频"。
    var hasVideo: Bool {
        guard let video else { return false }
        return !video.isAttachedPic
    }

    /// 源是否 10-bit / HDR。用于避免转码时被降级到 8-bit 产生色带。
    var isHighBitDepth: Bool { video?.isHighBitDepth ?? false }

    /// 是否存在多条音轨。
    var hasMultipleAudioTracks: Bool { audioStreamCount > 1 }

    /// 是否存在字幕轨。
    var hasSubtitles: Bool { !subtitleCodecNames.isEmpty }
}

// MARK: - ffprobe JSON 解码结构（snake_case 自动转换）

private struct ProbeStream: Decodable {
    let codecName: String?
    let codecType: String?
    let width: Int?
    let height: Int?
    let sampleRate: String?
    let channels: Int?
    let bitRate: String?
    let rFrameRate: String?
    let pixFmt: String?
    let disposition: ProbeDisposition?
}

/// ffprobe -show_streams 输出的 disposition 块。
/// attachedPic=1 表示该视频轨是内嵌封面图。
private struct ProbeDisposition: Decodable {
    let attachedPic: Int?
}

private struct ProbeFormat: Decodable {
    let duration: String?
    let size: String?
    let formatName: String?
}

private struct ProbeResult: Decodable {
    let streams: [ProbeStream]?
    let format: ProbeFormat?
}

extension MediaInfo {
    /// 从 ffprobe -print_format json 的输出解析
    static func parse(json: Data, url: URL) throws -> MediaInfo {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(ProbeResult.self, from: json)

        let streams = result.streams ?? []

        var video: VideoStreamInfo?
        var audio: AudioStreamInfo?
        var subtitleCodecNames: [String] = []
        var audioStreamCount = 0

        for s in streams {
            switch s.codecType {
            case "video":
                guard video == nil else { continue }
                let raw = s.codecName ?? "unknown"
                let w = s.width ?? 0
                let h = s.height ?? 0
                // 关键：内嵌封面图（disposition.attached_pic=1）不是真正的视频轨。
                // 若当成视频处理，音频文件会被"转换"出一路 PNG/MJPEG 视频（已实测复现）。
                if s.disposition?.attachedPic == 1 { continue }
                video = VideoStreamInfo(
                    codec: VideoCodec(rawValue: raw) ?? .h264,
                    rawCodecName: raw,
                    width: w,
                    height: h,
                    frameRate: Self.parseFrameRate(s.rFrameRate),
                    bitRate: Int64(s.bitRate ?? "") ?? 0,
                    isAttachedPic: false,
                    pixelFormat: s.pixFmt
                )
            case "audio":
                // 只解析第一条的细节，但要**数清总条数**——
                // 多语言音轨（中/英/日）若只映射第一条，用户会在无感知的情况下丢轨。
                audioStreamCount += 1
                guard audio == nil else { continue }
                let raw = s.codecName ?? "unknown"
                audio = AudioStreamInfo(
                    codec: AudioCodec(rawValue: raw) ?? .aac,
                    rawCodecName: raw,
                    sampleRate: Int(s.sampleRate ?? "") ?? 0,
                    channels: s.channels ?? 0,
                    bitRate: Int64(s.bitRate ?? "") ?? 0
                )
            case "subtitle":
                subtitleCodecNames.append(s.codecName ?? "unknown")
            default:
                break
            }
        }

        let containerNames = (result.format?.formatName ?? "")
            .split(separator: ",")
            .map(String.init)

        return MediaInfo(
            url: url,
            duration: Double(result.format?.duration ?? "") ?? 0,
            sizeBytes: Int64(result.format?.size ?? "") ?? 0,
            containerNames: containerNames,
            video: video,
            audio: audio,
            subtitleCount: subtitleCodecNames.count,
            subtitleCodecNames: subtitleCodecNames,
            audioStreamCount: audioStreamCount
        )
    }

    private static func parseFrameRate(_ value: String?) -> Double {
        guard let value else { return 0 }
        let parts = value.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return parts.first ?? 0 }
        return parts[0] / parts[1]
    }
}
