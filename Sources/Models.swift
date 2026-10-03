import Foundation
import SwiftUI

/// 视频来源平台识别与品牌微标签
public enum VideoPlatform: String, Codable {
    case douyin = "抖音"
    case xiaohongshu = "小红书"
    case bilibili = "哔哩哔哩"
    case youtube = "YouTube"
    case kuaishou = "快手"
    case tiktok = "TikTok"
    case iqiyi = "爱奇艺"
    case weibo = "微博"
    case twitter = "X (Twitter)"
    case xigua = "西瓜视频"
    case tencent = "腾讯视频"
    case wechat = "微信视频号"
    case convert = "万能转换"
    case other = "通用网络"
    
    public static func detect(from urlString: String) -> VideoPlatform {
        let lower = urlString.lowercased()
        if lower.contains("weixin.qq.com") || lower.contains("channels.weixin") { return .wechat }
        if lower.contains("douyin.com") || lower.contains("iesdouyin.com") { return .douyin }
        if lower.contains("xhslink") || lower.contains("xiaohongshu.com") { return .xiaohongshu }
        if lower.contains("bilibili.com") || lower.contains("b23.tv") { return .bilibili }
        if lower.contains("youtube.com") || lower.contains("youtu.be") { return .youtube }
        if lower.contains("kuaishou.com") { return .kuaishou }
        if lower.contains("tiktok.com") { return .tiktok }
        if lower.contains("iqiyi.com") || lower.contains("pps.tv") { return .iqiyi }
        if lower.contains("weibo.com") || lower.contains("weibo.cn") { return .weibo }
        if lower.contains("twitter.com") || lower.contains("x.com") { return .twitter }
        if lower.contains("ixigua.com") { return .xigua }
        if lower.contains("v.qq.com") { return .tencent }
        return .other
    }
    
    public var iconName: String {
        switch self {
        case .wechat: return "message.fill"
        case .douyin: return "music.note"
        case .xiaohongshu: return "book.fill"
        case .bilibili: return "play.tv.fill"
        case .youtube: return "play.rectangle.fill"
        case .kuaishou: return "video.fill"
        case .tiktok: return "sparkles.tv"
        case .iqiyi: return "play.tv.fill"
        case .weibo: return "newspaper.fill"
        case .twitter: return "bubble.left.and.bubble.right.fill"
        case .xigua: return "play.rectangle.fill"
        case .tencent: return "play.tv.fill"
        case .convert: return "arrow.triangle.2.circlepath.circle.fill"
        case .other: return "globe"
        }
    }
    
    public var themeColor: Color {
        switch self {
        case .wechat: return Color(red: 0.03, green: 0.76, blue: 0.38) // 微信官方翠绿
        case .douyin: return Color(red: 0.1, green: 0.8, blue: 0.85) // 霓虹青
        case .xiaohongshu: return Color(red: 1.0, green: 0.25, blue: 0.35) // 珊瑚红
        case .bilibili: return Color(red: 0.15, green: 0.65, blue: 1.0) // 天空蓝
        case .youtube: return Color(red: 0.95, green: 0.2, blue: 0.2) // 经典红
        case .kuaishou: return Color(red: 1.0, green: 0.5, blue: 0.1) // 橙色
        case .tiktok: return Color(red: 0.2, green: 0.9, blue: 0.8)
        case .iqiyi: return Color(red: 0.0, green: 0.85, blue: 0.35) // 爱奇艺标志性荧光绿
        case .weibo: return Color(red: 0.95, green: 0.25, blue: 0.25) // 微博红
        case .twitter: return Color(red: 0.1, green: 0.6, blue: 0.92) // 经典推特蓝
        case .xigua: return Color(red: 0.98, green: 0.2, blue: 0.28) // 西瓜红
        case .tencent: return Color(red: 0.05, green: 0.5, blue: 0.98) // 企鹅科技蓝
        case .convert: return Color(red: 0.0, green: 0.82, blue: 0.92) // 流光亮青
        case .other: return Color.gray
        }
    }
}

