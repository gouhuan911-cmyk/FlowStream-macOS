import Foundation

/// 单次转换的完整计划。
struct ConversionPlan: Sendable {
    let inputURL: URL
    let outputURL: URL
    let preset: Preset
    let modeUsed: EncodeMode
    let videoStrategy: VideoStrategy
    let audioStrategy: AudioStrategy
    /// 探测到的源信息（位深 / 音轨数 / 字幕格式）。
    /// 参数构建需要这些信息：HDR 10-bit 不能被降到 8-bit，多轨不能只留第一条。
    let source: MediaInfo?

    enum VideoStrategy: Sendable {
        case copy
        case transcodeHardware
        case transcodeSoftware
        case drop
        case gif
    }

    enum AudioStrategy: Sendable {
        case copy
        case transcode
        case drop
    }

    /// 给用户看的简短说明。
    var humanReadable: String {
        switch (videoStrategy, audioStrategy) {
        case (.copy, .copy):
            return "直接换容器，不损失画质"
        case (.copy, .transcode):
            return "复制视频，重编码音频"
        case (.copy, .drop):
            // 源本身没有音轨（无声视频 / 纯字幕素材），不是"被丢弃"，文案要说清
            return "直接换容器，不损失画质（无音频轨）"
        case (.transcodeHardware, .copy):
            return "VideoToolbox 硬件编码视频，复制音频"
        case (.transcodeHardware, .transcode):
            return "VideoToolbox 硬件编码视频 + 音频"
        case (.transcodeSoftware, .copy):
            return "软件编码视频，复制音频"
        case (.transcodeSoftware, .transcode):
            return "软件编码视频 + 音频"
        case (.drop, .transcode):
            return "仅提取音频"
        case (.drop, .copy):
            return "仅提取音频（原音质）"
        case (.transcodeSoftware, .drop), (.transcodeHardware, .drop):
            return "仅转换视频（无音频）"
        case (.gif, .drop):
            return "转 GIF 动图"
        default:
            return "自定义转换"
        }
    }
}

// MARK: - 保留 / 降级 / 丢弃决策

/// 给用户看的转换后果说明。
///
/// 存在的理由：引擎一直在"静默地"做取舍——多轨只留第一条、字幕整轨丢弃、
/// 10-bit 降到 8-bit。用户拖进去一个中英日三轨带字幕的 MKV，转完发现少了东西，
/// 根本无从得知是自己操作错了还是软件有问题。这些说明把取舍摆到台面上。
struct RetentionNote: Sendable, Equatable {
    let text: String
    let kind: Kind

    enum Kind: String, Sendable, CaseIterable {
        /// 内容完整保留
        case kept
        /// 内容仍在，但质量/轨数下降
        case downgraded
        /// 内容被丢弃
        case dropped
    }
}

/// 字幕轨的处置决策。UI 说明与 ffmpeg 参数共用同一份判定——
/// 分成两个函数写迟早会漂移，漂移后就会出现"UI 说保留了实际没保留"这种最难查的 bug。
enum SubtitleDecision: Sendable {
    /// 直拷，不重编码
    case copy(count: Int)
    /// 转成目标编码（MP4 家族的 mov_text / WebM 的 webvtt）
    case transcode(count: Int, encoder: String)
    /// 丢弃，附原因
    case drop(count: Int, reason: String)
}

/// 音轨的处置决策。
enum AudioTrackDecision: Sendable {
    /// 保留全部音轨
    case all(count: Int)
    /// 只保留第一条，附原因
    case firstOnly(count: Int, reason: String)
}

/// 位深的处置决策。
enum BitDepthDecision: Sendable {
    /// 与位深无关（源是 8-bit，或输出没有视频轨）
    case notApplicable
    /// 直拷，位深原样不动
    case preservedByCopy
    /// 重编码但保住了高 bit 深度
    case preserved(pixelFormat: String)
    /// 被降到 8-bit，附原因
    case downgraded(reason: String)
}

