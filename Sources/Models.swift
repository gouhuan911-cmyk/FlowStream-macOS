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
    case wechat = "微信视频号"
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
        case .other: return Color.gray
        }
    }
}

/// 视频画质与格式选项
public enum DownloadQuality: String, CaseIterable, Identifiable, Codable {
    case best = "最高画质"
    case p1080 = "1080P"
    case p720 = "720P"
    case audioMP3 = "仅音频 (MP3)"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .best: return "sparkles.tv"
        case .p1080: return "tv"
        case .p720: return "play.rectangle"
        case .audioMP3: return "waveform"
        }
    }
    
    public func localizedName(lang: AppLanguage) -> String {
        switch self {
        case .best: return lang == .zh ? "最高画质" : "Best Quality"
        case .p1080: return "1080P"
        case .p720: return "720P"
        case .audioMP3: return lang == .zh ? "仅音频 (MP3)" : "Audio (MP3)"
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
                "--audio-quality", "0"
            ]
        }
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