/// 外观显示模式 (白天 / 黑夜 / 跟随系统)
public enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system = "跟随系统"
    case light = "白天"
    case dark = "黑夜"
    
    public var id: String { rawValue }
    
    public func displayName(lang: AppLanguage) -> String {
        switch self {
        case .system:
            return lang == .zh ? "系统" : "System"
        case .light:
            return lang == .zh ? "白天" : "Light"
        case .dark:
            return lang == .zh ? "黑夜" : "Dark"
        }
    }
    
    public var icon: String {
        switch self {
        case .system: return "circle.righthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 视频画质与格式选项
public enum DownloadQuality: String, CaseIterable, Identifiable, Codable {
    case best = "最高画质 (4K/8K)"
    case p1080 = "1080P 高清"
    case p720 = "720P 标清"
    case audioMP3 = "高保真 MP3 (含内嵌封面)"
    case audioM4A = "无损原声 M4A"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .best: return "sparkles.tv"
        case .p1080: return "tv"
        case .p720: return "play.rectangle"
        case .audioMP3: return "waveform"
        case .audioM4A: return "music.note"
        }
    }
    
    public func localizedName(lang: AppLanguage) -> String {
        switch self {
        case .best: return lang == .zh ? "最高画质 (4K/8K)" : "Best (4K/8K)"
        case .p1080: return lang == .zh ? "1080P 高清" : "1080P HD"
        case .p720: return lang == .zh ? "720P 标清" : "720P"
        case .audioMP3: return lang == .zh ? "高保真 MP3 (含内嵌封面)" : "Hi-Fi MP3 (Cover Art)"
        case .audioM4A: return lang == .zh ? "无损原声 M4A" : "Lossless M4A"
        }
    }
    
    public func ytdlpArguments(removeWatermark: Bool = true) -> [String] {
        switch self {
        case .best:
            return [
                "-f", "bestvideo+bestaudio/best",
                "--merge-output-format", "mp4"
            ]
        case .p1080:
            return [
                "-f", "bestvideo[height<=1080]+bestaudio/best[height<=1080]",
                "--merge-output-format", "mp4"
            ]
        case .p720:
            return [
                "-f", "bestvideo[height<=720]+bestaudio/best[height<=720]",
                "--merge-output-format", "mp4"
            ]
        case .audioMP3:
            return [
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", "0",
                "--embed-thumbnail",
                "--add-metadata"
            ]
        case .audioM4A:
            return [
                "-x",
                "--audio-format", "m4a",
                "--embed-thumbnail",
                "--add-metadata"
            ]
        }
    }
}

/// 浏览器登录态导入来源 (支持 B站大会员 / YouTube 私享内容)
public enum BrowserCookieSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "不导入"
    case safari = "Safari"
    case chrome = "Google Chrome"
    case edge = "Microsoft Edge"
    case firefox = "Firefox"
    
    public var id: String { rawValue }
    
    public var argumentValue: String? {
        switch self {
        case .none: return nil
        case .safari: return "safari"
        case .chrome: return "chrome"
        case .edge: return "edge"
        case .firefox: return "firefox"
        }
    }
}

/// 播放列表 / 分P 单集数据项
public struct PlaylistItem: Identifiable, Codable, Hashable {
    public let id: String
    public let index: Int
    public let title: String
    public let url: String
    public let durationString: String?
    public var isSelected: Bool
    
    public init(
        id: String = UUID().uuidString,
        index: Int,
        title: String,
        url: String,
        durationString: String? = nil,
        isSelected: Bool = true
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.url = url
        self.durationString = durationString
        self.isSelected = isSelected
    }
}

/// 播放列表 / 分P 集合模型
public struct PlaylistInfo: Identifiable, Codable {
    public var id: String { url }
    public let url: String
    public let title: String
    public let platform: VideoPlatform
    public var items: [PlaylistItem]
    
    public init(url: String, title: String, platform: VideoPlatform, items: [PlaylistItem]) {
        self.url = url
        self.title = title
        self.platform = platform
        self.items = items
    }
}

/// 视频元数据模型
public struct VideoMetadata: Identifiable, Codable {
    public var id: String { url }
    public let url: String
    public let title: String
    public let duration: Double?
    public let durationString: String?
    public let thumbnail: String?
    public let uploader: String?
    public let channel: String?
    public let filesizeApprox: Int64?
    public var directStreamURL: String? = nil
    
    public var authorName: String {
        channel ?? uploader ?? "未知创作者"
    }
    