/// 结构化的"保留情况"摘要，供 UI 直接渲染徽章。
///
/// 刻意只给事实、不给外观：颜色 / 图标 / 文案长短属于视图层，
/// 模型层一旦掺进 SwiftUI 的 Color 就没法被 CLI 目标编译了
/// （模型层与 CLI 共用，CLI 不链接 SwiftUI）。
struct RetentionSummary: Sendable {
    /// 源音轨条数
    let audioTrackCount: Int
    /// 音轨是否全部保留（false = 只保留第一条）
    let allAudioTracksKept: Bool
    /// 源字幕条数
    let subtitleCount: Int
    /// 字幕是否保留
    let subtitlesKept: Bool
    /// 源是否 10-bit
    let isHighBitDepth: Bool
    /// 10-bit 是否被保住（源不是 10-bit 时为 false）
    let highBitDepthPreserved: Bool
    /// 详细说明条目，用于 tooltip 与展开区
    let notes: [RetentionNote]

    var hasSubtitles: Bool { subtitleCount > 0 }
    var hasMultipleAudioTracks: Bool { audioTrackCount > 1 }

    /// 有没有"会丢东西"的情况，UI 用它决定是否高亮警示。
    var hasLoss: Bool {
        (hasMultipleAudioTracks && !allAudioTracksKept)
            || (hasSubtitles && !subtitlesKept)
            || (isHighBitDepth && !highBitDepthPreserved)
    }
}

extension ConversionPlan {
    /// 本次转换会保留什么、丢掉什么。视图层直接渲染这个摘要，不再自己推断。
    var retentionSummary: RetentionSummary {
        let audioCount = source?.audioStreamCount ?? 0
        let subtitleCount = source?.subtitleCodecNames.count ?? 0
        let highBit = source?.isHighBitDepth ?? false

        var allAudioKept = true
        if case .firstOnly = ConversionPlanner.audioTrackDecision(plan: self) {
            allAudioKept = false
        }

        var subtitlesKept = false
        switch ConversionPlanner.subtitleDecision(plan: self) {
        case .copy, .transcode: subtitlesKept = true
        case .drop:             subtitlesKept = false
        }

        var bitKept = false
        switch ConversionPlanner.bitDepthDecision(plan: self) {
        case .preservedByCopy, .preserved: bitKept = true
        case .notApplicable, .downgraded:  bitKept = false
        }

        return RetentionSummary(
            audioTrackCount: audioCount,
            allAudioTracksKept: allAudioKept,
            subtitleCount: subtitleCount,
            subtitlesKept: subtitlesKept,
            isHighBitDepth: highBit,
            highBitDepthPreserved: bitKept,
            notes: ConversionPlanner.retentionNotes(plan: self)
        )
    }
}

/// 根据输入文件、目标预设和显式模式，生成转换计划与 ffmpeg 参数。
struct ConversionPlanner {

    // MARK: - ffmpeg 参数构建

    /// 生成 ffmpeg 参数数组（不经过 shell，避免注入）。
    func makeArguments(plan: ConversionPlan) -> [String] {
        var args: [String] = []
        args += ["-y", "-progress", "pipe:1", "-nostats", "-hide_banner"]
        args += ["-i", plan.inputURL.path]

        // 显式流选择：
        //  - 大写 V 表示"排除内嵌封面图"的视频轨（实测：不加 -map 时，
        //    带封面的音频提取 MP3 会把封面编码成一路 png 视频塞进输出）
        //  - 显式 map 同时排除字幕轨，规避 PGS/DVB 字幕转不进 MP4 导致的整体失败
        args += streamMapArgs(plan: plan)

        switch plan.videoStrategy {
        case .copy:
            args += ["-c:v", "copy"]
        case .transcodeHardware:
            args += videoTranscodeArgs(plan: plan, hardware: true)
        case .transcodeSoftware:
            args += videoTranscodeArgs(plan: plan, hardware: false)
        case .drop:
            args += ["-vn"]
        case .gif:
            args += gifFilterArgs()
        }

        switch plan.audioStrategy {
        case .copy:
            args += ["-c:a", "copy"]
        case .transcode:
            args += audioTranscodeArgs(plan: plan)
        case .drop:
            args += ["-an"]
        }

        // 元数据：默认复制全局元数据
        args += ["-map_metadata", "0"]

        // MP4 家族把 moov 移到文件头部：
        // 实测不加此参数时 moov 位于文件末尾（7.49MB 处），浏览器/QuickTime
        // 必须把整个文件下载完才能开始播放；加上后位于第 36 字节。
        // M4V 就是 MP4，同样受益。
        if plan.preset.container.isMP4Family {
            args += ["-movflags", "+faststart"]
        }

        args.append(plan.outputURL.path)
        return args
    }

