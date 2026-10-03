import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case launchFailed(Error)
    case nonZeroExit(Int32, String)
    case jsonParse(Error)

    var description: String {
        switch self {
        case .launchFailed(let e):
            return "启动 ffprobe 失败: \(e)"
        case .nonZeroExit(let code, let err):
            return "ffprobe 退出码 \(code): \(err)"
        case .jsonParse(let e):
            return "解析 ffprobe 输出失败: \(e)"
        }
    }
}

/// 封装 ffprobe 调用，把 JSON 输出转成 MediaInfo。
struct MediaProbe {
    func probe(url: URL) async throws -> MediaInfo {
        try probeSync(url: url)
    }

    func probeSync(url: URL) throws -> MediaInfo {
        let ffprobe = try FFmpegLocator.ffprobe()
        let (data, errData, code) = try POSIXSpawn.runAndCaptureStdout(
            executable: ffprobe,
            arguments: [
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                "-i", url.path
            ]
        )

        guard code == 0 else {
            let err = String(data: errData, encoding: .utf8) ?? "未知错误"
            throw ProbeError.nonZeroExit(code, err)
        }

        return try MediaInfo.parse(json: data, url: url)
    }
}
