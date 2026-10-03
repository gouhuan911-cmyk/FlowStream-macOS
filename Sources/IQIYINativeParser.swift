import Foundation
import CryptoKit

/// 专为爱奇艺 (iqiyi.com / pps.tv) 打造的高性能原生解析引擎
/// 基于爱奇艺移动端 H5 状态树与官方 TMTS 媒体切片接口，原生绕过 yt-dlp 过时规则与反爬阻断
public final class IQIYINativeParser {
    public static let shared = IQIYINativeParser()
    
    private let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
    private let tmtsKey = "d5fb4bd9d50c4be6948c97edd7254b0e"
    private let tmtsSrc = "76f90cbd92f94a2e925d83e8ccd22cb7"
    
    private init() {}
    
    public struct TMTSStream {
        public let vd: Int
        public let m3u: String?
        public let screenSize: String?
        public let fileFormat: String?
    }
    
    private struct ExtractedPageInfo {
        var tvid: String?
        var title: String?
        var albumName: String?
        var thumbnail: String?
        var duration: Double?
    }
    
    /// 解析爱奇艺页面 URL，直接提取开放原画 H.264 M3U8 流
    public func parse(url: URL) async throws -> VideoMetadata {
        let cleanURLString = url.absoluteString
        let mobileURLString: String
        
        let path = url.path
        if let regex = try? NSRegularExpression(pattern: #"(v_[a-zA-Z0-9]+)\.html"#),
           let match = regex.firstMatch(in: path, range: NSRange(location: 0, length: (path as NSString).length)) {
            let slug = (path as NSString).substring(with: match.range(at: 1))
            mobileURLString = "https://m.iqiyi.com/\(slug).html"
        } else if let host = url.host?.lowercased(), !host.hasPrefix("m.") {
            mobileURLString = cleanURLString.replacingOccurrences(of: "://www.iqiyi.com", with: "://m.iqiyi.com")
        } else {
            mobileURLString = cleanURLString
        }
        
        guard let mobileURL = URL(string: mobileURLString) else {
            throw YTDLPError.executionFailed(message: "爱奇艺链接格式无效。")
        }
        
        // 抓取移动端页面 HTML
        var request = URLRequest(url: mobileURL)
        request.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.iqiyi.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...399).contains(httpResp.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw YTDLPError.executionFailed(message: "无法访问爱奇艺视频页面，请检查网络连接。")
        }
        
        // 提取 tvid (qipuId) 及标题、封面信息
        let parsedPage = extractPageInfo(from: html)
        guard let tvid = parsedPage.tvid, !tvid.isEmpty else {
            throw YTDLPError.executionFailed(message: "未能从该爱奇艺页面中定位到有效的视频 ID (tvId)。")
        }
        
        // 调用 iQIYI TMTS 官方流分发接口
        let streams = try await fetchTMTSStreams(tvid: tvid)
        guard !streams.isEmpty else {
            throw YTDLPError.executionFailed(message: "未能获取到可播放的爱奇艺视频流，该视频可能受数字版权保护 (DRM) 或为会员独占内容。")
        }
        
        // 优选最高画质清晰度 (优先 720P H.264，兼顾高画质与播放兼容性)
        let selectedStream = streams.sorted { s1, s2 in
            let score1 = streamScore(vd: s1.vd, format: s1.fileFormat)
            let score2 = streamScore(vd: s2.vd, format: s2.fileFormat)
            return score1 > score2
        }.first
        
        guard let stream = selectedStream, let m3uURL = stream.m3u, !m3uURL.isEmpty else {
            throw YTDLPError.executionFailed(message: "爱奇艺视频分发地址解析失败。")
        }
        
        var thumb = parsedPage.thumbnail ?? ""
        if thumb.hasPrefix("//") {
            thumb = "https:" + thumb
        } else if thumb.hasPrefix("http://") {
            thumb = "https://" + thumb.dropFirst("http://".count)
        }
        
        let displayTitle: String
        if let t = parsedPage.title, !t.isEmpty {
            displayTitle = t
        } else if let a = parsedPage.albumName, !a.isEmpty {
            displayTitle = a
        } else {
            displayTitle = "爱奇艺高清视频"
        }
        
        return VideoMetadata(
            url: cleanURLString,
            title: displayTitle,
            duration: parsedPage.duration,
            durationString: parsedPage.duration.map { formatSeconds(Int($0)) },
            thumbnail: thumb.isEmpty ? nil : thumb,
            uploader: parsedPage.albumName ?? "爱奇艺",
            channel: "爱奇艺",
            filesizeApprox: nil,
            directStreamURL: m3uURL
        )
    }
    