    private func streamMapArgs(plan: ConversionPlan) -> [String] {
        switch (plan.videoStrategy, plan.audioStrategy) {
        case (.drop, _):
            // 纯音频提取：MP3/FLAC 这类容器只有一个音轨槽位，只能取第一条
            return ["-map", "0:a:0?"]
        case (.gif, _):
            return ["-map", "0:V:0?"]
        case (_, .drop):
            // 无音轨输出（GIF 之外的静音视频），字幕照常保留
            return ["-map", "0:V:0?"] + subtitleMapArgs(plan: plan)
        default:
            // 大写 V = 排除内嵌封面图的视频轨；
            // 0:a?（不带序号）= **所有**音轨，多语言音轨必须全留，
            // 写成 0:a:0? 会让中/英/日三轨的番剧只剩中文一轨，且用户毫不知情。
            return ["-map", "0:V:0?"] + audioMapArgs(plan: plan) + subtitleMapArgs(plan: plan)
        }
    }

    /// 音轨映射。判定统一走 `audioTrackDecision`，这里只翻译成参数。
    private func audioMapArgs(plan: ConversionPlan) -> [String] {
        switch Self.audioTrackDecision(plan: plan) {
        case .all:       return ["-map", "0:a?"]
        case .firstOnly: return ["-map", "0:a:0?"]
        }
    }

    /// 字幕映射。判定统一走 `subtitleDecision`，这里只翻译成参数。
    private func subtitleMapArgs(plan: ConversionPlan) -> [String] {
        switch Self.subtitleDecision(plan: plan) {
        case .copy:
            return ["-map", "0:s?", "-c:s", "copy"]
        case .transcode(_, let encoder):
            return ["-map", "0:s?", "-c:s", encoder]
        case .drop:
            return []
        }
    }

    /// 文本类字幕编码（可以安全转进 MP4 家族）。
    private static let textSubtitleCodecs: Set<String> = [
        "srt", "subrip", "mov_text", "ass", "ssa", "webvtt", "text"
    ]

    // MARK: - 决策函数（参数与 UI 说明的唯一事实来源）

    /// 音轨保留决策。
    ///
    /// 单轨源一律返回 .all——UI 层只在 count > 1 时才展示，
    /// 否则会出现"保留全部 1 条音轨"这种傻话。
    static func audioTrackDecision(plan: ConversionPlan) -> AudioTrackDecision {
        let count = plan.source?.audioStreamCount ?? 0

        // 纯音频输出：MP3 / FLAC / WAV 这类容器只有一个音轨槽位
        if plan.videoStrategy == .drop {
            if count > 1 {
                return .firstOnly(count: count,
                                  reason: "\(plan.preset.container.displayName) 只能存放 1 条音轨")
            }
            return .all(count: count)
        }

        guard count > 1 else { return .all(count: count) }

        if plan.preset.container.supportsMultipleAudioTracks {
            return .all(count: count)
        }
        return .firstOnly(
            count: count,
            reason: "\(plan.preset.container.displayName) 的多音轨在各播放器上表现不一致"
        )
    }

