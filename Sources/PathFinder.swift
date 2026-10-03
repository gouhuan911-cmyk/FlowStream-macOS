import Foundation

/// 负责探测 Apple Silicon / Intel 架构下的 yt-dlp 与 ffmpeg 可执行文件路径
/// 并提供安全构建子进程环境变量的能力
public final class PathFinder {
    public static let shared = PathFinder()
    
    private init() {}
    
    /// 寻找 yt-dlp 可执行路径
    /// 优先级：Apple Silicon (/opt/homebrew/bin) -> Intel (/usr/local/bin) -> 常见用户路径与 PATH
    public func resolveYtDlpPath() -> String? {
        let candidatePaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            "/bin/yt-dlp",
            NSHomeDirectory() + "/.local/bin/yt-dlp",
            NSHomeDirectory() + "/Library/Python/3.9/bin/yt-dlp",
            NSHomeDirectory() + "/Library/Python/3.10/bin/yt-dlp",
            NSHomeDirectory() + "/Library/Python/3.11/bin/yt-dlp",
            NSHomeDirectory() + "/Library/Python/3.12/bin/yt-dlp"
        ]
        
        for path in candidatePaths {
            if isExecutable(atPath: path) {
                return path
            }
        }
        
        return searchInSystemPath(binaryName: "yt-dlp")
    }
    
    /// 寻找 ffmpeg 可执行路径
    /// 优先级：Apple Silicon (/opt/homebrew/bin) -> Intel (/usr/local/bin) -> 常见用户路径与 PATH
    public func resolveFFmpegPath() -> String? {
        let candidatePaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            "/bin/ffmpeg",
            NSHomeDirectory() + "/.local/bin/ffmpeg"
        ]
        
        for path in candidatePaths {
            if isExecutable(atPath: path) {
                return path
            }
        }
        
        return searchInSystemPath(binaryName: "ffmpeg")
    }
    
    /// 寻找 ffprobe 可执行路径
    /// 优先级：Apple Silicon (/opt/homebrew/bin) -> Intel (/usr/local/bin) -> 常见用户路径与 PATH
    public func resolveFFprobePath() -> String? {
        let candidatePaths = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe",
            "/bin/ffprobe",
            NSHomeDirectory() + "/.local/bin/ffprobe"
        ]
        
        for path in candidatePaths {
            if isExecutable(atPath: path) {
                return path
            }
        }
        
        return searchInSystemPath(binaryName: "ffprobe")
    }
    
    /// 检查指定路径是否存在且具备可执行权限
    public func isExecutable(atPath path: String) -> Bool {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
            return fileManager.isExecutableFile(atPath: path)
        }
        return false
    }
    
    /// 从当前 PATH 环境变量遍历搜寻二进制程序
    private func searchInSystemPath(binaryName: String) -> String? {
        let fileManager = FileManager.default
        let pathVar = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = pathVar.components(separatedBy: ":")
        
        for dir in dirs {
            let fullPath = (dir as NSString).appendingPathComponent(binaryName)
            if fileManager.fileExists(atPath: fullPath) && fileManager.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }
    
    /// 手动构建 Process 执行所需的环境变量字典
    /// 关键防坑：GUI 应用启动时往往缺少 Homebrew 路径，必须显式把 /opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin 注入 PATH
    public func makeInjectedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        
        let customPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            NSHomeDirectory() + "/.local/bin"
        ]
        
        let injectedPathPrefix = customPaths.joined(separator: ":")
        if let existingPath = env["PATH"], !existingPath.isEmpty {
            env["PATH"] = "\(injectedPathPrefix):\(existingPath)"
        } else {
            env["PATH"] = injectedPathPrefix
        }
        
        // 确保字符编码使用 UTF-8，防止子进程中文乱码
        env["LC_ALL"] = "en_US.UTF-8"
        env["LANG"] = "en_US.UTF-8"
        
        return env
    }
    
    /// 探测当前系统的运行环境就绪状态
    public func checkEnvironment() -> EnvironmentStatus {
        let ytdlp = resolveYtDlpPath()
        let ffmpeg = resolveFFmpegPath()
        let isReady = (ytdlp != nil) && (ffmpeg != nil)
        return EnvironmentStatus(ytdlpPath: ytdlp, ffmpegPath: ffmpeg, isReady: isReady)
    }
}
