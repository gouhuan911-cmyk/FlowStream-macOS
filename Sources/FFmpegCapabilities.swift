import Foundation

/// ffmpeg 自身的实际能力：版本号与可用的 VideoToolbox 硬件编码器。
///
/// 存在的理由：界面上曾经写死 `"ffmpeg 6.0 已就绪"` 和 `"VideoToolbox 可用"`。
/// 前者在换掉二进制后会说谎，后者更离谱——VideoToolbox 编码器的可用性取决于
/// 这台机器上的 ffmpeg 构建，在无硬编的机器 / 虚拟机里那句话纯属编造。
/// 用户看到"硬件可用"却拿到软件编码的速度，第一反应是软件坏了。
///
/// 这里走引擎层而不是视图层，是为了让 CLI 也能测（`transmute-cli caps`）。
enum FFmpegCapabilities {

    /// 查询结果。所有字段都是"查过才知道"，没有默认值冒充结论。
    struct Report: Sendable {
        /// 形如 "ffmpeg version 6.0"，查询失败为 nil
        let versionLine: String?
        /// 可用的 VideoToolbox 编码器名（h264_videotoolbox / hevc_videotoolbox …）
        let videoToolboxEncoders: Set<String>

        /// 精简版本号，用于界面上的小徽章（"ffmpeg version 6.0" → "6.0"）。
        /// 查询失败返回 nil，绝不拿一个猜的数字冒充。
        var shortVersion: String? {
            guard let versionLine else { return nil }
            return versionLine.split(separator: " ").last.map(String.init)
        }

        var hasVideoToolbox: Bool { !videoToolboxEncoders.isEmpty }

        /// 界面徽章文案。硬件不可用时明确说"软件编码"，不假装硬件可用。
        var hardwareBadgeText: String {
            hasVideoToolbox ? "VideoToolbox 可用" : "软件编码（无硬件加速）"
        }
    }

    /// 缓存：ffmpeg -version / -encoders 都要起子进程，
    /// 空态界面每次出现都重新查一遍没必要，进程内查一次即可。
    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var report: Report?
        func get() -> Report {
            lock.lock()
            defer { lock.unlock() }
            if let report { return report }
            let fresh = FFmpegCapabilities.query()
            report = fresh
            return fresh
        }
    }

    /// 同步查询（内部会起 ffmpeg 子进程，别在主线程调）。
    static func current() -> Report {
        cache.get()
    }

    /// 异步查询，供 UI 在后台线程调用后回主线程刷新。
    static func currentAsync(completion: @escaping (Report) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let report = current()
            DispatchQueue.main.async { completion(report) }
        }
    }

    // MARK: - 实际查询

    static func query() -> Report {
        guard let ffmpeg = try? FFmpegLocator.ffmpeg() else {
            return Report(versionLine: nil, videoToolboxEncoders: [])
        }
        return Report(versionLine: versionLine(of: ffmpeg),
                      videoToolboxEncoders: videoToolboxEncoders(of: ffmpeg))
    }

    private static func versionLine(of ffmpeg: URL) -> String? {
        guard let out = try? POSIXSpawn.runAndCaptureStdout(executable: ffmpeg, arguments: ["-version"]).stdout,
              let text = String(data: out, encoding: .utf8),
              let first = text.split(separator: "\n").first else { return nil }
        let line = String(first)
        // 形如 "ffmpeg version 6.0 Copyright ..."，截到 Copyright 之前
        if let range = line.range(of: " Copyright") {
            return String(line[line.startIndex..<range.lowerBound])
        }
        return line
    }

    /// 从 `ffmpeg -encoders` 里挑出 videotoolbox 编码器。
    ///
    /// 只说明"这个 ffmpeg 构建编译进了硬编编码器"，不等于当前机器一定能硬编
    /// （还取决于 GPU / 驱动 / 系统版本）。但比起无条件宣称"可用"，已经诚实得多，
    /// 而且足以挡住"根本没编进硬编却告诉用户有硬件加速"这种最离谱的情况。
    private static func videoToolboxEncoders(of ffmpeg: URL) -> Set<String> {
        guard let out = try? POSIXSpawn.runAndCaptureStdout(
                executable: ffmpeg,
                arguments: ["-hide_banner", "-encoders"]).stdout,
              let text = String(data: out, encoding: .utf8) else { return [] }

        var found: Set<String> = []
        for line in text.split(separator: "\n") {
            // -encoders 每行形如 " V....D h264_videotoolbox  VideoToolbox H.264 Encoder"
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            // 至少要有 flags + 编码器名 + 描述
            guard fields.count >= 3 else { continue }
            let name = String(fields[1])
            guard name.hasSuffix("_videotoolbox") else { continue }
            // flags 列形如 "V....."：V=视频 / A=音频 / S=字幕。只要视频编码器。
            guard fields[0].contains("V") else { continue }
            found.insert(name)
        }
        return found
    }
}
