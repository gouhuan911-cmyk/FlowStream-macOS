import Foundation

/// 编码方式：自动（能直拷就直拷）/ 硬件 / 软件
enum EncodeMode: String, CaseIterable, Codable, Sendable {
    case auto
    case hardware
    case software

    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .hardware: return "硬件加速"
        case .software: return "软件编码"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "能直接换容器就不重编码，速度最快"
        case .hardware: return "VideoToolbox 硬件编码，快 6 倍"
        case .software: return "libx264/libx265，体积最小"
        }
    }
}

enum PresetCategory: String, CaseIterable, Codable, Sendable {
    case video
    case audio
    case animation

    var displayName: String {
        switch self {
        case .video: return "视频"
        case .audio: return "音频"
        case .animation: return "动图"
        }
    }
}

struct Preset: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let category: PresetCategory
    let container: ContainerFormat
    let videoCodec: VideoCodec
    let audioCodec: AudioCodec
    var mode: EncodeMode
    /// 硬件编码质量档，1-100，越大越好（对应 ffmpeg -q:v）
    var videoQuality: Int
    /// 软件编码 CRF，0-51，越小越好
    var crf: Int
    /// 音频码率 kbps
    var audioBitrate: Int
    /// 输出最大宽度，nil 表示保持原始分辨率
    var maxWidth: Int?
    /// 原画质换壳：只要目标容器支持源编码就直拷，不改变编码。
    /// 为 true 时 videoCodec / audioCodec 仅作为"容器不支持时的兜底重编码目标"。
    /// 没有这个开关的话，「MKV 原画质」遇到 HEVC/VP9 源会被硬转成 H.264，预设承诺失效。
    var remux: Bool
    /// ProRes 档位：proxy / lt / standard / hq / 4444
    var proresProfile: String

    var summary: String {
        if container.isAudioOnly {
            return "\(audioCodec.displayName) · \(audioBitrate) kbps"
        }
        if container == .gif {
            return "GIF 动图"
        }
        return "\(videoCodec.displayName) · \(audioCodec.displayName)"
    }
}

// MARK: - 内置预设库

