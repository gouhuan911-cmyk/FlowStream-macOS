import Foundation
import WebKit

/// 负责调度与融合原生解析引擎（针对抖音原生 WebKit 绕过 Argus，针对小红书解析真实链接，针对通用平台调度 yt-dlp）
public final class YTDLPService {
    public static let shared = YTDLPService()
    
    private var currentDownloadProcess: Process?
    private var currentStdoutPipe: Pipe?
    private var currentStderrPipe: Pipe?
    private let processLock = NSLock()
    
    // 正则表达式预编译
    private let progressRegex: NSRegularExpression? = {
        let pattern = #"(?:\[download\])\s+([0-9.]+)%\s+of\s+~?\s*([0-9.]+\s*[A-Za-z]+)(?:\s+at\s+([0-9.]+\s*[A-Za-z]+/s))?(?:\s+ETA\s+([0-9:]+))?"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()
    
    private let destinationRegexes: [NSRegularExpression] = {
        let patterns = [
            #"\[Merger\] Merging formats into "([^"]+)""#,
            #"\[ExtractAudio\] Destination:\s+(.+)"#,
            #"\[download\] Destination:\s+(.+)"#,
            #"\[download\]\s+(.+?)\s+has already been downloaded"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()
    
    private init() {}
    
    // MARK: - 智能链接提取工具
    
    /// 从任意带有中文字符、表情包或分享口令的文案中，精准提取第一个合法 http/https 链接
    public static func extractCleanURL(from rawText: String) -> String {
        let urls = extractAllCleanURLs(from: rawText)
        return urls.first ?? rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 从任意文本中批量提取所有合法的 http/https 链接（去重并按出现次序排列）
    public static func extractAllCleanURLs(from rawText: String) -> [String] {
        let pattern = #"(https?://[a-zA-Z0-9\-\._~:/\?#\[\]@!$&'\(\)\*\+,;=%]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = rawText as NSString
        let matches = regex.matches(in: rawText, options: [], range: NSRange(location: 0, length: ns.length))
        var urls: [String] = []
        for m in matches {
            let u = ns.substring(with: m.range)
            if !urls.contains(u) {
                urls.append(u)
            }
        }
        return urls
    }
    
    // MARK: - 阶段一：元数据异步解析
    
    /// 统一入口：智能分流解析
    public func parseMetadata(rawInput: String, removeWatermark: Bool = true, cookieSource: BrowserCookieSource = .none) async throws -> VideoMetadata {
        // 1. 彻底提取出纯净 URL，去除各种“复制打开抖音/小红书”口令杂质
        let cleanURLString = YTDLPService.extractCleanURL(from: rawInput)
        guard let url = URL(string: cleanURLString) else {
            throw YTDLPError.executionFailed(message: "输入的文本中未检测到有效的网页视频链接。")
        }
        
        let host = url.host?.lowercased() ?? ""
        let fullPath = cleanURLString.lowercased()
        
        // 2. 针对微信视频号 (weixin.qq.com / channels.weixin.qq.com) 友好提示
        if host.contains("weixin.qq.com") || fullPath.contains("channels.weixin.qq.com") {
            throw YTDLPError.executionFailed(message: "微信视频号属于腾讯内部加密封闭生态，不支持通过公开链接直接下载。")
        }
        
        // 3. 针对哔哩哔哩 (bilibili.com / b23.tv) 启用官方开放 API 0.15 秒极速直通车！
        if host.contains("bilibili.com") || host.contains("b23.tv") {
            if let fastMeta = await fetchBilibiliFastMetadata(url: cleanURLString) {
                return fastMeta
            }
        }
        
        // 4. 针对爱奇艺 (iqiyi.com / pps.tv) 启用官方 TMTS 切片分发原生解析引擎
        if host.contains("iqiyi.com") || host.contains("pps.tv") {
            return try await IQIYINativeParser.shared.parse(url: url)
        }
        
        // 5. 针对抖音 (v.douyin.com / douyin.com / iesdouyin.com) 启用原生 WebKit 纯净原画无水印提取
        if host.contains("douyin.com") || host.contains("iesdouyin.com") {
            do {
                return try await DouyinNativeParser.shared.parse(url: url)
            } catch {
                // 原生解析如遇微弱延迟，自动立即复试一次
                do {
                    try await Task.sleep(nanoseconds: 400_000_000)
                    return try await DouyinNativeParser.shared.parse(url: url)
                } catch {
                    throw YTDLPError.executionFailed(message: "抖音视频原画解析超时，请稍后重试或检查链接有效性。")
                }
            }
        }
        
        // 6. 针对小红书 (xhslink.cn / xhslink.com / xiaohongshu.com) 进行短链接 0.16s 重定向穿透
        var targetURLString = cleanURLString
        if host.contains("xhslink") || host.contains("xiaohongshu") {
            targetURLString = await resolveXHSTargetURL(from: cleanURLString)
        }
        
        // 7. 调用通用 yt-dlp 引擎解析（支持 YouTube、小红书、快手、TikTok 等海量平台）
        return try await parseViaYTDLP(url: targetURLString, removeWatermark: removeWatermark, cookieSource: cookieSource)
    }
    
    /// Bilibili 官方开放接口 0.15 秒极速元数据解析
    private func fetchBilibiliFastMetadata(url: String) async -> VideoMetadata? {
        var target = url
        if url.contains("b23.tv") {
            target = await resolveXHSTargetURL(from: url)
        }
        
        var bvid: String? = nil
        var aid: String? = nil
        
        if let bvRange = target.range(of: "BV[a-zA-Z0-9]{10}", options: .regularExpression) {
            bvid = String(target[bvRange])
        } else if let avRange = target.range(of: "(?:av|aid=)([0-9]+)", options: .regularExpression) {
            let matched = String(target[avRange])
            aid = matched.replacingOccurrences(of: "av", with: "").replacingOccurrences(of: "aid=", with: "")
        }
        
        guard bvid != nil || aid != nil else { return nil }
        
        var apiURLString = "https://api.bilibili.com/x/web-interface/view?"
        if let b = bvid {
            apiURLString += "bvid=\(b)"
        } else if let a = aid {
            apiURLString += "aid=\(a)"
        }
        
        guard let apiURL = URL(string: apiURLString) else { return nil }
        
        var req = URLRequest(url: apiURL)
        req.timeoutInterval = 3.0
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            guard (res as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? Int, code == 0,
                  let dataObj = json["data"] as? [String: Any] else { return nil }
            
            let title = dataObj["title"] as? String ?? "哔哩哔哩视频"
            let pic = (dataObj["pic"] as? String)?.replacingOccurrences(of: "http://", with: "https://")
            let duration = dataObj["duration"] as? Double
            let owner = dataObj["owner"] as? [String: Any]
            let author = owner?["name"] as? String ?? "B站UP主"
            
            return VideoMetadata(
                url: target,
                title: title,
                duration: duration,
                durationString: nil,
                thumbnail: pic,
                uploader: author,
                channel: author,
                filesizeApprox: nil,
                directStreamURL: nil
            )
        } catch {
            return nil
        }
    }
    
    /// 毫秒级解析小红书短链并还原真实笔记地址（兼容 xhslink.cn 与 xhslink.com）
    private func resolveXHSTargetURL(from shortURLString: String) async -> String {
        guard let url = URL(string: shortURLString) else { return shortURLString }
        
        return await withCheckedContinuation { continuation in
            let delegate = XHSRedirectDelegate()
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4.0
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            
            let task = session.dataTask(with: req) { _, response, _ in
                session.finishTasksAndInvalidate()
                var finalURL = delegate.redirectedURL
                if finalURL == nil, let httpRes = response as? HTTPURLResponse {
                    finalURL = httpRes.url?.absoluteString
                }
                
                guard let target = finalURL else {
                    continuation.resume(returning: shortURLString)
                    return
                }
                
                // 检查是否包含 redirectPath 参数并解码
                if target.contains("redirectPath=") {
                    let pattern = #"redirectPath=([^&]+)"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: target, range: NSRange(location: 0, length: (target as NSString).length)) {
                        let encoded = (target as NSString).substring(with: match.range(at: 1))
                        if let decoded = encoded.removingPercentEncoding {
                            let full = decoded.hasPrefix("http") ? decoded : "https://www.xiaohongshu.com" + (decoded.hasPrefix("/") ? decoded : "/" + decoded)
                            continuation.resume(returning: full)
                            return
                        }
                    }
                }
                
                continuation.resume(returning: target)
            }
            task.resume()
        }
    }
    
    /// 底层 yt-dlp 元数据解析（极速优化版：移除 ffmpeg 扫描、注入 YouTube Android 协议、阻断预下载）
    private func parseViaYTDLP(url: String, removeWatermark: Bool, cookieSource: BrowserCookieSource = .none) async throws -> VideoMetadata {
        guard let ytdlpPath = PathFinder.shared.resolveYtDlpPath() else {
            throw YTDLPError.binaryNotFound(name: "yt-dlp")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ytdlpPath)
                process.environment = PathFinder.shared.makeInjectedEnvironment()
                
                var arguments = [
                    "--dump-single-json",
                    "--no-warnings",
                    "--no-playlist",
                    "--no-check-certificates",
                    "--retries", "1"
                ]
                
                if let browser = cookieSource.argumentValue {
                    arguments.append(contentsOf: ["--cookies-from-browser", browser])
                }
                
                // 针对 YouTube 注入 Android 客户端协议，免除繁重的 Web 端 JS 挑战解密，耗时减半
                if url.contains("youtube.com") || url.contains("youtu.be") {
                    arguments.append(contentsOf: [
                        "--extractor-args", "youtube:player_client=android"
                    ])
                }
                
                arguments.append(url)
                process.arguments = arguments
                
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: YTDLPError.executionFailed(message: "无法启动进程: \(error.localizedDescription)"))
                    return
                }
                
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    do {
                        let decoder = JSONDecoder()
                        var metadata = try decoder.decode(VideoMetadata.self, from: outData)
                        metadata = VideoMetadata(
                            url: url,
                            title: metadata.title,
                            duration: metadata.duration,
                            durationString: metadata.durationString,
                            thumbnail: metadata.thumbnail,
                            uploader: metadata.uploader,
                            channel: metadata.channel,
                            filesizeApprox: metadata.filesizeApprox,
                            directStreamURL: nil
                        )
                        continuation.resume(returning: metadata)
                    } catch {
                        let rawOutput = String(data: outData, encoding: .utf8) ?? ""
                        continuation.resume(throwing: YTDLPError.parseJSONFailed(message: "JSON 解析错误: \(error.localizedDescription)\n原始内容截取: \(rawOutput.prefix(300))"))
                    }
                } else {
                    let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(throwing: YTDLPError.executionFailed(message: errString.isEmpty ? "解析失败，退出码: \(process.terminationStatus)" : errString))
                }
            }
        }
    }
    
    // MARK: - 阶段二：流式下载与进度解析
    
    public func startDownload(
        metadata: VideoMetadata,
        quality: DownloadQuality,
        destinationFolder: URL,
        removeWatermark: Bool = true,
        concurrentFragments: Int = 4,
        cookieSource: BrowserCookieSource = .none,
        onProgress: @escaping (DownloadProgress) -> Void,
        onStatusChange: @escaping (String) -> Void,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let ytdlpPath = PathFinder.shared.resolveYtDlpPath() else {
            onCompletion(.failure(YTDLPError.binaryNotFound(name: "yt-dlp")))
            return
        }
        
        guard let ffmpegPath = PathFinder.shared.resolveFFmpegPath() else {
            onCompletion(.failure(YTDLPError.binaryNotFound(name: "ffmpeg")))
            return
        }
        
        cancelCurrentTask()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlpPath)
            process.environment = PathFinder.shared.makeInjectedEnvironment()
            
            // 安全过滤文件名中的非法字符
            let safeTitle = metadata.title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanSafeTitle = safeTitle.isEmpty ? "Video_\(Int(Date().timeIntervalSince1970))" : safeTitle
            
            var arguments: [String] = [
                "--newline",
                "--no-colors",
                "--no-playlist",
                "--windows-filenames",
                "--no-overwrites",
                "--ffmpeg-location", ffmpegPath,
                "-P", destinationFolder.path
            ]
            
            // 如果具备无水印直链 (如爱奇艺 M3U8、抖音/微信视频号等)，直接下载该原画视频流
            if let directURL = metadata.directStreamURL, !directURL.isEmpty {
                let isDouyin = metadata.url.contains("douyin.com") || metadata.url.contains("iesdouyin.com") || directURL.contains("douyinvod.com")
                let isIqiyi = metadata.url.contains("iqiyi.com") || metadata.url.contains("pps.tv") || directURL.contains("iqiyi.com")
                let ua = isIqiyi ? "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1" : "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.15"
                
                var headers: [String] = [
                    "--add-header", "User-Agent: \(ua)"
                ]
                if isDouyin {
                    headers.append(contentsOf: ["--add-header", "Referer: https://www.douyin.com/"])
                } else if isIqiyi {
                    headers.append(contentsOf: ["--add-header", "Referer: https://m.iqiyi.com/"])
                }
                
                if concurrentFragments > 1 {
                    arguments.append(contentsOf: ["-N", "\(concurrentFragments)"])
                }
                arguments.append(contentsOf: ["--buffer-size", "1M"])
                
                arguments.append(contentsOf: [
                    "-o", "\(cleanSafeTitle.prefix(50)).%(ext)s",
                    "--no-check-certificates"
                ])
                if quality == .audioMP3 || quality == .audioM4A {
                    arguments.append(contentsOf: quality.ytdlpArguments(removeWatermark: removeWatermark))
                }
                arguments.append(contentsOf: headers)
                arguments.append(directURL)
            } else {
                // 通用下载模式
                if concurrentFragments > 1 {
                    arguments.append(contentsOf: ["-N", "\(concurrentFragments)"])
                }
                arguments.append(contentsOf: ["--buffer-size", "1M"])
                
                arguments.append(contentsOf: [
                    "-o", "%(title)s.%(ext)s"
                ])
                arguments.append(contentsOf: quality.ytdlpArguments(removeWatermark: removeWatermark))
                if let browser = cookieSource.argumentValue {
                    arguments.append(contentsOf: ["--cookies-from-browser", browser])
                }
                arguments.append(metadata.url)
            }
            
            process.arguments = arguments
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            self.processLock.lock()
            self.currentDownloadProcess = process
            self.currentStdoutPipe = stdoutPipe
            self.currentStderrPipe = stderrPipe
            self.processLock.unlock()
            
            var stdoutBuffer = ""
            var stderrBuffer = ""
            let bufferLock = NSLock()
            var currentProgress = DownloadProgress()
            var detectedFinalFilePath: String? = nil
            
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self = self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }
                
                if let text = String(data: data, encoding: .utf8) {
                    bufferLock.lock()
                    stdoutBuffer += text
                    
                    while let newlineIndex = stdoutBuffer.firstIndex(of: "\n") {
                        let line = String(stdoutBuffer[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                        stdoutBuffer.removeSubrange(..<stdoutBuffer.index(after: newlineIndex))
                        
                        if !line.isEmpty {
                            self.parseOutputLine(
                                line: line,
                                currentProgress: &currentProgress,
                                detectedFilePath: &detectedFinalFilePath,
                                onProgress: onProgress,
                                onStatusChange: onStatusChange
                            )
                        }
                    }
                    bufferLock.unlock()
                }
            }
            
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let text = String(data: data, encoding: .utf8) {
                    bufferLock.lock()
                    stderrBuffer += text
                    bufferLock.unlock()
                }
            }
            
            process.terminationHandler = { [weak self] proc in
                guard let self = self else { return }
                
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                
                self.processLock.lock()
                self.currentDownloadProcess = nil
                self.currentStdoutPipe = nil
                self.currentStderrPipe = nil
                self.processLock.unlock()
                
                let exitCode = proc.terminationStatus
                if exitCode == 0 {
                    var finalURL: URL = destinationFolder
                    if let path = detectedFinalFilePath {
                        let fullPath = path.hasPrefix("/") ? path : destinationFolder.appendingPathComponent(path).path
                        if FileManager.default.fileExists(atPath: fullPath) {
                            finalURL = URL(fileURLWithPath: fullPath)
                        }
                    }
                    
                    // 保底机制：若正则未准确提取，尝试寻找下载目录中最近 30 秒内新增的媒体文件
                    if finalURL == destinationFolder {
                        if let files = try? FileManager.default.contentsOfDirectory(at: destinationFolder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) {
                            let recentFiles = files.filter { url in
                                let ext = url.pathExtension.lowercased()
                                return ["mp4", "m4a", "mp3", "mkv", "webm", "flv"].contains(ext)
                            }.sorted {
                                let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                                let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                                return d0 > d1
                            }
                            if let newest = recentFiles.first,
                               let modDate = try? newest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                               Date().timeIntervalSince(modDate) < 60 {
                                finalURL = newest
                            }
                        }
                    }
                    onCompletion(.success(finalURL))
                } else if proc.terminationReason == .uncaughtSignal {
                    onCompletion(.failure(YTDLPError.cancelled))
                } else {
                    let errMsg = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    onCompletion(.failure(YTDLPError.executionFailed(message: errMsg.isEmpty ? "下载异常退出 (代码: \(exitCode))" : errMsg)))
                }
            }
            
            do {
                try process.run()
            } catch {
                self.cleanupHandles(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
                onCompletion(.failure(YTDLPError.executionFailed(message: "启动下载进程失败: \(error.localizedDescription)")))
            }
        }
    }
    
    private func parseOutputLine(
        line: String,
        currentProgress: inout DownloadProgress,
        detectedFilePath: inout String?,
        onProgress: @escaping (DownloadProgress) -> Void,
        onStatusChange: @escaping (String) -> Void
    ) {
        if let regex = progressRegex {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
            if let match = matches.first {
                if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                    let pctStr = nsLine.substring(with: match.range(at: 1))
                    if let pct = Double(pctStr) {
                        currentProgress.percentage = pct / 100.0
                    }
                }
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                    currentProgress.totalSize = nsLine.substring(with: match.range(at: 2))
                }
                if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
                    currentProgress.speed = nsLine.substring(with: match.range(at: 3))
                }
                if match.numberOfRanges > 4, match.range(at: 4).location != NSNotFound {
                    currentProgress.eta = nsLine.substring(with: match.range(at: 4))
                }
                
                onProgress(currentProgress)
                return
            }
        }
        
        if line.contains("[Merger]") {
            onStatusChange("正在使用 ffmpeg 合并音视频轨...")
        } else if line.contains("[ExtractAudio]") {
            onStatusChange("正在提取音频并转换 MP3...")
        }
        
        for regex in destinationRegexes {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
            if let match = matches.first, match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                let candidatePath = nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                detectedFilePath = candidatePath
                currentProgress.destinationPath = candidatePath
                onProgress(currentProgress)
                break
            }
        }
    }
    
    public func cancelCurrentTask() {
        processLock.lock()
        defer { processLock.unlock() }
        
        if let proc = currentDownloadProcess, proc.isRunning {
            proc.terminate()
        }
        
        currentStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        currentStderrPipe?.fileHandleForReading.readabilityHandler = nil
        currentDownloadProcess = nil
        currentStdoutPipe = nil
        currentStderrPipe = nil
    }
    
    private func cleanupHandles(stdoutPipe: Pipe, stderrPipe: Pipe) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        processLock.lock()
        currentDownloadProcess = nil
        currentStdoutPipe = nil
        currentStderrPipe = nil
        processLock.unlock()
    }
}

/// 专门用于小红书 0.1s 极速网络层重定向拦截，避免下载无用的网页 HTML
final class XHSRedirectDelegate: NSObject, URLSessionTaskDelegate {
    var redirectedURL: String?
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let location = response.allHeaderFields["Location"] as? String ?? response.allHeaderFields["location"] as? String {
            self.redirectedURL = location
        } else if let reqURL = request.url?.absoluteString {
            self.redirectedURL = reqURL
        }
        // 关键性能优化：直接阻断后续跳转和网页主体下载，0.1秒极速返回
        completionHandler(nil)
    }
}

// MARK: - 自定义错误定义
public enum YTDLPError: LocalizedError {
    case binaryNotFound(name: String)
    case parseJSONFailed(message: String)
    case executionFailed(message: String)
    case wechatRestricted(message: String)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let name):
            return "未在系统中找到组件 '\(name)'。请确保已通过 Homebrew 安装 (运行 brew install \(name))。"
        case .parseJSONFailed(let msg):
            return "视频信息解析失败: \(msg)"
        case .executionFailed(let msg):
            return "执行失败: \(msg)"
        case .wechatRestricted(let msg):
            return msg
        case .cancelled:
            return "下载任务已取消。"
        }
    }
}
