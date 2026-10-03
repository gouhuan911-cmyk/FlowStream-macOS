import Foundation

enum FFmpegLocatorError: Error, CustomStringConvertible {
    case bundleNotFound
    case binaryNotFound(String)

    var description: String {
        switch self {
        case .bundleNotFound:
            return "无法定位应用 bundle"
        case .binaryNotFound(let name):
            return "找不到 \(name)。请确保 ffmpeg / ffprobe 已在 bin/ 目录或系统 PATH 中。"
        }
    }
}

/// 定位 ffmpeg / ffprobe 可执行文件。
/// 优先顺序：
///   1. .app/Contents/MacOS/
///   2. 项目 bin/
///   3. 系统 PATH
enum FFmpegLocator {
    static func ffmpeg() throws -> URL { try locate("ffmpeg") }
    static func ffprobe() throws -> URL { try locate("ffprobe") }

    private static func locate(_ name: String) throws -> URL {
        // 1. .app/Contents/MacOS/（分发形态）
        if let bundle = Bundle.main.executableURL,
           bundle.lastPathComponent != name {
            let candidate = bundle.deletingLastPathComponent().appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // 2. 项目 bin/（开发形态）
        if let projectBin = projectBinDirectory() {
            let candidate = projectBin.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // 3. PathFinder 智能探测 (Homebrew / System PATH / 用户目录)
        if name == "ffmpeg", let p = PathFinder.shared.resolveFFmpegPath() {
            return URL(fileURLWithPath: p)
        }
        if name == "ffprobe", let p = PathFinder.shared.resolveFFprobePath() {
            return URL(fileURLWithPath: p)
        }

        // 4. 系统 PATH
        if let path = findInPATH(name) {
            return URL(fileURLWithPath: path)
        }

        throw FFmpegLocatorError.binaryNotFound(name)
    }

    /// 从当前可执行文件向上回溯，找到项目根目录下的 bin/
    private static func projectBinDirectory() -> URL? {
        var url = Bundle.main.bundleURL
        // CLI 调用时 Bundle.main 是 CLI 自己的路径；需要特殊处理
        if let exec = ProcessInfo.processInfo.arguments.first {
            url = URL(fileURLWithPath: exec)
        }

        // 向上找 Transmute/ 根目录
        for _ in 0..<6 {
            let binCandidate = url.appendingPathComponent("bin")
            if FileManager.default.fileExists(atPath: binCandidate.path) {
                return binCandidate
            }
            url = url.deletingLastPathComponent()
            if url.path == "/" { break }
        }
        return nil
    }

    private static func findInPATH(_ name: String) -> String? {
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let candidate = String(dir) + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