    public var formattedDuration: String {
        if let str = durationString, !str.isEmpty { return str }
        guard let dur = duration, dur > 0 else { return "00:30" }
        let total = Int(dur)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    public var formattedFileSize: String {
        guard let size = filesizeApprox, size > 0 else { return "原画流" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    enum CodingKeys: String, CodingKey {
        case title, duration
        case durationString = "duration_string"
        case thumbnail, uploader, channel
        case filesizeApprox = "filesize_approx"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "视频内容"
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.durationString = try container.decodeIfPresent(String.self, forKey: .durationString)
        self.thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        self.uploader = try container.decodeIfPresent(String.self, forKey: .uploader)
        self.channel = try container.decodeIfPresent(String.self, forKey: .channel)
        self.filesizeApprox = try container.decodeIfPresent(Int64.self, forKey: .filesizeApprox)
        self.url = ""
        self.directStreamURL = nil
    }
    
    public init(
        url: String,
        title: String,
        duration: Double?,
        durationString: String?,
        thumbnail: String?,
        uploader: String?,
        channel: String?,
        filesizeApprox: Int64?,
        directStreamURL: String? = nil
    ) {
        self.url = url
        self.title = title
        self.duration = duration
        self.durationString = durationString
        self.thumbnail = thumbnail
        self.uploader = uploader
        self.channel = channel
        self.filesizeApprox = filesizeApprox
        self.directStreamURL = directStreamURL
    }
}

/// 任务运行状态
public enum TaskItemStatus: Equatable {
    case waiting
    case parsing
    case ready
    case queued
    case downloading
    case merging
    case completed(outputURL: URL)
    case failed(error: String)
    case cancelled
}

/// 批量下载队列单个任务项
public final class DownloadTaskItem: Identifiable, ObservableObject {
    public let id: UUID
    public let originalInput: String
    public let cleanURL: String
    public let platform: VideoPlatform
    public let createdAt: Date
    
    @Published public var metadata: VideoMetadata?
    @Published public var quality: DownloadQuality = .best
    public var selectedQuality: DownloadQuality {
        get { quality }
        set { quality = newValue }
    }
    @Published public var status: TaskItemStatus = .waiting
    @Published public var progress: Double = 0.0
    @Published public var speed: String = "--"
    @Published public var eta: String = "--"
    @Published public var totalSize: String = "--"
    @Published public var completedFileURL: URL? = nil
    @Published public var errorMessage: String? = nil
    
    public init(
        id: UUID = UUID(),
        originalInput: String,
        cleanURL: String,
        platform: VideoPlatform,
        quality: DownloadQuality = .best
    ) {
        self.id = id
        self.originalInput = originalInput
        self.cleanURL = cleanURL
        self.platform = platform
        self.quality = quality
        self.createdAt = Date()
    }
    
    public var isActiveOrPending: Bool {
        switch status {
        case .parsing, .ready, .queued, .downloading, .merging:
            return true
        case .completed, .failed, .cancelled, .waiting:
            return false
        }
    }
}

/// 历史记录持久化模型
public struct DownloadHistoryItem: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let thumbnailURL: String?
    public let platformRaw: String
    public let filePath: String
    public let fileSizeString: String
    public let durationString: String
    public let completedAt: Date
    
    public var platform: VideoPlatform {
        VideoPlatform(rawValue: platformRaw) ?? .other
    }
    
    public var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
    
    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: completedAt)
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        thumbnailURL: String?,
        platform: VideoPlatform,
        filePath: String,
        fileSizeString: String,
        durationString: String,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.platformRaw = platform.rawValue
        self.filePath = filePath
        self.fileSizeString = fileSizeString
        self.durationString = durationString
        self.completedAt = completedAt
    }
}

/// 本地环境健康状态
public struct EnvironmentStatus {
    public let ytdlpPath: String?
    public let ffmpegPath: String?
    public let isReady: Bool
    
    public var missingTools: [String] {
        var missing: [String] = []
        if ytdlpPath == nil { missing.append("yt-dlp") }
        if ffmpegPath == nil { missing.append("ffmpeg") }
        return missing
    }
}

/// 实时下载进度流模型
public struct DownloadProgress {
    public var percentage: Double = 0.0
    public var totalSize: String = "--"
    public var speed: String = "--"
    public var eta: String = "--"
    public var destinationPath: String? = nil
    
    public init(
        percentage: Double = 0.0,
        totalSize: String = "--",
        speed: String = "--",
        eta: String = "--",
        destinationPath: String? = nil
    ) {
        self.percentage = percentage
        self.totalSize = totalSize
        self.speed = speed
        self.eta = eta
        self.destinationPath = destinationPath
    }
}

