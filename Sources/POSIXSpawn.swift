import Foundation

enum POSIXSpawnError: Error, CustomStringConvertible {
    case pipeFailed
    case spawnFailed(Int32)
    case waitFailed

    var description: String {
        switch self {
        case .pipeFailed:
            return "创建 pipe 失败"
        case .spawnFailed(let code):
            return "posix_spawn 失败 (errno \(code))"
        case .waitFailed:
            return "waitpid 失败"
        }
    }
}

/// 基于 posix_spawn 的子进程封装。
/// 在沙箱环境中，Foundation.Process 启动 ffmpeg 长时间任务时会被 SIGTERM 异常终止，
/// 而 posix_spawn 可正常工作。这是本项目的关键工程坑。
struct POSIXSpawn {
    /// 同步运行一个外部程序。
    /// - Parameters:
    ///   - executable: 可执行文件完整路径
    ///   - arguments: 参数数组（不包含 argv[0]）
    ///   - environment: 环境变量，默认继承当前环境
    ///   - stdoutHandler: stdout 数据回调，每读到一块数据调用一次
    ///   - stderrHandler: stderr 数据回调
    /// - Returns: 子进程退出码
    @discardableResult
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        stdoutHandler: ((Data) -> Void)? = nil,
        stderrHandler: ((Data) -> Void)? = nil,
        pidCallback: ((pid_t) -> Void)? = nil
    ) throws -> Int32 {
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0, pipe(&errPipe) == 0 else {
            throw POSIXSpawnError.pipeFailed
        }

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)

        // 子进程 stdin 指到 /dev/null：ffmpeg 不需要输入，
        // 否则在 CLOEXEC_DEFAULT 下 fd 0 会被关闭，某些解码器会尝试读 stdin 而卡住。
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        // 子进程：stdout/err 重定向到 pipe 写端
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO)
        // 关闭子进程中不需要的 pipe fd
        posix_spawn_file_actions_addclose(&actions, outPipe[0])
        posix_spawn_file_actions_addclose(&actions, errPipe[0])
        posix_spawn_file_actions_addclose(&actions, outPipe[1])
        posix_spawn_file_actions_addclose(&actions, errPipe[1])

        defer {
            posix_spawn_file_actions_destroy(&actions)
        }

        // POSIX_SPAWN_CLOEXEC_DEFAULT：子进程只保留 file_actions 显式设置的 fd。
        // 不加这个的话，GUI 主进程打开的所有 fd（窗口资源、日志文件、临时文件等）
        // 都会被 ffmpeg 继承，既浪费描述符，也会让父进程无法真正释放这些资源。
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        defer {
            posix_spawnattr_destroy(&attr)
        }

        // argv[0] 为程序名
        var cArgs: [UnsafeMutablePointer<CChar>?] = [strdup(executable.lastPathComponent)]
        for arg in arguments {
            cArgs.append(strdup(arg))
        }
        cArgs.append(nil)
        defer {
            for ptr in cArgs { free(ptr) }
        }

        // envp
        let env = environment ?? ProcessInfo.processInfo.environment
        var cEnv: [UnsafeMutablePointer<CChar>?] = []
        for (key, value) in env {
            cEnv.append(strdup("\(key)=\(value)"))
        }
        cEnv.append(nil)
        defer {
            for ptr in cEnv { free(ptr) }
        }

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, executable.path, &actions, &attr, cArgs, cEnv)
        if spawnStatus != 0 {
            close(outPipe[0]); close(outPipe[1])
            close(errPipe[0]); close(errPipe[1])
            throw POSIXSpawnError.spawnFailed(spawnStatus)
        }

        // 启动成功后立即回调 pid（供外部 kill / 取消）
        pidCallback?(pid)

        // 父进程关闭写端
        close(outPipe[1])
        close(errPipe[1])

        // 后台读取 stdout
        let stdoutGroup = DispatchGroup()
        if let handler = stdoutHandler {
            stdoutGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { stdoutGroup.leave() }
                drainPipe(fd: outPipe[0], handler: handler)
            }
        } else {
            close(outPipe[0])
        }

        // 后台读取 stderr
        let stderrGroup = DispatchGroup()
        if let handler = stderrHandler {
            stderrGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { stderrGroup.leave() }
                drainPipe(fd: errPipe[0], handler: handler)
            }
        } else {
            close(errPipe[0])
        }

        // 同步等待子进程
        var status: Int32 = 0
        let waitResult = waitpid(pid, &status, 0)
        if waitResult < 0 {
            throw POSIXSpawnError.waitFailed
        }

        stdoutGroup.wait()
        stderrGroup.wait()

        let lower = status & 0x7f
        let upper = (status >> 8) & 0xff
        if lower == 0 {
            return upper                    // 正常退出
        } else if lower == 0x7f {
            return 255                      // 被 ptrace 停止，理论上不会出现
        } else {
            return 128 + lower              // 被信号终止（如 SIGTERM=15）
        }
    }

    /// 便捷方法：运行并返回完整 stdout。
    static func runAndCaptureStdout(executable: URL, arguments: [String], environment: [String: String]? = nil) throws -> (stdout: Data, stderr: Data, exitCode: Int32) {
        var stdoutData = Data()
        var stderrData = Data()
        let code = try run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            stdoutHandler: { stdoutData.append($0) },
            stderrHandler: { stderrData.append($0) }
        )
        return (stdoutData, stderrData, code)
    }

    private static func drainPipe(fd: Int32, handler: (Data) -> Void) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            handler(Data(buffer.prefix(Int(n))))
        }
        close(fd)
    }
}