enum PresetLibrary {
    static let all: [Preset] = [
        Preset(
            id: "mp4-h264",
            name: "MP4 (H.264)",
            symbol: "film",
            category: .video,
            container: .mp4,
            videoCodec: .h264,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 20,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "mp4-h264-hw",
            name: "MP4 (H.264 硬)",
            symbol: "cpu",
            category: .video,
            container: .mp4,
            videoCodec: .h264,
            audioCodec: .aac,
            // 明确走 VideoToolbox，适合快速输出兼容 MP4
            mode: .hardware,
            videoQuality: 65,
            crf: 20,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "mp4-hevc",
            name: "MP4 (HEVC)",
            symbol: "film.stack",
            category: .video,
            container: .mp4,
            videoCodec: .hevc,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 24,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "mp4-hevc-hw",
            name: "MP4 (HEVC 硬)",
            symbol: "cpu",
            category: .video,
            container: .mp4,
            videoCodec: .hevc,
            audioCodec: .aac,
            mode: .hardware,
            videoQuality: 65,
            crf: 24,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "mov-prores",
            name: "MOV (ProRes)",
            symbol: "sparkles.tv",
            category: .video,
            container: .mov,
            videoCodec: .prores,
            audioCodec: .aac,
            // ProRes VideoToolbox 在部分素材/分辨率下会失败（profile 不兼容），
            // 统一走 prores_ks 软件编码，稳定性优先。
            mode: .software,
            videoQuality: 70,
            crf: 0,
            audioBitrate: 192,
            remux: false,
            // standard = ProRes 422，1080p 约 147 Mbps；
            // hq 档体积直接翻倍，对消费级转换场景不划算。
            proresProfile: "standard"
        ),
        Preset(
            id: "mkv-remux",
            name: "MKV (原画质)",
            symbol: "shippingbox",
            category: .video,
            container: .mkv,
            // remux=true：尽力直拷源编码（HEVC/VP9/AV1 都照拷），
            // 这里的 h264/aac 仅在容器不支持源编码时才作为兜底重编码目标。
            videoCodec: .h264,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 20,
            audioBitrate: 192,
            remux: true,
            proresProfile: "standard"
        ),
        Preset(
            id: "webm-vp9",
            name: "WebM (VP9)",
            symbol: "globe",
            category: .video,
            container: .webm,
            videoCodec: .vp9,
            audioCodec: .opus,
            mode: .software,
            videoQuality: 65,
            crf: 32,
            audioBitrate: 128,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "avi-compatible",
            name: "AVI (兼容)",
            symbol: "tv",
            category: .video,
            container: .avi,
            videoCodec: .mpeg4,
            audioCodec: .mp3,
            mode: .software,
            videoQuality: 65,
            // mpeg4 编码器不支持 -crf（实测被静默忽略），
            // 走 -q:v 质量档：crf 值直接映射为 q:v（1-31，越小越好）。
            // 实测 6 秒 1080p：q:v4=24Mbps / q:v6=15Mbps / q:v8=11Mbps，取 6 兼顾兼容与体积。
            crf: 6,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "mov-dnxhd",
            name: "MOV (DNxHD)",
            symbol: "photo.stack",
            category: .video,
            container: .mov,
            videoCodec: .dnxhd,
            audioCodec: .pcm_s16le,
            mode: .software,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 0,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "mkv-h264",
            name: "MKV (H.264)",
            symbol: "shippingbox",
            category: .video,
            container: .mkv,
            videoCodec: .h264,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 20,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "mkv-hevc",
            name: "MKV (HEVC)",
            symbol: "shippingbox",
            category: .video,
            container: .mkv,
            videoCodec: .hevc,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 24,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "webm-vp8",
            name: "WebM (VP8)",
            symbol: "globe",
            category: .video,
            container: .webm,
            videoCodec: .vp8,
            audioCodec: .vorbis,
            mode: .software,
            videoQuality: 65,
            crf: 10,
            audioBitrate: 128,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "ts-h264",
            name: "TS (H.264)",
            symbol: "server.rack",
            category: .video,
            container: .ts,
            videoCodec: .h264,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 20,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "flv-h264",
            name: "FLV (H.264)",
            symbol: "play.rectangle",
            category: .video,
            container: .flv,
            videoCodec: .h264,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 20,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "wmv-wmv2",
            name: "WMV",
            symbol: "window.horizontal",
            category: .video,
            container: .wmv,
            videoCodec: .wmv2,
            audioCodec: .wmav2,
            mode: .software,
            videoQuality: 65,
            // wmv2 走 -q:v（1-31，越小越好），取 4 兼顾画质与体积
            crf: 4,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "m4v-h264",
            name: "M4V (H.264)",
            symbol: "airplayvideo",
            category: .video,
            container: .m4v,
            // M4V 就是 MP4，只是扩展名不同（iTunes / Apple TV 用它区分是否含 DRM）
            videoCodec: .h264,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 20,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "mov-hevc",
            name: "MOV (HEVC)",
            symbol: "film.stack",
            category: .video,
            container: .mov,
            videoCodec: .hevc,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 24,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "m2ts-h264",
            name: "M2TS (蓝光)",
            symbol: "opticaldisc",
            category: .video,
            container: .m2ts,
            // BDAV 规范：H.264 视频 + AC-3 音轨，192 字节包
            videoCodec: .h264,
            audioCodec: .ac3,
            mode: .software,
            videoQuality: 65,
            crf: 20,
            audioBitrate: 448,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "mpg-mpeg2",
            name: "MPG (MPEG-2)",
            symbol: "tv.inset.filled",
            category: .video,
            container: .mpg,
            // MPEG-PS：DVD / 车载碟机 / 老电视只认 MPEG-2 视频 + MP2 音频
            videoCodec: .mpeg2,
            audioCodec: .mp2,
            mode: .software,
            videoQuality: 65,
            // mpeg2video 只认 -q:v（1-31，越小越好）。
            // 实测 30 秒 1080p 素材（源 40.5MB），-q:v 与 SSIM / 体积 / 复用告警的关系：
            //   q3: 87.6MB  SSIM 高  但 6603 行 "buffer underflow" 告警（硬件机必卡）
            //   q8: 37.4MB  SSIM 0.9803   27 行告警
            //   q10: 30.8MB SSIM 0.9763    0 行告警  ← 选它
            //   q12: 26.3MB SSIM 0.9725
            // q10 只比 q5 掉 0.4% SSIM，却换来零告警 + 0.76x 源体积，兼容性最优。
            crf: 10,
            audioBitrate: 224,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "audio-mp3",
            name: "提取 MP3",
            symbol: "music.note",
            category: .audio,
            container: .mp3,
            videoCodec: .h264,
            audioCodec: .mp3,
            mode: .auto,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 320,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "audio-m4a",
            name: "提取 M4A",
            symbol: "music.note.list",
            category: .audio,
            container: .m4a,
            videoCodec: .h264,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 256,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "audio-wav",
            name: "提取 WAV",
            symbol: "waveform",
            category: .audio,
            container: .wav,
            videoCodec: .h264,
            audioCodec: .pcm_s16le,
            mode: .software,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 0,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "audio-aac",
            name: "提取 AAC",
            symbol: "music.note",
            category: .audio,
            container: .m4a,
            videoCodec: .h264,
            audioCodec: .aac,
            mode: .auto,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 256,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "audio-flac",
            name: "提取 FLAC",
            symbol: "music.note",
            category: .audio,
            container: .flac,
            videoCodec: .h264,
            audioCodec: .flac,
            mode: .auto,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 0,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "audio-opus",
            name: "提取 Opus",
            symbol: "music.note",
            category: .audio,
            container: .opus,
            videoCodec: .h264,
            audioCodec: .opus,
            mode: .auto,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 128,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "audio-ogg",
            name: "提取 OGG",
            symbol: "music.note",
            category: .audio,
            container: .ogg,
            videoCodec: .h264,
            audioCodec: .vorbis,
            mode: .auto,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 192,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "audio-aiff",
            name: "提取 AIFF",
            symbol: "waveform.path",
            category: .audio,
            container: .aiff,
            videoCodec: .h264,
            // AIFF 是大端 PCM；用小端会被播放器识别为噪音或静音
            audioCodec: .pcm_s16be,
            mode: .auto,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 0,
            remux: false,
            proresProfile: "standard"
        ),
        Preset(
            id: "gif",
            name: "转 GIF",
            symbol: "photo.on.rectangle.angled",
            category: .animation,
            container: .gif,
            videoCodec: .h264,
            audioCodec: .aac,
            mode: .software,
            videoQuality: 65,
            crf: 0,
            audioBitrate: 0,
            remux: false,
            proresProfile: "standard"
        )
    ]

    static func preset(id: String) -> Preset? {
        all.first { $0.id == id }
    }

    static func presets(in category: PresetCategory) -> [Preset] {
        all.filter { $0.category == category }
    }

    /// 音频页专用的输出预设列表。
    static var audioPresets: [Preset] {
        all.filter { $0.category == .audio }
    }
}
