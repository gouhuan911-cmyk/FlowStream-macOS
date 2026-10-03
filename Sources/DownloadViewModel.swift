import Foundation
import SwiftUI
import AppKit

public enum MainTab: String, CaseIterable {
    case queue
    case history
}

@MainActor
public final class DownloadViewModel: ObservableObject {
    // MARK: - 基础导航与语言
    @Published public var currentTab: MainTab = .queue
    @Published public var language: AppLanguage = .zh
    
    // MARK: - 队列任务与历史记录
    @Published public var queueTasks: [DownloadTaskItem] = []
    @Published public var historyItems: [DownloadHistoryItem] = []
    
    // MARK: - 输入框与剪贴板感知
    @Published public var urlInput: String = ""
    @Published public var isClipboardAutoFilled: Bool = false
    @Published public var detectedClipboardURL: String? = nil
    @Published public var isDraggingOver: Bool = false
    
    // MARK: - 全局配置
    @Published public var downloadFolderURL: URL
    @Published public var removeWatermark: Bool = true
    @Published public var concurrentFragments: Int = 4
    @Published public var autoStartDownload: Bool = false
    @Published public var environmentStatus: EnvironmentStatus = PathFinder.shared.checkEnvironment()
    
    // MARK: - 外观主题模式 (白天 / 黑夜 / 跟随系统)
    @Published public var appearanceMode: AppearanceMode = .system {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: kAppearanceModeKey)
            applyAppearance()
        }
    }
    
    // MARK: - 设置面板
    @Published public var isSettingsPresented: Bool = false
    
    // 并发下载数控制 (单任务流式下载，其余进入排队)
    private let maxConcurrentDownloads = 1
    
    private let kDownloadFolderKey = "FlowStream_DownloadFolderPath_v2"
    private let kRemoveWatermarkKey = "FlowStream_RemoveWatermark_v2"
    private let kLanguageKey = "FlowStream_Language_v2"
    private let kAutoStartDownloadKey = "FlowStream_AutoStartDownload_v2"
    private let kAppearanceModeKey = "FlowStream_AppearanceMode_v2"
    private var lastCheckedClipboard: String = ""
    
    public init() {
        // 读取持久化路径
        if let savedPath = UserDefaults.standard.string(forKey: kDownloadFolderKey),
           FileManager.default.fileExists(atPath: savedPath) {
            self.downloadFolderURL = URL(fileURLWithPath: savedPath)
        } else {
            let defaultDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
            self.downloadFolderURL = defaultDir
        }
        
        // 读取无水印开关
        if UserDefaults.standard.object(forKey: kRemoveWatermarkKey) != nil {
            self.removeWatermark = UserDefaults.standard.bool(forKey: kRemoveWatermarkKey)
        } else {
            self.removeWatermark = true
        }
        
        // 读取自动开始下载开关 (默认关闭，遵循用户控制原则)
        if UserDefaults.standard.object(forKey: kAutoStartDownloadKey) != nil {
            self.autoStartDownload = UserDefaults.standard.bool(forKey: kAutoStartDownloadKey)
        } else {
            self.autoStartDownload = false
        }
        
        // 读取语言偏好
        if let savedLang = UserDefaults.standard.string(forKey: kLanguageKey),
           let l = AppLanguage(rawValue: savedLang) {
            self.language = l
        } else {
            self.language = .zh
        }
        
        // 读取外观偏好 (默认跟随系统)
        if let savedMode = UserDefaults.standard.string(forKey: kAppearanceModeKey),
           let mode = AppearanceMode(rawValue: savedMode) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }
        
        // 清理旧的无用配置缓存
        UserDefaults.standard.removeObject(forKey: "FlowStream_CloudParserConfig_v2")
        UserDefaults.standard.removeObject(forKey: "FlowStream_CloudPresets_v2")
        
        // 加载历史记录
        self.historyItems = HistoryManager.shared.loadHistory()
        
        refreshEnvironment()
        setupAppActiveNotification()
        applyAppearance()
    }
    
    // MARK: - 外观主题切换应用
    public func applyAppearance() {
        DispatchQueue.main.async {
            switch self.appearanceMode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
    
    // MARK: - 语言切换
    public func toggleLanguage() {
        self.language = (self.language == .zh) ? .en : .zh
        UserDefaults.standard.set(self.language.rawValue, forKey: kLanguageKey)
    }
    
    // MARK: - 输出文件夹选择与打开
    public func selectOutputFolder() {
        let openPanel = NSOpenPanel()
        openPanel.message = L10n.text(.saveLocation, lang: language)
        openPanel.prompt = L10n.text(.changeFolder, lang: language)
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = downloadFolderURL
        
        if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
            self.downloadFolderURL = selectedURL
            UserDefaults.standard.set(selectedURL.path, forKey: kDownloadFolderKey)
        }
    }
    
    public func openOutputFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadFolderURL.path)
    }
    
    public func refreshEnvironment() {
        self.environmentStatus = PathFinder.shared.checkEnvironment()
    }
    
    // MARK: - 剪贴板智能感知
    private func setupAppActiveNotification() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboardOnActive()
            }
        }
    }
    
    public func checkClipboardOnActive() {
        guard let current = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !current.isEmpty,
              current != lastCheckedClipboard else { return }
        
        lastCheckedClipboard = current
        let clean = YTDLPService.extractCleanURL(from: current)
        
        // 判定是否是合法视频网址
        if clean.hasPrefix("http://") || clean.hasPrefix("https://") {
            // 检查当前队列是否已存在
            let alreadyInQueue = queueTasks.contains { $0.cleanURL == clean }
            if !alreadyInQueue {
                // 如果当前输入框为空或已是旧链接，自动填入唯一输入框
                if self.urlInput.isEmpty || self.urlInput.hasPrefix("http") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.urlInput = clean
                        self.isClipboardAutoFilled = true
                    }
                }
            }
        }
    }
    
    // MARK: - 浏览器直接拖入处理 (Drag & Drop)
    public func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // 优先尝试作为 URL 读取
            if provider.hasItemConformingToTypeIdentifier("public.url") {
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        self?.parseAndAdd(rawText: url.absoluteString)
                    }
                }
                return true
            } else if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                _ = provider.loadObject(ofClass: String.self) { [weak self] text, _ in
                    guard let text = text else { return }
                    DispatchQueue.main.async {
                        self?.parseAndAdd(rawText: text)
                    }
                }
                return true
            }
        }
        return false
    }
    
    // MARK: - 阶段一：解析视频 (分析阶段，提取信息并在队列中呈现卡片，支持多链接批量提取)
    public func parseAndAdd(rawText: String) {
        let extractedURLs = YTDLPService.extractAllCleanURLs(from: rawText)
        guard !extractedURLs.isEmpty else { return }
        
        self.currentTab = .queue
        self.urlInput = ""
        self.isClipboardAutoFilled = false
        
        for clean in extractedURLs {
            // 避免重复添加正在解析、排队或下载中的完全相同网址
            if queueTasks.contains(where: { $0.cleanURL == clean && $0.isActiveOrPending }) {
                continue
            }
            
            let platform = VideoPlatform.detect(from: clean)
            let taskItem = DownloadTaskItem(
                originalInput: rawText,
                cleanURL: clean,
                platform: platform
            )
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.queueTasks.insert(taskItem, at: 0)
            }
            
            startParsing(item: taskItem)
        }
    }
    
    // 兼容多行换行批量输入
    public func addURLToQueue(rawText: String) {
        parseAndAdd(rawText: rawText)
    }
    
    // MARK: - 智能重试任务（自动判断是解析失败重试还是下载失败重试，杜绝死锁）
    public func retryTask(item: DownloadTaskItem) {
        if item.metadata == nil {
            startParsing(item: item)
        } else {
            enqueueDownload(item: item)
        }
    }
    
    // MARK: - 解析单个任务元数据
    public func startParsing(item: DownloadTaskItem) {
        item.status = .parsing
        self.objectWillChange.send()
        
        Task {
            do {
                let meta = try await YTDLPService.shared.parseMetadata(
                    rawInput: item.cleanURL,
                    removeWatermark: removeWatermark
                )
                await MainActor.run {
                    item.metadata = meta
                    withAnimation {
                        item.status = .ready
                    }
                    self.objectWillChange.send()
                    
                    // 仅在用户显式开启“自动开始下载”时才自动入队，否则保持待下载状态，完全由用户控制
                    if self.autoStartDownload {
                        self.enqueueDownload(item: item)
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        item.status = .failed(error: error.localizedDescription)
                        item.errorMessage = error.localizedDescription
                    }
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    // MARK: - 触发单个任务进入下载排队
    public func enqueueDownload(item: DownloadTaskItem) {
        withAnimation {
            item.status = .queued
        }
        processDownloadQueue()
    }
    
    // MARK: - 队列下载调度器 (按次序单任务下载，其余排队)
    public func processDownloadQueue() {
        let isDownloading = queueTasks.contains {
            if case .downloading = $0.status { return true }
            if case .merging = $0.status { return true }
            return false
        }
        
        // 当前有任务在下载或合并中，等待其完成
        guard !isDownloading else { return }
        
        // 取出排队中最早的任务启动下载 (FIFO)
        if let nextItem = queueTasks.reversed().first(where: { $0.status == .queued }) {
            startDownloading(item: nextItem)
        }
    }
    
    // MARK: - 全部开始与全部暂停
    public func startAll() {
        var anyEnqueued = false
        for item in queueTasks where item.status == .ready {
            item.status = .queued
            anyEnqueued = true
        }
        if anyEnqueued {
            processDownloadQueue()
        }
    }
    
    public func pauseAll() {
        YTDLPService.shared.cancelCurrentTask()
        withAnimation {
            for item in queueTasks {
                if case .downloading = item.status {
                    item.status = .ready
                } else if case .merging = item.status {
                    item.status = .ready
                } else if item.status == .queued {
                    item.status = .ready
                }
            }
        }
    }
    
    // MARK: - 取消或暂停单个任务
    public func cancelTask(item: DownloadTaskItem) {
        if case .downloading = item.status {
            YTDLPService.shared.cancelCurrentTask()
            withAnimation { item.status = .ready }
            processDownloadQueue()
        } else if case .merging = item.status {
            YTDLPService.shared.cancelCurrentTask()
            withAnimation { item.status = .ready }
            processDownloadQueue()
        } else if item.status == .queued {
            withAnimation { item.status = .ready }
        }
    }
    
    // MARK: - 执行单个任务下载
    public func startDownloading(item: DownloadTaskItem) {
        guard let meta = item.metadata else { return }
        
        item.status = .downloading
        item.progress = 0.0
        item.speed = "--"
        item.eta = "--"
        
        var destination = downloadFolderURL
        if !FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                let defaultDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
                destination = defaultDir
                self.downloadFolderURL = defaultDir
            }
        }
        
        YTDLPService.shared.startDownload(
            metadata: meta,
            quality: item.quality,
            destinationFolder: destination,
            removeWatermark: removeWatermark,
            concurrentFragments: concurrentFragments,
            onProgress: { [weak item] newProgress in
                DispatchQueue.main.async {
                    guard let item = item else { return }
                    item.progress = newProgress.percentage
                    item.speed = newProgress.speed
                    item.eta = newProgress.eta
                    item.totalSize = newProgress.totalSize
                }
            },
            onStatusChange: { [weak item] status in
                DispatchQueue.main.async {
                    if status.contains("ffmpeg") || status.contains("合并") {
                        item?.status = .merging
                    }
                }
            },
            onCompletion: { [weak self, weak item] result in
                DispatchQueue.main.async {
                    guard let self = self, let item = item else { return }
                    switch result {
                    case .success(let outputURL):
                        item.status = .completed(outputURL: outputURL)
                        item.completedFileURL = outputURL
                        item.progress = 1.0
                        
                        // 自动写入历史记录
                        let history = DownloadHistoryItem(
                            title: meta.title,
                            thumbnailURL: meta.thumbnail,
                            platform: item.platform,
                            filePath: outputURL.path,
                            fileSizeString: item.totalSize != "--" ? item.totalSize : meta.formattedFileSize,
                            durationString: meta.formattedDuration
                        )
                        HistoryManager.shared.addHistory(item: history)
                        self.historyItems = HistoryManager.shared.loadHistory()
                        
                        // 提示用户：后台下载完成时，Dock 图标跳动提醒
                        NSApp.requestUserAttention(.informationalRequest)
                        
                    case .failure(let error):
                        if let ytError = error as? YTDLPError, case .cancelled = ytError {
                            item.status = .ready
                        } else {
                            item.status = .failed(error: error.localizedDescription)
                            item.errorMessage = error.localizedDescription
                        }
                    }
                    
                    // 流转下一个排队任务
                    self.processDownloadQueue()
                }
            }
        )
    }
    
    // MARK: - 任务控制与清理
    public func removeTask(item: DownloadTaskItem) {
        if case .downloading = item.status {
            YTDLPService.shared.cancelCurrentTask()
        } else if case .merging = item.status {
            YTDLPService.shared.cancelCurrentTask()
        }
        withAnimation {
            queueTasks.removeAll { $0.id == item.id }
        }
        processDownloadQueue()
    }
    
    public func clearCompleted() {
        withAnimation {
            queueTasks.removeAll {
                if case .completed = $0.status { return true }
                return false
            }
        }
    }
    
    // MARK: - 原生 QuickLook 空格预览与访达定位
    public func previewItem(fileURL: URL) {
        QuickLookHelper.shared.preview(fileURL: fileURL)
    }
    
    /// 空格快捷键唤起：智能寻找最新完成或可用的视频进行原生预览
    public func previewActiveOrLatestCompletedItem() {
        if let completed = queueTasks.first(where: {
            if case .completed = $0.status { return true }
            return false
        }), let url = completed.completedFileURL {
            previewItem(fileURL: url)
            return
        }
        if let firstHistory = historyItems.first(where: { $0.fileExists }) {
            previewItem(fileURL: firstHistory.fileURL)
        }
    }
    
    public func revealInFinder(fileURL: URL) {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadFolderURL.path)
        }
    }
    
    // MARK: - 历史记录操作
    public func removeHistory(item: DownloadHistoryItem) {
        HistoryManager.shared.removeHistory(id: item.id)
        self.historyItems = HistoryManager.shared.loadHistory()
    }
    
    public func clearAllHistory() {
        HistoryManager.shared.clearAllHistory()
        self.historyItems = []
    }
}
