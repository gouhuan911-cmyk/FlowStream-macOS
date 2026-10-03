import Foundation
import WebKit

/// 专为抖音平台打造的高性能原生 WebKit 解析引擎
/// 基于 macOS 系统原生 WebKit 运行，天然绕过 ArgusSecurityPlugin 反爬拦截
@MainActor
public final class DouyinNativeParser: NSObject {
    public static let shared = DouyinNativeParser()
    
    // 关键核心：强引用持有当前进行中的解析会话，绝对杜绝 delegate 弱引用导致过早释放
    private var activeSessions: [UUID: DouyinParseSession] = [:]
    
    private override init() {
        super.init()
    }
    
    /// 解析抖音短链接或网页链接，直接提取无水印 1080P/720P 原片流（独立会话隔离，支持并发）
    public func parse(url: URL) async throws -> VideoMetadata {
        let sessionId = UUID()
        let session = DouyinParseSession(id: sessionId, url: url) { [weak self] in
            self?.activeSessions.removeValue(forKey: sessionId)
        }
        self.activeSessions[sessionId] = session
        return try await session.start()
    }
}

@MainActor
private final class DouyinParseSession: NSObject, WKNavigationDelegate {
    let id: UUID
    let url: URL
    let onCompletion: () -> Void
    
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<VideoMetadata, Error>?
    private var isCompleted = false
    private var pollTimer: Timer?
    private var attempts = 0
    private let maxAttempts = 15 // 每 0.1 秒轮询一次，最多 1.5 秒
    
    init(id: UUID, url: URL, onCompletion: @escaping () -> Void) {
        self.id = id
        self.url = url
        self.onCompletion = onCompletion
        super.init()
    }
    
    func start() async throws -> VideoMetadata {
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            
            let config = WKWebViewConfiguration()
            let wv = WKWebView(frame: .zero, configuration: config)
            self.webView = wv
            wv.navigationDelegate = self
            
            // 采用主流移动端 Safari UA，获得纯净的短视频流结构
            wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
            
            let request = URLRequest(url: self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8.0)
            wv.load(request)
            
            // 4 秒硬超时兜底（如果页面异常无响应，迅速转入通用引擎兜底，绝不卡顿）
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                guard let self = self, !self.isCompleted else { return }
                self.finish(with: .failure(NSError(domain: "DouyinParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "抖音解析超时，正在切换备用通道。"])))
            }
        }
    }
    
    private func finish(with result: Result<VideoMetadata, Error>) {
        guard !isCompleted else { return }
        isCompleted = true
        pollTimer?.invalidate()
        pollTimer = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        onCompletion()
        continuation?.resume(with: result)
        continuation = nil
    }
    
    // MARK: - 关键防御：拦截一切外部 Scheme（如 snssdk1128://、douyin:// 等）
    // 彻底杜绝 macOS 弹出“未设定用来打开应用程序”系统弹窗！
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let targetURL = navigationAction.request.url, let scheme = targetURL.scheme?.lowercased() {
            if scheme != "http" && scheme != "https" {
                // 静默阻断外部手机 App 协议唤起
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isCompleted else { return }
        attempts = 0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(onPollTimerTick), userInfo: nil, repeats: true)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }
    
    @objc private func onPollTimerTick() {
        guard !isCompleted, let wv = self.webView else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        
        attempts += 1
        
        let script = """
        (function() {
            try {
                var r = window._ROUTER_DATA;
                if (!r) return null;
                
                // 1. 尝试从标准移动端 loaderData 中提取
                if (r.loaderData) {
                    for (var key in r.loaderData) {
                        var page = r.loaderData[key];
                        if (page && page.videoInfoRes && page.videoInfoRes.item_list && page.videoInfoRes.item_list.length > 0) {
                            return JSON.stringify({ item: page.videoInfoRes.item_list[0], title: document.title });
                        }
                    }
                }
                
                // 2. 深度搜索任意包含 item_list 的数据节点
                function findItem(obj, depth) {
                    if (!obj || typeof obj !== 'object' || depth > 4) return null;
                    if (Array.isArray(obj.item_list) && obj.item_list.length > 0) {
                        return obj.item_list[0];
                    }
                    for (var k in obj) {
                        if (typeof obj[k] === 'object') {
                            var res = findItem(obj[k], depth + 1);
                            if (res) return res;
                        }
                    }
                    return null;
                }
                
                var found = findItem(r, 0);
                if (found) {
                    return JSON.stringify({ item: found, title: document.title });
                }
                
                // 3. 检查是否有原生 video 元素
                var videoEl = document.querySelector('video');
                if (videoEl && videoEl.src && videoEl.src.startsWith('http')) {
                    return JSON.stringify({ directSrc: videoEl.src, title: document.title });
                }
                
                return null;
            } catch(e) {
                return null;
            }
        })()
        """
        
        wv.evaluateJavaScript(script) { [weak self] res, _ in
            guard let self = self, !self.isCompleted else { return }
            
            if let str = res as? String,
               let data = str.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                if let item = json["item"] as? [String: Any] {
                    let pageTitle = json["title"] as? String ?? ""
                    let title = (item["desc"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalTitle = (title != nil && !title!.isEmpty) ? title! : (pageTitle.isEmpty ? "抖音精彩视频" : pageTitle)
                    
                    let author = (item["author"] as? [String: Any])?["nickname"] as? String ?? "抖音创作者"
                    let durationMs = item["duration"] as? Double ?? 0
                    let cover = (item["video"] as? [String: Any])?["cover"] as? [String: Any]
                    let thumbURL = (cover?["url_list"] as? [String])?.first
                    
                    let videoObj = item["video"] as? [String: Any]
                    let playAddr = videoObj?["play_addr"] as? [String: Any]
                    let rawPlayURL = (playAddr?["url_list"] as? [String])?.first ?? ""
                    
                    // 核心去水印逻辑：将 playwm 替换为纯净的 play
                    let noWatermarkStreamURL = rawPlayURL.replacingOccurrences(of: "playwm", with: "play")
                    
                    let meta = VideoMetadata(
                        url: wv.url?.absoluteString ?? self.url.absoluteString,
                        title: finalTitle,
                        duration: durationMs > 0 ? durationMs / 1000.0 : nil,
                        durationString: nil,
                        thumbnail: thumbURL,
                        uploader: author,
                        channel: author,
                        filesizeApprox: nil,
                        directStreamURL: noWatermarkStreamURL.isEmpty ? nil : noWatermarkStreamURL
                    )
                    
                    self.finish(with: .success(meta))
                    return
                } else if let directSrc = json["directSrc"] as? String, !directSrc.isEmpty {
                    let pageTitle = json["title"] as? String ?? "抖音精彩视频"
                    let meta = VideoMetadata(
                        url: wv.url?.absoluteString ?? self.url.absoluteString,
                        title: pageTitle,
                        duration: nil,
                        durationString: nil,
                        thumbnail: nil,
                        uploader: "抖音创作者",
                        channel: "抖音创作者",
                        filesizeApprox: nil,
                        directStreamURL: directSrc
                    )
                    self.finish(with: .success(meta))
                    return
                }
            }
            
            // 轮询超过上限（1.5秒），快速释放并转入通用引擎兜底
            if self.attempts >= self.maxAttempts {
                self.finish(with: .failure(NSError(domain: "DouyinParser", code: -2, userInfo: [NSLocalizedDescriptionKey: "未能从抖音响应中提取到视频信息，将自动切入通用引擎。"])))
            }
        }
    }
}