    /// 字幕保留决策。
    ///
    /// 早先版本**完全不映射字幕**，理由是"规避 PGS/DVB 字幕转不进 MP4 导致整体失败"。
    /// 这个担心是对的，但一刀切太粗暴：MKV 通吃所有字幕格式，丢掉纯粹是损失。
    /// 现在的策略是按容器能力分级放行，宁可少留也不让转换失败。
    static func subtitleDecision(plan: ConversionPlan) -> SubtitleDecision {
        let codecs = plan.source?.subtitleCodecNames ?? []
        guard !codecs.isEmpty else { return .drop(count: 0, reason: "") }

        switch plan.preset.container {
        case .mkv:
            // Matroska 官方支持 SRT / ASS / PGS / DVD / VobSub 全部格式，直拷零风险
            return .copy(count: codecs.count)

        case .mp4, .mov, .m4v:
            // MP4 家族只收文本字幕。只要混了一条图文字幕就整体放弃——
            // 图文字幕（PGS / DVD）转进 MP4 会让 ffmpeg 直接报错，整个任务白跑。
            guard codecs.allSatisfy({ Self.textSubtitleCodecs.contains($0) }) else {
                return .drop(
                    count: codecs.count,
                    reason: "含图文字幕（\(Self.subtitleLabel(codecs))），装不进 \(plan.preset.container.displayName)"
                )
            }
            return .transcode(count: codecs.count, encoder: "mov_text")

        case .webm:
            guard codecs.allSatisfy({ $0 == "webvtt" }) else {
                return .drop(count: codecs.count,
                             reason: "WebM 只认 WebVTT 字幕，源是 \(Self.subtitleLabel(codecs))")
            }
            return .transcode(count: codecs.count, encoder: "webvtt")

        default:
            return .drop(count: codecs.count,
                         reason: "\(plan.preset.container.displayName) 的字幕支持不完善")
        }
    }

    /// 位深保留决策。
    static func bitDepthDecision(plan: ConversionPlan) -> BitDepthDecision {
        guard plan.source?.isHighBitDepth == true else { return .notApplicable }
        switch plan.videoStrategy {
        case .copy:
            return .preservedByCopy
        case .drop, .gif:
            // 输出没有视频轨（纯音频 / GIF），位深无从谈起
            return .notApplicable
        case .transcodeHardware, .transcodeSoftware:
            let codec = plan.preset.videoCodec
            if codec.supportsHighBitDepth, let fmt = codec.highBitDepthPixelFormat {
                return .preserved(pixelFormat: fmt)
            }
            // H.264 等刻意不支持：10-bit 需要 High10 profile，
            // 绝大多数播放器、浏览器和剪辑软件都不认，产出的文件是"放不出来"的
            return .downgraded(reason: "\(codec.displayName) 的 10-bit 兼容性差，主流播放器放不出来")
        }
    }

    /// 把 ffprobe 的字幕编码名翻译成人话，只用于"为什么丢字幕"的说明。
    private static func subtitleLabel(_ codecs: [String]) -> String {
        let labels = codecs.map { raw -> String in
            switch raw {
            case "subrip", "srt":                 return "SRT"
            case "mov_text":                      return "MOV 文本"
            case "ass", "ssa":                    return "ASS"
            case "webvtt":                        return "WebVTT"
            case "hdmv_pgs_subtitle":             return "PGS 图文"
            case "dvd_subtitle":                  return "DVD 图文"
            case "dvb_subtitle", "dvb_teletext":  return "DVB 图文"
            case "xsub":                          return "XSUB 图文"
            default:                              return raw
            }
        }
        // 去重后拼接，避免 3 条 SRT 显示成 "SRT、SRT、SRT"
        var seen: [String] = []
        for l in labels where !seen.contains(l) { seen.append(l) }
        return seen.joined(separator: "、")
    }