    private func fetchTMTSStreams(tvid: String) async throws -> [TMTSStream] {
        let tm = Int(Date().timeIntervalSince1970 * 1000)
        let rawSign = "\(tm)\(tmtsKey)\(tvid)"
        let sc = Insecure.MD5.hash(data: Data(rawSign.utf8)).map { String(format: "%02x", $0) }.joined()
        
        let apiString = "https://cache.m.iqiyi.com/jp/tmts/\(tvid)/\(tvid)/?tvid=\(tvid)&vid=\(tvid)&src=\(tmtsSrc)&sc=\(sc)&t=\(tm)"
        guard let apiURL = URL(string: apiString) else { return [] }
        
        var req = URLRequest(url: apiURL)
        req.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("https://m.iqiyi.com/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 8
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResp = response as? HTTPURLResponse, (200...399).contains(httpResp.statusCode),
              var text = String(data: data, encoding: .utf8) else {
            return []
        }
        
        if text.hasPrefix("var tvInfoJs=") {
            text.removeFirst("var tvInfoJs=".count)
        }
        
        guard let jsonData = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let dataDict = json["data"] as? [String: Any] else {
            return []
        }
        
        // 检查爱奇艺 BOSS 鉴权与会员专属状态
        if let boss = dataDict["bossInfo"] as? [String: Any],
           let status = boss["status"] as? String {
            if status == "Q00304" || status == "Q00301" {
                throw YTDLPError.executionFailed(message: "该视频为爱奇艺【VIP会员专享剧集】，受官方版权加密保护 (DRM) 无法直接下载。(第1~2集等免费开放试看剧集可直接下载)")
            } else if status == "Q00308" {
                throw YTDLPError.executionFailed(message: "该视频为爱奇艺【超前点播/单点付费】内容，受数字版权保护无法直接下载。")
            } else if status == "Q00302" {
                throw YTDLPError.executionFailed(message: "该视频受爱奇艺【区域版权保护】，当前网络地区无法解析。")
            }
        }
        
        guard let vidl = dataDict["vidl"] as? [[String: Any]] else {
            return []
        }
        
        var results: [TMTSStream] = []
        for item in vidl {
            let vd = item["vd"] as? Int ?? 0
            let m3u = (item["m3u"] as? String) ?? (item["m3utx"] as? String)
            let screenSize = item["screenSize"] as? String
            let fileFormat = item["fileFormat"] as? String
            if let m3u = m3u, !m3u.isEmpty {
                results.append(TMTSStream(vd: vd, m3u: m3u, screenSize: screenSize, fileFormat: fileFormat))
            }
        }
        return results
    }
    
    private func streamScore(vd: Int, format: String?) -> Int {
        var score = 0
        switch vd {
        case 5, 18: score = 500 // 1080P
        case 4: score = 400     // 720P H.264
        case 17: score = 380    // 720P H.265
        case 2: score = 300     // 480P
        case 75: score = 280
        case 1: score = 200     // 360P
        case 96: score = 100    // 240P
        default: score = vd * 10
        }
        // H.264 兼容性最佳，优先于 H.265
        if format?.lowercased() == "h265" {
            score -= 10
        }
        return score
    }
    
    private func extractPageInfo(from html: String) -> ExtractedPageInfo {
        var info = ExtractedPageInfo()
        
        // 尝试从 window.__INITIAL_STATE__ 中提取完整结构化数据
        if let idx = html.range(of: "window.__INITIAL_STATE__=") {
            let sub = String(html[idx.upperBound...])
            if let endIdx = sub.range(of: ";</script>") {
                let jsonStr = String(sub[..<endIdx.lowerBound])
                if let jsonData = jsonStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let play = obj["play"] as? [String: Any] {
                    
                    if let videoInfo = play["videoInfo"] as? [String: Any] {
                        if let qipuId = videoInfo["qipuId"] {
                            info.tvid = "\(qipuId)"
                        } else if let vid = videoInfo["videoId"] {
                            info.tvid = "\(vid)"
                        }
                        info.title = videoInfo["videoName"] as? String
                        info.thumbnail = videoInfo["imageUrl"] as? String
                        if let dur = videoInfo["duration"] as? Double {
                            info.duration = dur
                        } else if let durInt = videoInfo["duration"] as? Int {
                            info.duration = Double(durInt)
                        }
                    }
                    
                    if let albumInfo = play["albumInfo"] as? [String: Any] {
                        info.albumName = albumInfo["albumName"] as? String
                        if info.title == nil || info.title?.isEmpty == true {
                            info.title = albumInfo["albumName"] as? String
                        }
                        if info.thumbnail == nil || info.thumbnail?.isEmpty == true {
                            info.thumbnail = albumInfo["imageUrl"] as? String
                        }
                    }
                }
            }
        }
        
        // 兜底正则扫描
        if info.tvid == nil {
            if let m = regexMatch(pattern: #"\"videoId\":\s*([0-9]+)"#, in: html) {
                info.tvid = m
            } else if let m = regexMatch(pattern: #"\"qipuId\":\s*([0-9]+)"#, in: html) {
                info.tvid = m
            } else if let m = regexMatch(pattern: #"(?i)tvid[\"\':\s=]+([0-9]+)"#, in: html) {
                info.tvid = m
            }
        }
        
        if info.title == nil {
            if let m = regexMatch(pattern: #"\"videoName\":\s*\"([^\"]+)\""#, in: html) {
                info.title = m
            } else if let m = regexMatch(pattern: #"<title>([^<]+)</title>"#, in: html) {
                let cleaned = m.replacingOccurrences(of: "-电视剧全集-完整版视频在线观看-爱奇艺", with: "")
                    .replacingOccurrences(of: "-在线视频网站-海量正版高清视频在线观看", with: "")
                    .replacingOccurrences(of: "-爱奇艺", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    info.title = cleaned
                }
            }
        }
        
        return info
    }
    
    private func regexMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
    
    private func formatSeconds(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        let h = m / 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m % 60, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}
