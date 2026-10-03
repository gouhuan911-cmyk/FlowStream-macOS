import Foundation

/// 单个转换任务的状态机。
final class TranscodeJob: ObservableObject, Identifiable, @unchecked Sendable {
    let id = UUID()
    /// 原始输入文件
    let inputURL: URL
    /// 用户指定的输出路径（可选，nil 表示自动命名）
    var outputURL: URL?
    /// 生成 outputURL 时所用的容器。切换预设后若容器变了，必须重新生成路径，
    /// 否则会出现"预设是 GIF 但输出文件仍叫 xxx.mp4"的错误。
    var outputContainer: ContainerFormat?
    /// 目标预设
    @Published var preset: Preset
    /// 当前任务状态
    @Published var state: State = .pending
    /// 进度 0.0 ~ 1.0
    @Published var progress: Double = 0
    /// 实时转码 FPS
    @Published var fps: Double = 0
    /// 实时转码倍速 (如 4.8x)
    @Published var speedText: String = ""
    /// 错误信息（失败时）
    @Published var errorMessage: String?
    /// 转换计划（探测后生成）
    @Published var plan: ConversionPlan?
    /// 探测信息
    @Published var mediaInfo: MediaInfo?
    /// 加密音乐解密后的临时文件。非加密文件为 nil。
    var decryptedURL: URL?
    /// 解密产物所在临时目录，任务结束或移除时必须清理，否则 /tmp 会堆积几十 MB 的解密副本。
    var tempDirectory: URL?

    enum State: String, Sendable {
        case pending    // 等待中
        case decrypting // 解密中（加密音乐专用）
        case analyzing  // 探测中
        case ready      // 已生成计划，准备转码
        case running    // 转码中
        case completed  // 完成
        case failed     // 失败
        case cancelled  // 已取消

        var label: String {
            switch self {
            case .pending:    return "等待中"
            case .decrypting: return "解密中"
            case .analyzing:  return "分析中"
            case .ready:      return "就绪"
            case .running:    return "转换中"
            case .completed:  return "完成"
            case .failed:     return "失败"
            case .cancelled:  return "已取消"
            }
        }
    }

    init(inputURL: URL, preset: Preset) {
        self.inputURL = inputURL
        self.preset = preset
    }

    var fileName: String { inputURL.lastPathComponent }

    /// 真正交给 ffmpeg 的输入：加密音乐用解密产物，其余用原文件。
    var effectiveInputURL: URL { decryptedURL ?? inputURL }

    /// 源文件的格式标签。加密音乐直接显示格式名，
    /// 此时文件还没解密，mediaInfo 拿不到任何信息。
    var sourceFormatLabel: String {
        if let format = AudioDecryptor.format(of: inputURL) {
            return format.displayName
        }
        return inputURL.pathExtension.uppercased()
    }

    /// 时长文本。未探测时返回空串，让 UI 自行决定要不要占位。
    var durationLabel: String {
        mediaInfo?.durationLabel ?? ""
    }

    /// 是否为需要解密的加密音乐
    var isEncryptedSource: Bool {
        AudioDecryptor.isEncrypted(inputURL)
    }

    var resolutionLabel: String {
        guard let v = mediaInfo?.video else { return "" }
        return v.resolutionLabel
    }

    var strategyLabel: String {
        plan?.humanReadable ?? ""
    }

    /// 本次转换会保留 / 丢弃什么。nil 表示还没探测完，UI 不显示徽章。
    /// 视图层只负责把这个摘要画出来，判定逻辑全部在引擎层。
    var retentionSummary: RetentionSummary? {
        plan?.retentionSummary
    }

    var isHardwareAccelerated: Bool {
        plan?.videoStrategy == .transcodeHardware
    }

    var isDirectCopy: Bool {
        plan?.videoStrategy == .copy
    }

    var formattedProgress: String {
        "\(Int(progress * 100))%"
    }
}