    /// 汇总成给用户看的说明条目。
    ///
    /// 存在的理由：引擎一直在"静默地"做取舍——多轨只留第一条、字幕整轨丢弃、
    /// 10-bit 降到 8-bit。用户拖进去一个中英日三轨带字幕的 MKV，转完发现少了东西，
    /// 根本无从判断是自己操作错了还是软件有问题。这些条目把取舍摆到台面上。
    static func retentionNotes(plan: ConversionPlan) -> [RetentionNote] {
        var notes: [RetentionNote] = []

        if plan.videoStrategy == .gif {
            let hasExtras = (plan.source?.audioStreamCount ?? 0) > 0
                || !(plan.source?.subtitleCodecNames.isEmpty ?? true)
            if hasExtras {
                notes.append(RetentionNote(text: "GIF 只保留画面，音轨与字幕不会写入",
                                           kind: .dropped))
            }
            return notes
        }

        switch Self.audioTrackDecision(plan: plan) {
        case .all(let count):
            if count > 1 {
                notes.append(RetentionNote(text: "保留全部 \(count) 条音轨", kind: .kept))
            }
        case .firstOnly(let count, let reason):
            notes.append(RetentionNote(
                text: "只保留第 1 条音轨，其余 \(count - 1) 条丢弃",
                kind: .dropped))
            notes.append(RetentionNote(text: reason, kind: .dropped))
        }

        switch Self.subtitleDecision(plan: plan) {
        case .copy(let count):
            notes.append(RetentionNote(text: "保留 \(count) 条字幕（原样拷贝）", kind: .kept))
        case .transcode(let count, let encoder):
            notes.append(RetentionNote(text: "保留 \(count) 条字幕（转为 \(encoder)）", kind: .kept))
        case .drop(let count, let reason):
            if count > 0 {
                notes.append(RetentionNote(text: "\(count) 条字幕将丢弃", kind: .dropped))
                notes.append(RetentionNote(text: reason, kind: .dropped))
            }
        }

        switch Self.bitDepthDecision(plan: plan) {
        case .notApplicable:
            break
        case .preservedByCopy:
            notes.append(RetentionNote(text: "10-bit 高色深原样保留（直拷）", kind: .kept))
        case .preserved(let pixelFormat):
            notes.append(RetentionNote(text: "保留 10-bit 高色深（\(pixelFormat)）", kind: .kept))
        case .downgraded(let reason):
            notes.append(RetentionNote(text: "源为 10-bit，输出将降到 8-bit", kind: .downgraded))
            notes.append(RetentionNote(text: reason, kind: .downgraded))
        }

        return notes
    }


    private func videoTranscodeArgs(plan: ConversionPlan, hardware: Bool) -> [String] {
        var args: [String] = []
        let preset = plan.preset

        // HEVC in MP4/MOV 需要 hvc1 tag，否则 Apple 设备放不了
        let needsHVC1 = preset.videoCodec == .hevc && (preset.container == .mp4 || preset.container == .mov)

        let encoder: String?
        if hardware {
            encoder = preset.videoCodec.hardwareEncoder
        } else {
            encoder = preset.videoCodec.softwareEncoder
        }

        guard let encoder else { return args }
        args += ["-c:v", encoder]

        if hardware {
            // VideoToolbox 完全不支持 -crf（会被静默忽略），只能用 -q:v 质量档
            args += ["-q:v", "\(preset.videoQuality)"]
        } else if preset.videoCodec.supportsCRF {
            args += ["-crf", "\(preset.crf)"]
        } else if preset.videoCodec.usesQScale {
            // mpeg4 / mjpeg 走 -q:v（1-31，越小越好）
            args += ["-q:v", "\(min(max(preset.crf, 1), 31))"]
        }
        // ProRes 用 profile 控制质量，不接任何质量参数

        if preset.videoCodec == .prores {
            args += ["-profile:v", preset.proresProfile]
        }

        // VideoToolbox 的 10-bit 必须显式指定 profile（实测踩坑，2026-09-02）：
        // 只给 -pix_fmt yuv420p10le 时 hevc_videotoolbox 输出的仍是 8-bit，
        // 而 ffprobe 还会在 profile 字段显示 "Main 10"——标签骗人，数据是 8-bit，
        // 光看 profile 根本发现不了，必须比对 pix_fmt。
        // 软件 libx265 不需要：它会根据 pix_fmt 自动切到 Main10。
        if hardware, preset.videoCodec == .hevc, case .preserved = Self.bitDepthDecision(plan: plan) {
            args += ["-profile:v", "main10"]
        }
        // DNxHD 必须显式给码率，否则 ffmpeg 会报 "Frame size must be 1080p/720p ..."
        if preset.videoCodec == .dnxhd {
            args += ["-b:v", "60M"]
        }
        if needsHVC1 {
            args += ["-tag:v", "hvc1"]
        }

        args += codecTuningArgs(preset: preset, hardware: hardware)

        // 缩放：宽度向下取偶，避免奇数宽在 yuv420p 下报错
        if let maxWidth = preset.maxWidth, maxWidth > 0 {
            args += ["-vf", "scale=w='floor(min(\(maxWidth),iw)/2)*2':h=-2:flags=lanczos"]
        }

        // 像素格式：ProRes 不支持 yuv420p（强制指定会被忽略并回退），显式给 10bit 422。
        //
        // ★ 10-bit 源必须保持 10-bit（实测踩坑）：
        // 之前无脑给 yuv420p，iPhone 杜比视界 / 相机 HLG / 蓝光原盘这类 10-bit 素材
        // 转 HEVC、VP9 后一律被压成 8-bit，天空与暗部渐变出现明显色带（banding）。
        // 但**不能**对 H.264 也开：10-bit H.264 需要 High10 profile，
        // 绝大多数播放器、浏览器和剪辑软件都不认，用户拿到的是"放不出来"的文件。
        let pixFmt: String?
        if case .preserved(let highDepthFormat) = Self.bitDepthDecision(plan: plan) {
            pixFmt = highDepthFormat
        } else {
            pixFmt = preset.videoCodec.outputPixelFormat
        }
        if let pixFmt {
            args += ["-pix_fmt", pixFmt]
        }

        return args
    }

