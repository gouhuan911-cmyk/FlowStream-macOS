import Foundation
import SwiftUI

/// 语言选项
public enum AppLanguage: String, CaseIterable, Identifiable {
    case zh = "中"
    case en = "EN"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }
}

/// 集中式多语言文本管理
public struct L10n {
    public static func text(_ key: Key, lang: AppLanguage) -> String {
        switch key {
        case .appName:
            return lang == .zh ? "流光下载" : "FlowStream DL"
        case .appSubtitle:
            return lang == .zh ? "原生极速视频下载器" : "Native Video Downloader"
        case .inputPlaceholder:
            return lang == .zh ? "输入或拖入视频链接 (抖音/B站/小红书/YouTube等)..." : "Enter or drop video URLs (Douyin, Bilibili, RED, YouTube, etc.)..."
        case .pasteAndAdd:
            return lang == .zh ? "加入队列" : "Add to Queue"
        case .addToQueue:
            return lang == .zh ? "加入队列" : "Add to Queue"
        case .startDownload:
            return lang == .zh ? "开始下载" : "Download"
        case .startAll:
            return lang == .zh ? "全部开始" : "Start All"
        case .pauseAll:
            return lang == .zh ? "全部暂停" : "Pause All"
        case .autoStart:
            return lang == .zh ? "自动开始下载" : "Auto-start"
        case .saveLocation:
            return lang == .zh ? "保存位置:" : "Save To:"
        case .changeFolder:
            return lang == .zh ? "更改目录" : "Change"
        case .openFolder:
            return lang == .zh ? "打开目录" : "Open Folder"
        case .noWatermark:
            return lang == .zh ? "无水印原片" : "No Watermark"
        case .acceleration:
            return lang == .zh ? "4x并发加速" : "4x Turbo"
        case .tabQueue:
            return lang == .zh ? "📥 下载队列" : "📥 Queue"
        case .tabHistory:
            return lang == .zh ? "📜 历史记录" : "📜 History"
        case .emptyQueueTitle:
            return lang == .zh ? "暂无下载任务" : "No Active Downloads"
        case .emptyQueueSubtitle:
            return lang == .zh ? "在上方输入链接，或直接将浏览器网页地址拖入窗口" : "Enter URL above or drag and drop links directly into this window"
        case .emptyHistoryTitle:
            return lang == .zh ? "暂无历史记录" : "No Download History"
        case .emptyHistorySubtitle:
            return lang == .zh ? "下载完成的视频将自动保存在这里，支持一键空格预览" : "Completed videos will appear here with instant spacebar preview"
        case .clearCompleted:
            return lang == .zh ? "清空已完成" : "Clear Done"
        case .clearHistory:
            return lang == .zh ? "清空全部历史" : "Clear All History"
        case .revealInFinder:
            return lang == .zh ? "在访达中定位" : "Reveal in Finder"
        case .quickLookPreview:
            return lang == .zh ? "空格预览播放" : "QuickLook (Space)"
        case .clipboardDetected:
            return lang == .zh ? "检测到剪贴板链接" : "Clipboard Link Detected"
        case .dropPrompt:
            return lang == .zh ? "释放鼠标，立即加入流光下载队列" : "Drop links here to start downloading"
        case .waiting:
            return lang == .zh ? "排队等待中" : "Waiting"
        case .parsing:
            return lang == .zh ? "正在解析元数据..." : "Parsing..."
        case .readyStatus:
            return lang == .zh ? "已就绪" : "Ready"
        case .queued:
            return lang == .zh ? "排队等待下载..." : "Queued..."
        case .downloading:
            return lang == .zh ? "正在极速下载..." : "Downloading..."
        case .merging:
            return lang == .zh ? "正在合并封装..." : "Merging Formats..."
        case .completed:
            return lang == .zh ? "下载完成" : "Completed"
        case .failed:
            return lang == .zh ? "下载失败" : "Failed"
        case .fileMissing:
            return lang == .zh ? "文件已被移走或删除" : "File Missing"
        case .envOk:
            return lang == .zh ? "环境正常" : "Ready"
        case .envMissing:
            return lang == .zh ? "依赖缺失" : "Missing Deps"
        case .parseVideo:
            return lang == .zh ? "解析视频" : "Analyze"
        case .autoFilledNotice:
            return lang == .zh ? "已自动感知剪贴板" : "From Clipboard"
        case .settings:
            return lang == .zh ? "偏好设置" : "Settings"
        case .done:
            return lang == .zh ? "完成" : "Done"
        case .close:
            return lang == .zh ? "关闭" : "Close"
        case .appearance:
            return lang == .zh ? "外观模式" : "Appearance"
        case .appearanceSystem:
            return lang == .zh ? "跟随系统" : "System"
        case .appearanceLight:
            return lang == .zh ? "白天" : "Light"
        case .appearanceDark:
            return lang == .zh ? "黑夜" : "Dark"
        case .tabConvert:
            return lang == .zh ? "🔄 万能转换" : "🔄 Convert"
        case .smartInputPlaceholder:
            return lang == .zh ? "输入网页视频链接 或 拖入本地媒体文件 (自动识别)..." : "Enter web URL or drop local media files (Auto-detect)..."
        case .smartActionBtn:
            return lang == .zh ? "🚀 智能解析 / 转码" : "🚀 Smart Action"
        case .startTranscode:
            return lang == .zh ? "⚡️ 极速转码" : "⚡️ Transcode"
        case .hardwareAcceleration:
            return lang == .zh ? "⚡️ VideoToolbox 硬件加速" : "⚡️ VideoToolbox Turbo"
        case .quickPresetsTitle:
            return lang == .zh ? "常用预设" : "Presets"
        case .morePresets:
            return lang == .zh ? "更多预设" : "More Presets"
        case .oneClickConvert:
            return lang == .zh ? "🔄 一键转码" : "🔄 Transcode"
        case .selectFiles:
            return lang == .zh ? "浏览文件" : "Browse Files"
        case .emptyConvertTitle:
            return lang == .zh ? "拖入媒体文件或加密音乐即可转换" : "Drop Media Files or Encrypted Music Here"
        case .emptyConvertSubtitle:
            return lang == .zh ? "内置 28 种主流影音预设 · VideoToolbox 硬件加速 · NCM/MFLAC 音乐秒级解锁" : "28 media presets · Apple Silicon VideoToolbox GPU acceleration · Instant NCM/MFLAC unlock"
        case .convertSettings:
            return lang == .zh ? "视频与音频转换" : "Conversion Settings"
        case .transcoding:
            return lang == .zh ? "正在极速转码..." : "Transcoding..."
        case .analyzing:
            return lang == .zh ? "正在分析媒体..." : "Analyzing..."
        case .decrypting:
            return lang == .zh ? "正在解密音乐..." : "Decrypting..."
        case .directCopy:
            return lang == .zh ? "无损直拷" : "Direct Copy"
        }
    }
    
    public enum Key {
        case appName, appSubtitle, inputPlaceholder, pasteAndAdd, addToQueue
        case startDownload, startAll, pauseAll, autoStart, parseVideo, autoFilledNotice
        case saveLocation, changeFolder, openFolder, noWatermark, acceleration
        case tabQueue, tabHistory, emptyQueueTitle, emptyQueueSubtitle
        case emptyHistoryTitle, emptyHistorySubtitle, clearCompleted, clearHistory
        case revealInFinder, quickLookPreview, clipboardDetected, dropPrompt
        case waiting, parsing, readyStatus, queued, downloading, merging, completed, failed, fileMissing
        case envOk, envMissing
        case settings, done, close
        case appearance, appearanceSystem, appearanceLight, appearanceDark
        case tabConvert, smartInputPlaceholder, smartActionBtn, startTranscode, hardwareAcceleration
        case quickPresetsTitle, morePresets, oneClickConvert, selectFiles
        case emptyConvertTitle, emptyConvertSubtitle, convertSettings, transcoding, analyzing, decrypting, directCopy
    }
}

