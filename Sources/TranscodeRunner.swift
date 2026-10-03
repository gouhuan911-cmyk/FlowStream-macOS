import Foundation

enum TranscodeError: Error, CustomStringConvertible {
    case launchFailed(Error)
    case cancelled
    case nonZeroExit(Int32, String)

    var description: String {
        switch self {
        case .launchFailed(let e):
            return "启动 ffmpeg 失败: \(e)"
        case .cancelled:
            return "转换已取消"
        case .nonZeroExit(let code, let err):
            return "ffmpeg 退出码 \(code): \(err)"
        }
    }
}

/// 实时进度行解析器。
/// ffmpeg -progress pipe:1 每行输出 key=value，解析 out_time_us、fps 与 speed。
struct ProgressInfo {
    var microseconds: Double?
    var fps: Double?
    var speed: String?
}

struct ProgressLineParser {
    private var buffer = ""

    mutating func feed(_ data: Data) -> ProgressInfo {
        guard let text = String(data: data, encoding: .utf8) else { return ProgressInfo() }
        buffer += text
        var lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        if !buffer.hasSuffix("\n") {
            buffer = String(lines.popLast() ?? "")
        } else {
            buffer = ""
        }

        var info = ProgressInfo()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("out_time_us=") {
                let value = trimmed.dropFirst("out_time_us=".count)
                info.microseconds = Double(value)
            } else if trimmed.hasPrefix("fps=") {
                let value = trimmed.dropFirst("fps=".count)
                info.fps = Double(value)
            } else if trimmed.hasPrefix("speed=") {
                let value = trimmed.dropFirst("speed=".count).trimmingCharacters(in: .whitespaces)
                info.speed = value
            }
        }
        return info
    }
}

/// 单个 ffmpeg 任务的运行器：启动、进度回调、取消。
/// 使用 POSIXSpawn（posix_spawn）而非 Foundation.Process，
/// 因为在沙箱环境中，Process 启动 ffmpeg 长时间任务会被异常 SIGTERM 终止。
final class TranscodeRunner {
    private var processPID: pid_t?
    private var isCancelled = false
    private let lock = NSLock()

    /// 运行 ffmpeg。
    /// - Parameters:
    ///   - arguments: 完整的 ffmpeg 参数数组（不含 argv[0]）
    ///   - duration: 输入文件总时长（秒），用于计算百分比
    ///   - progress: 进度回调 (百分比 0.0~1.0, 实时FPS, 实时倍速)，保证在主线程调用
    ///   - completion: 完成回调，保证在主线程调用
    func run(arguments: [String], duration: Double,
             progress: @escaping (Double, Double, String) -> Void,
             completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.lock.lock()
            self.isCancelled = false
            self.processPID = nil
            self.lock.unlock()

            do {
                let ffmpeg = try FFmpegLocator.ffmpeg()

                var parser = ProgressLineParser()
                var errorData = Data()
                var lastProgress: Double = -1
                var lastFPS: Double = 0
                var lastSpeed: String = ""

                let code = try POSIXSpawn.run(
                    executable: ffmpeg,
                    arguments: arguments,
                    stdoutHandler: { data in
                        let info = parser.feed(data)
                        if let f = info.fps { lastFPS = f }
                        if let s = info.speed, !s.isEmpty { lastSpeed = s }
                        if let us = info.microseconds, duration > 0 {
                            let pct = min(max(us / (duration * 1_000_000.0), 0.0), 1.0)
                            if abs(pct - lastProgress) > 0.005 || pct >= 1.0 || lastFPS > 0 {
                                lastProgress = pct
                                let currentFps = lastFPS
                                let currentSpeed = lastSpeed
                                DispatchQueue.main.async { progress(pct, currentFps, currentSpeed) }
                            }
                        }
                    },
                    stderrHandler: { data in
                        errorData.append(data)
                    },
                    pidCallback: { [weak self] pid in
                        self?.lock.lock()
                        self?.processPID = pid
                        let shouldKill = self?.isCancelled == true
                        self?.lock.unlock()
                        if shouldKill {
                            kill(pid, SIGTERM)
                        }
                    }
                )

                self.lock.lock()
                let cancelled = self.isCancelled
                self.processPID = nil
                self.lock.unlock()

                DispatchQueue.main.async {
                    if cancelled {
                        completion(.failure(TranscodeError.cancelled))
                    } else if code != 0 {
                        let err = String(data: errorData, encoding: .utf8) ?? "未知错误"
                        completion(.failure(TranscodeError.nonZeroExit(code, err)))
                    } else {
                        completion(.success(()))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(TranscodeError.launchFailed(error)))
                }
            }
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        if let pid = processPID, pid > 0 {
            kill(pid, SIGTERM)
        }
        lock.unlock()
    }
}