    /// 编码器调优参数。VP9 不调优时 1080p 只有 0.2x 实时，用户会以为卡死。
    private func codecTuningArgs(preset: Preset, hardware: Bool) -> [String] {
        guard !hardware else { return [] }
        switch preset.videoCodec {
        case .vp9:
            // 实测（6 秒 1080p 素材）：默认 31s / 7.59MB；
            // 加 row-mt + cpu-used 3 后 13s / 7.73MB —— 快 2.4 倍，体积仅 +1.8%
            return ["-deadline", "good", "-cpu-used", "3", "-row-mt", "1"]
        case .av1:
            return ["-cpu-used", "6", "-row-mt", "1"]
        case .h264, .hevc:
            return ["-preset", "medium"]
        default:
            return []
        }
    }

    private func audioTranscodeArgs(plan: ConversionPlan) -> [String] {
        var args: [String] = ["-c:a", plan.preset.audioCodec.softwareEncoder]
        if plan.preset.audioBitrate > 0 {
            args += ["-b:a", "\(plan.preset.audioBitrate)k"]
        }
        return args
    }

    /// GIF 走两阶段调色板：先生成全局调色板，再用它抖动输出。
    /// 实测（6 秒 1080p 素材）体积对比：
    ///   bayer 抖动 3.04MB / sierra2_4a 3.39MB / fps12 4.07MB
    /// sierra2_4a 只比 bayer 大 11%，但能消除 bayer 特有的交叉网纹，画质提升明显，故选它。
    private func gifFilterArgs() -> [String] {
        return [
            "-vf", "fps=10,scale=w='floor(min(480,iw)/2)*2':h=-2:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=sierra2_4a",
            "-loop", "0"
        ]
    }

    // MARK: - 策略决策

    /// 判断一份输入+预设应该走什么策略。
    func plan(input: MediaInfo, outputURL: URL, preset: Preset, explicitMode: EncodeMode = .auto) -> ConversionPlan {
        let (videoStrategy, audioStrategy, effectiveMode) = decideStrategies(input: input, preset: preset, explicitMode: explicitMode)

        return ConversionPlan(
            inputURL: input.url,
            outputURL: outputURL,
            preset: preset,
            modeUsed: effectiveMode,
            videoStrategy: videoStrategy,
            audioStrategy: audioStrategy,
            source: input
        )
    }

