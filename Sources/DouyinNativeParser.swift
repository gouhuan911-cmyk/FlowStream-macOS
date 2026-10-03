import Foundation
import WebKit
import Cocoa

/// 专为抖音平台打造的高性能原生 WebKit 解析引擎
/// 基于 macOS 系统原生 WebKit 运行，天然绕过 ArgusSecurityPlugin 反爬拦截与风控校验
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
private final class DouyinParseSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let url: URL
    let onCompletion: () -> Void
    
    private var webView: WKWebView?
    private var offscreenWindow: NSWindow?
    private var continuation: CheckedContinuation<VideoMetadata, Error>?
    private var isCompleted = false
    private var pollTimer: Timer?
    private var attempts = 0
    private let maxAttempts = 22 // 每 0.35 秒轮询一次，最多 ~7.7 秒
    
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
            
            // 采用真实桌面端 Safari UA，获得完整 XGPlayer 原画流
            let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.15"
            
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800), configuration: config)
            self.webView = wv
            wv.navigationDelegate = self
            wv.uiDelegate = self
            wv.customUserAgent = desktopUA
            
            // 关键：挂载到后台离屏 NSWindow，彻底防止 macOS WebKit 冻结后台定时器与渲染引擎
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.contentView = wv
            win.orderBack(nil)
            win.alphaValue = 0.0
            self.offscreenWindow = win
            
            let request = URLRequest(url: self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12.0)
            wv.load(request)
            
            // 9 秒总超时保底
            DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) { [weak self] in
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
        webView?.uiDelegate = nil
        webView?.stopLoading()
        offscreenWindow?.orderOut(nil)
        offscreenWindow?.contentView = nil
        offscreenWindow = nil
        webView = nil
        onCompletion()
        continuation?.resume(with: result)
        continuation = nil
    }
    
    // MARK: - 关键防御：拦截一切外部 Scheme（如 bitbrowser://, snssdk1128://, douyin://, hubstudio:// 等）
    // 彻底杜绝 macOS 弹出“未设定用来打开应用程序”系统弹窗！
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if let targetURL = navigationAction.request.url, let scheme = targetURL.scheme?.lowercased() {
            if !["http", "https", "about", "blob", "data"].contains(scheme) {
                // 静默阻断所有外部应用伪协议，杜绝 macOS 系统弹窗
                decisionHandler(.cancel, preferences)
                return
            }
        }
        decisionHandler(.allow, preferences)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let targetURL = navigationAction.request.url, let scheme = targetURL.scheme?.lowercased() {
            if !["http", "https", "about", "blob", "data"].contains(scheme) {
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
    
    // MARK: - WKUIDelegate：静默屏蔽弹窗与新窗口
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        return nil
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isCompleted else { return }
        attempts = 0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(timeInterval: 0.35, target: self, selector: #selector(onPollTimerTick), userInfo: nil, repeats: true)
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
                var v = document.querySelector('video');
                var player = v ? v.__xg_player : null;
                if (!player && window.player) player = window.player;
                
                var streamURL = null;
                
                // 1. 优先提取 XGPlayer 播放器内核中绑定的真实原画直链 (排除测试短片)
                if (player && player.config && Array.isArray(player.config.url)) {
                    for (var i = 0; i < player.config.url.length; i++) {
                        var u = player.config.url[i].src || '';
                        if (u.includes('douyinvod.com') && !u.includes('uuu_265')) {
                            streamURL = u;
                            break;
                        }
                    }
                }
                
                // 2. 检查 video 原生 src 直链 (排除测试素材)
                if (!streamURL && v && v.src && v.src.startsWith('http') && !v.src.includes('uuu_265') && !v.src.includes('douyinstatic')) {
                    streamURL = v.src;
                }
                
                // 3. 检查常规 _ROUTER_DATA 结构 (移动端或兼容页)
                if (!streamURL && window._ROUTER_DATA && window._ROUTER_DATA.loaderData) {
                    for (var key in window._ROUTER_DATA.loaderData) {
                        var page = window._ROUTER_DATA.loaderData[key];
                        if (page && page.videoInfoRes && page.videoInfoRes.item_list && page.videoInfoRes.item_list.length > 0) {
                            var item = page.videoInfoRes.item_list[0];
                            var playAddr = item.video && item.video.play_addr;
                            var rawURL = (playAddr && playAddr.url_list && playAddr.url_list[0]) || '';
                            if (rawURL) {
                                streamURL = rawURL.replace('playwm', 'play');
                                break;
                            }
                        }
                    }
                }
                
                // 4. 提取标题与有效性检验
                var pageTitle = (document.title || '').replace(/\\s*-\\s*抖音$/, '').trim();
                var isTitleGood = pageTitle.length > 0 && !pageTitle.includes('记录美好生活') && !pageTitle.includes('在抖音');
                
                var poster = (v && v.poster) || '';
                var duration = (v && v.duration) || 0;
                
                return JSON.stringify({
                    streamURL: streamURL,
                    title: pageTitle,
                    isTitleGood: isTitleGood,
                    poster: poster,
                    duration: duration
                });
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
                
                let streamURL = json["streamURL"] as? String
                let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let isTitleGood = json["isTitleGood"] as? Bool ?? false
                let poster = json["poster"] as? String
                let duration = json["duration"] as? Double
                
                if let stream = streamURL, !stream.isEmpty {
                    // 当标题就绪，或轮询超过8次保底时即可完成返回
                    if isTitleGood || self.attempts >= 8 {
                        let finalTitle = (title != nil && !title!.isEmpty) ? title! : "抖音精彩视频"
                        let meta = VideoMetadata(
                            url: wv.url?.absoluteString ?? self.url.absoluteString,
                            title: finalTitle,
                            duration: (duration != nil && duration! > 0) ? duration : nil,
                            durationString: nil,
                            thumbnail: (poster != nil && !poster!.isEmpty) ? poster : nil,
                            uploader: "抖音",
                            channel: "抖音",
                            filesizeApprox: nil,
                            directStreamURL: stream
                        )
                        self.finish(with: .success(meta))
                        return
                    }
                }
            }
            
            // 轮询超过上限（约 7.7 秒），返回失败
            if self.attempts >= self.maxAttempts {
                self.finish(with: .failure(NSError(domain: "DouyinParser", code: -2, userInfo: [NSLocalizedDescriptionKey: "未能从抖音响应中提取到视频信息。"])))
            }
        }
    }
}