    private func decideStrategies(input: MediaInfo, preset: Preset, explicitMode: EncodeMode) -> (ConversionPlan.VideoStrategy, ConversionPlan.AudioStrategy, EncodeMode) {
        // 音频-only 输出
        if preset.container.isAudioOnly {
            let audioStrategy = decideAudio(input: input, preset: preset, forceTranscode: false)
            return (.drop, audioStrategy, .software)
        }

        // GIF
        if preset.container == .gif {
            return (.gif, .drop, .software)
        }

        // 源没有可用视频轨（例如音频文件、或只有内嵌封面的文件）。
        // 注意这里不能返回 (.drop, .drop)：那会同时生成 -vn 和 -an，
        // ffmpeg 必然报 "Output file does not contain any stream"（已实测复现）。
        // 正确做法是退化成纯音频输出——MP3 拖进来选 MP4 预设，产出带 AAC 音轨的 MP4。
        guard input.hasVideo else {
            let audioStrategy = decideAudio(input: input, preset: preset, forceTranscode: true)
            return (.drop, audioStrategy, .software)
        }

        let sourceVideoRaw = input.video?.rawCodecName ?? ""
        let sourceAudioRaw = input.audio?.rawCodecName ?? ""
        let hasAudio = input.audio != nil

        // 直拷判定，全部基于 ffprobe 原始 codec 名：
        //  - remux 预设：容器支持源编码就照拷（这才是"原画质"的本意）
        //  - 普通预设：源编码必须等于目标编码，且容器支持
        var canCopyVideo: Bool
        if preset.remux {
            canCopyVideo = preset.container.copyableVideoCodecNames.contains(sourceVideoRaw)
        } else {
            canCopyVideo = (sourceVideoRaw == preset.videoCodec.rawValue)
                && preset.container.copyableVideoCodecNames.contains(sourceVideoRaw)
        }

        let canCopyAudio: Bool
        if preset.remux {
            canCopyAudio = hasAudio && preset.container.copyableAudioCodecNames.contains(sourceAudioRaw)
        } else {
            canCopyAudio = hasAudio
                && (sourceAudioRaw == preset.audioCodec.rawValue)
                && preset.container.copyableAudioCodecNames.contains(sourceAudioRaw)
        }

        // 若用户设置了最大宽度且源分辨率超出，必须重编码才能缩放
        if let maxWidth = preset.maxWidth, maxWidth > 0,
           let width = input.video?.width, width > maxWidth {
            canCopyVideo = false
        }

        // 显式模式处理：
        // - 命令行/UI 强制 hardware/software 直接生效
        // - auto 时：能直拷就直拷；不能直拷则先看预设自身模式，
        //   预设也没指定才优先硬件编码器
        var effectiveMode = explicitMode
        if explicitMode == .auto {
            if canCopyVideo {
                effectiveMode = .auto
            } else if preset.mode != .auto {
                effectiveMode = preset.mode
            } else {
                effectiveMode = (preset.videoCodec.hardwareEncoder != nil) ? .hardware : .software
            }
        }

        let videoStrategy: ConversionPlan.VideoStrategy
        if canCopyVideo {
            videoStrategy = .copy
        } else if effectiveMode == .hardware, preset.videoCodec.hardwareEncoder != nil {
            videoStrategy = .transcodeHardware
        } else {
            videoStrategy = .transcodeSoftware
        }

        let audioStrategy = decideAudio(input: input, preset: preset, forceTranscode: !canCopyAudio)

        return (videoStrategy, audioStrategy, effectiveMode)
    }

    private func decideAudio(input: MediaInfo, preset: Preset, forceTranscode: Bool) -> ConversionPlan.AudioStrategy {
        guard let audio = input.audio else { return .drop }

        if forceTranscode { return .transcode }

        // 多轨源进非 MKV 容器：强制转码，不能直拷。
        // 直拷会把每条音轨原样塞进去，第二轨若是 DTS / TrueHD 这类 MP4 不认的格式，
        // ffmpeg 会直接报错，整个任务失败——比只留一条轨的后果更糟。
        if input.hasMultipleAudioTracks,
           preset.container.supportsMultipleAudioTracks,
           preset.container != .mkv {
            return .transcode
        }

        // 容器要求固定音频编码（如 WebM 只能放 Opus）且源编码不一致，强制转码
        // 这些容器的播放器只认特定音轨，源编码不同就必须重编码，否则出的是"哑巴文件"
        let forcedCodecs: [ContainerFormat: AudioCodec] = [
            .webm: .opus,
            .mp3: .mp3,
            .wav: .pcm_s16le,
            .flac: .flac,
            .opus: .opus,
            .ogg: .vorbis,
            .aiff: .pcm_s16be,  // AIFF 标准是大端 PCM
            .mpg: .mp2,         // MPEG-PS 标准音轨，DVD/车载机只认这个
            .m2ts: .ac3         // BDAV 规范音轨，蓝光播放机兼容性最好
        ]
        if let forced = forcedCodecs[preset.container], forced != audio.codec {
            return .transcode
        }

        // 纯音频输出场景：forceTranscode 为 false，但源编码可能与目标不同
        // （例如 MP4 源提取 Opus），必须显式转码。
        if audio.codec != preset.audioCodec {
            return .transcode
        }

        // 走到这里说明源音频编码与目标一致且目标容器支持直拷
        return .copy
    }
}
