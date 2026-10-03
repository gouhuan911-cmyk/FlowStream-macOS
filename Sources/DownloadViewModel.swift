import Foundation
import SwiftUI
import AppKit

public enum MainTab: String, CaseIterable, Identifiable {
    case queue = "queue"       // 📥 网络下载
    case convert = "convert"   // 🔄 万能转换
    case history = "history"   // 📜 媒体历史
    
    public var id: String { rawValue }
}

@MainActor
public final class DownloadViewModel: ObservableObject {
    // MARK: - 基础导航与语言
    @Published public var currentTab: MainTab = .queue
    @Published public var language: AppLanguage = .zh
    
    // MARK: - 下载队列与历史记录
    @Published public var queueTasks: [DownloadTaskItem] = []
    @Published public var historyItems: [DownloadHistoryItem] = []
    @Published public var historySearchText: String = ""
    
    public var filteredHistoryItems: [DownloadHistoryItem] {
        let query = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return historyItems
        }
        return historyItems.filter {
            $0.title.lowercased().contains(query) ||
            $0.filePath.lowercased().contains(query) ||
            $0.platform.rawValue.lowercased().contains(query)
        }
    }
    
    // MARK: - 万能转换舱
    @Published var convertJobs: [TranscodeJob] = []
    @Published public var isConverting: Bool = false
    @Published var activePreset: Preset
    @Published public var useHardwareAcceleration: Bool = true {
        didSet {
            UserDefaults.standard.set(useHardwareAcceleration, forKey: kUseHardwareKey)
            // 重新规划就绪中的转换任务
            for job in convertJobs where job.state == .ready || job.state == .pending {
                buildConvertPlan(for: job)
            }
        }
    }
    @Published public var convertOutputFolderURL: URL
    @Published public var maxConcurrentTranscodes: Int = 1
    @Published var ffmpegReport: FFmpegCapabilities.Report = FFmpegCapabilities.query()
    
    private var convertRunners: [UUID: TranscodeRunner] = [:]
    
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
    private let kConvertFolderKey = "FlowStream_ConvertFolderPath_v2"
    private let kUseHardwareKey = "FlowStream_UseHardwareAcceleration_v2"
    private let kActivePresetIdKey = "FlowStream_ActivePresetId_v2"
    private let kRemoveWatermarkKey = "FlowStream_RemoveWatermark_v2"
    private let kLanguageKey = "FlowStream_Language_v2"
    private let kAutoStartDownloadKey = "FlowStream_AutoStartDownload_v2"
    private let kAppearanceModeKey = "FlowStream_AppearanceMode_v2"
    private var lastCheckedClipboard: String = ""
    
    public init() {
        // 读取持久化下载路径
        let defaultDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        let downloadFolder: URL
        if let savedPath = UserDefaults.standard.string(forKey: kDownloadFolderKey),
           FileManager.default.fileExists(atPath: savedPath) {
            downloadFolder = URL(fileURLWithPath: savedPath)
        } else {
            downloadFolder = defaultDir
        }
        self.downloadFolderURL = downloadFolder
        
        // 读取转换输出路径
        if let savedConvertPath = UserDefaults.standard.string(forKey: kConvertFolderKey),
           FileManager.default.fileExists(atPath: savedConvertPath) {
            self.convertOutputFolderURL = URL(fileURLWithPath: savedConvertPath)
        } else {
            self.convertOutputFolderURL = downloadFolder
        }
        
        // 读取硬件加速偏好 (默认开启 Apple Silicon VideoToolbox)
        if UserDefaults.standard.object(forKey: kUseHardwareKey) != nil {
            self.useHardwareAcceleration = UserDefaults.standard.bool(forKey: kUseHardwareKey)
        } else {
            self.useHardwareAcceleration = true
        }
        
        // 读取激活预设 (默认 MP4 H.264 硬件加速)
        if let savedPresetId = UserDefaults.standard.string(forKey: kActivePresetIdKey),
           let p = PresetLibrary.preset(id: savedPresetId) {
            self.activePreset = p
        } else {
            self.activePreset = PresetLibrary.preset(id: "mp4-h264-hw") ?? PresetLibrary.all[0]
        }
        
        // 读取无水印开关
        if UserDefaults.standard.object(forKey: kRemoveWatermarkKey) != nil {
            self.removeWatermark = UserDefaults.standard.bool(forKey: kRemoveWatermarkKey)
        } else {
            self.removeWatermark = true
        }
        
        // 读取自动开始下载开关
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
        
        // 加载历史记录
        self.historyItems = HistoryManager.shared.loadHistory()
        
        refreshEnvironment()
        setupAppActiveNotification()
        applyAppearance()
    }
    
    // MARK: - 常用预设列表与切换
    var quickPresets: [Preset] {
        [
            PresetLibrary.preset(id: "mp4-h264-hw") ?? PresetLibrary.all[0],
            PresetLibrary.preset(id: "mp4-hevc-hw") ?? PresetLibrary.all[1],
            PresetLibrary.preset(id: "mov-prores") ?? PresetLibrary.all[2],
            PresetLibrary.preset(id: "gif") ?? PresetLibrary.all[3],
            PresetLibrary.preset(id: "audio-mp3") ?? PresetLibrary.all[4],
            PresetLibrary.preset(id: "audio-flac") ?? PresetLibrary.all[5]
        ]
    }
    
    var allPresets: [Preset] {
        PresetLibrary.all
    }
    
    func selectPreset(_ preset: Preset) {
        self.activePreset = preset
        UserDefaults.standard.set(preset.id, forKey: kActivePresetIdKey)
        // 同步所有排队中的任务
        for job in convertJobs where job.state == .ready || job.state == .pending {
            job.preset = preset
            buildConvertPlan(for: job)
        }
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
    
    public func selectConvertOutputFolder() {
        let openPanel = NSOpenPanel()
        openPanel.message = L10n.text(.saveLocation, lang: language)
        openPanel.prompt = L10n.text(.changeFolder, lang: language)
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = convertOutputFolderURL
        
        if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
            self.convertOutputFolderURL = selectedURL
            UserDefaults.standard.set(selectedURL.path, forKey: kConvertFolderKey)
        }
    }
    
    public func openConvertOutputFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: convertOutputFolderURL.path)
    }
    
    public func refreshEnvironment() {
        self.environmentStatus = PathFinder.shared.checkEnvironment()
        self.ffmpegReport = FFmpegCapabilities.query()
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
        guard let pasteboardString = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pasteboardString.isEmpty else { return }
        
        // 避免重复识别完全相同的剪贴板文本
        guard pasteboardString != lastCheckedClipboard else { return }
        lastCheckedClipboard = pasteboardString
        
        // 优先判断是否为视频链接
        let extractedURLs = YTDLPService.extractAllCleanURLs(from: pasteboardString)
        if let clean = extractedURLs.first {
            let alreadyInQueue = queueTasks.contains { $0.cleanURL == clean }
            if !alreadyInQueue {
                if self.urlInput.isEmpty || self.urlInput.hasPrefix("http") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.urlInput = clean
                        self.isClipboardAutoFilled = true
                    }
                }
            }
        }
    }
    
    // MARK: - 智能万能输入入口 (Smart Universal Input)
    public func smartHandleInput() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            selectLocalFilesForConvert()
            return
        }
        
        // 1. 判断是否为本地文件路径
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("file://") || FileManager.default.fileExists(atPath: trimmed) {
            let cleanPath = trimmed.replacingOccurrences(of: "file://", with: "")
            let url = URL(fileURLWithPath: cleanPath)
            addConvertFiles(urls: [url])
            return
        }
        
        // 2. 判断是否为网络视频链接
        let extractedURLs = YTDLPService.extractAllCleanURLs(from: trimmed)
        if !extractedURLs.isEmpty {
            parseAndAdd(rawText: trimmed)
            return
        }
        
        // 3. 兜底尝试作为链接或打开文件选择器
        if trimmed.lowercased().contains("http") {
            parseAndAdd(rawText: trimmed)
        } else {
            selectLocalFilesForConvert()
        }
    }
    
    // MARK: - 全窗口拖拽投放 (Drag & Drop)
    public func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // 1. 尝试作为本地文件读取
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        self?.addConvertFiles(urls: [url])
                    }
                }
                return true
            }
            
            // 2. 尝试作为网络 URL 读取
            if provider.hasItemConformingToTypeIdentifier("public.url") {
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        if url.isFileURL {
                            self?.addConvertFiles(urls: [url])
                        } else {
                            self?.parseAndAdd(rawText: url.absoluteString)
                        }
                    }
                }
                return true
            }
            
            // 3. 尝试作为纯文本读取
            if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                _ = provider.loadObject(ofClass: String.self) { [weak self] text, _ in
                    guard let text = text else { return }
                    DispatchQueue.main.async {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("/") || trimmed.hasPrefix("file://") || FileManager.default.fileExists(atPath: trimmed) {
                            let cleanPath = trimmed.replacingOccurrences(of: "file://", with: "")
                            self?.addConvertFiles(urls: [URL(fileURLWithPath: cleanPath)])
                        } else {
                            self?.parseAndAdd(rawText: text)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
    
    // MARK: - 阶段一：解析视频 (下载队列)
    public func parseAndAdd(rawText: String) {
        let extractedURLs = YTDLPService.extractAllCleanURLs(from: rawText)
        guard !extractedURLs.isEmpty else { return }
        
        self.currentTab = .queue
        self.urlInput = ""
        self.isClipboardAutoFilled = false
        
        for clean in extractedURLs {
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
    
    public func addURLToQueue(rawText: String) {
        parseAndAdd(rawText: rawText)
    }
    
    public func retryTask(item: DownloadTaskItem) {
        if item.metadata == nil {
            startParsing(item: item)
        } else {
            enqueueDownload(item: item)
        }
    }
    
    public func startParsing(item: DownloadTaskItem) {
        item.status = .parsing
        item.errorMessage = nil
        self.objectWillChange.send()
        
        Task {
            do {
                let meta = try await YTDLPService.shared.parseMetadata(
                    rawInput: item.cleanURL,
                    removeWatermark: removeWatermark
                )
                await MainActor.run {
                    item.metadata = meta
                    item.totalSize = meta.formattedFileSize
                    withAnimation {
                        item.status = .ready
                    }
                    self.objectWillChange.send()
                    
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
    
    // MARK: - 阶段二：开始下载
    public func enqueueDownload(item: DownloadTaskItem) {
        guard let _ = item.metadata else { return }
        item.status = .waiting
        processDownloadQueue()
    }
    
    public func startAllPendingDownloads() {
        for task in queueTasks {
            if case .ready = task.status {
                task.status = .waiting
            }
        }
        processDownloadQueue()
    }
    
    public func pauseAllDownloads() {
        YTDLPService.shared.cancelCurrentTask()
        for task in queueTasks {
            if case .downloading = task.status {
                task.status = .ready
            } else if case .waiting = task.status {
                task.status = .ready
            }
        }
    }
    
    public func startAll() {
        startAllPendingDownloads()
    }
    
    public func pauseAll() {
        pauseAllDownloads()
    }
    
    private func processDownloadQueue() {
        let isAnyDownloading = queueTasks.contains {
            if case .downloading = $0.status { return true }
            if case .merging = $0.status { return true }
            return false
        }
        guard !isAnyDownloading else { return }
        
        guard let nextTask = queueTasks.first(where: {
            if case .waiting = $0.status { return true }
            return false
        }) else { return }
        
        executeDownload(item: nextTask)
    }
    
    private func executeDownload(item: DownloadTaskItem) {
        guard let meta = item.metadata else { return }
        
        item.status = .downloading
        item.progress = 0.0
        
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
                    if newProgress.percentage >= 0.99 && item.status == .downloading {
                        item.status = .merging
                    }
                }
            },
            onStatusChange: { _ in },
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
                        
                        NSApp.requestUserAttention(.informationalRequest)
                        
                    case .failure(let error):
                        if let ytError = error as? YTDLPError, case .cancelled = ytError {
                            item.status = .ready
                        } else {
                            item.status = .failed(error: error.localizedDescription)
                            item.errorMessage = error.localizedDescription
                        }
                    }
                    
                    self.processDownloadQueue()
                }
            }
        )
    }
    
    // MARK: - 下载任务清理与控制
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
    
    public func cancelTask(item: DownloadTaskItem) {
        removeTask(item: item)
    }
    
    public func clearCompleted() {
        withAnimation {
            queueTasks.removeAll {
                if case .completed = $0.status { return true }
                return false
            }
        }
    }
    
    // MARK: - 万能转换舱业务逻辑 (Transcode Engine)
    
    public func selectLocalFilesForConvert() {
        let openPanel = NSOpenPanel()
        openPanel.title = L10n.text(.selectFiles, lang: language)
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        
        if openPanel.runModal() == .OK {
            addConvertFiles(urls: openPanel.urls)
        }
    }
    
    public func isSupportedMediaFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let supported: Set<String> = [
            "mp4", "mov", "m4v", "mkv", "webm", "avi", "ts", "m2ts", "mts",
            "mpg", "mpeg", "mpe", "vob", "flv", "wmv", "gif", "3gp",
            "mp3", "flac", "m4a", "aac", "aiff", "aif", "aifc", "caf", "wav",
            "ogg", "oga", "opus", "wma", "ape", "alac", "ac3", "eac3", "dts"
        ]
        return supported.contains(ext) || AudioDecryptor.isEncrypted(url)
    }
    
    public func addConvertFiles(urls: [URL]) {
        var added = 0
        let fm = FileManager.default
        
        for url in urls {
            var filesToAdd: [URL] = []
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey]),
                           values.isRegularFile == true, values.isHidden != true,
                           isSupportedMediaFile(fileURL) {
                            filesToAdd.append(fileURL)
                        }
                    }
                }
            } else if isSupportedMediaFile(url) {
                filesToAdd.append(url)
            }
            
            for file in filesToAdd {
                if convertJobs.contains(where: { $0.inputURL.standardizedFileURL == file.standardizedFileURL }) {
                    continue
                }
                let job = TranscodeJob(inputURL: file, preset: activePreset)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.convertJobs.insert(job, at: 0)
                }
                analyzeConvertJob(job: job)
                added += 1
            }
        }
        
        if added > 0 {
            self.currentTab = .convert
            self.urlInput = ""
        }
    }
    
    func analyzeConvertJob(job: TranscodeJob) {
        if job.isEncryptedSource {
            job.state = .decrypting
            job.progress = 0
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    let decryptedURL = try AudioDecryptor.shared.decrypt(fileAt: job.inputURL) { pct in
                        DispatchQueue.main.async { job.progress = pct }
                    }
                    DispatchQueue.main.async {
                        job.decryptedURL = decryptedURL
                        job.tempDirectory = decryptedURL.deletingLastPathComponent()
                        job.progress = 0
                        self?.probeConvertJob(job: job)
                    }
                } catch {
                    DispatchQueue.main.async {
                        job.state = .failed
                        job.errorMessage = error.localizedDescription
                    }
                }
            }
            return
        }
        
        probeConvertJob(job: job)
    }
    
    private func probeConvertJob(job: TranscodeJob) {
        job.state = .analyzing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let info = try MediaProbe().probeSync(url: job.effectiveInputURL)
                DispatchQueue.main.async {
                    job.mediaInfo = info
                    self?.buildConvertPlan(for: job)
                }
            } catch {
                DispatchQueue.main.async {
                    job.state = .failed
                    job.errorMessage = "媒体探测失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func buildConvertPlan(for job: TranscodeJob) {
        guard let info = job.mediaInfo else { return }
        guard info.hasVideo || info.audio != nil else {
            job.state = .failed
            job.errorMessage = "文件中没有可转换的音视频轨道"
            return
        }
        
        let outURL = defaultConvertOutputURL(for: job)
        job.outputURL = outURL
        job.outputContainer = job.preset.container
        
        let planner = ConversionPlanner()
        let explicitMode: EncodeMode = useHardwareAcceleration ? .hardware : .software
        let plan = planner.plan(input: info, outputURL: outURL, preset: job.preset, explicitMode: explicitMode)
        job.plan = plan
        job.state = .ready
        
        if isConverting {
            scheduleConvert()
        }
    }
    
    private func defaultConvertOutputURL(for job: TranscodeJob) -> URL {
        let base = job.inputURL.deletingPathExtension().lastPathComponent
        let ext = job.preset.container.fileExtension
        let folder = convertOutputFolderURL
        let candidate = folder.appendingPathComponent("\(base)-converted.\(ext)")
        return uniqueOutputURL(candidate)
    }
    
    private func uniqueOutputURL(_ url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var i = 2
        while true {
            let candidate = dir.appendingPathComponent("\(base)-\(i).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
    
    public func startConverting() {
        if !hasRunnableConvertJobs {
            requeueFinishedConvertJobs()
        }
        isConverting = true
        scheduleConvert()
    }
    
    public func stopConverting() {
        isConverting = false
        for (_, runner) in convertRunners {
            runner.cancel()
        }
    }
    
    private var hasRunnableConvertJobs: Bool {
        convertJobs.contains { job in
            switch job.state {
            case .pending, .decrypting, .analyzing, .ready, .running: return true
            case .completed, .failed, .cancelled: return false
            }
        }
    }
    
    private func requeueFinishedConvertJobs() {
        for job in convertJobs {
            switch job.state {
            case .completed, .failed, .cancelled:
                job.state = .pending
                job.progress = 0
                job.fps = 0
                job.speedText = ""
                job.errorMessage = nil
                buildConvertPlan(for: job)
            default:
                break
            }
        }
    }
    
    public func scheduleConvert() {
        guard isConverting else { return }
        
        let runningCount = convertJobs.filter { $0.state == .running }.count
        guard runningCount < maxConcurrentTranscodes else { return }
        
        for job in convertJobs where job.state == .ready || job.state == .pending {
            if job.plan == nil, job.mediaInfo != nil {
                buildConvertPlan(for: job)
            }
            guard let _ = job.plan else { continue }
            runConvertJob(job: job)
            if convertJobs.filter({ $0.state == .running }).count >= maxConcurrentTranscodes {
                break
            }
        }
        
        if !convertJobs.isEmpty,
           convertJobs.allSatisfy({ $0.state == .completed || $0.state == .failed || $0.state == .cancelled }) {
            isConverting = false
        }
    }
    
    private func runConvertJob(job: TranscodeJob) {
        guard let plan = job.plan else { return }
        
        let planner = ConversionPlanner()
        let args = planner.makeArguments(plan: plan)
        let duration = job.mediaInfo?.duration ?? 0
        
        let runner = TranscodeRunner()
        convertRunners[job.id] = runner
        job.state = .running
        job.progress = 0
        job.fps = 0
        job.speedText = ""
        
        runner.run(
            arguments: args,
            duration: duration,
            progress: { [weak job] pct, fps, speed in
                job?.progress = pct
                job?.fps = fps
                job?.speedText = speed
            },
            completion: { [weak self, weak job] result in
                guard let self = self, let job = job else { return }
                self.convertRunners.removeValue(forKey: job.id)
                
                switch result {
                case .success:
                    job.state = .completed
                    job.progress = 1.0
                    self.cleanupTemp(for: job)
                    
                    if let outURL = job.outputURL {
                        var sizeStr = "--"
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: outURL.path),
                           let size = attrs[.size] as? NSNumber {
                            sizeStr = ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
                        }
                        
                        let historyItem = DownloadHistoryItem(
                            title: job.fileName + " (\(job.preset.name))",
                            thumbnailURL: nil,
                            platform: .convert,
                            filePath: outURL.path,
                            fileSizeString: sizeStr,
                            durationString: job.durationLabel
                        )
                        HistoryManager.shared.addHistory(item: historyItem)
                        self.historyItems = HistoryManager.shared.loadHistory()
                    }
                    
                    NSApp.requestUserAttention(.informationalRequest)
                    
                case .failure(let err):
                    self.cleanupTemp(for: job)
                    self.discardPartialOutput(for: job)
                    if let te = err as? TranscodeError, case .cancelled = te {
                        job.state = .cancelled
                        job.progress = 0
                    } else {
                        job.state = .failed
                        job.progress = 0
                        job.errorMessage = err.localizedDescription
                    }
                }
                
                self.scheduleConvert()
            }
        )
    }
    
    func cancelConvertJob(job: TranscodeJob) {
        if let runner = convertRunners[job.id] {
            runner.cancel()
        }
        job.state = .cancelled
        job.progress = 0
        cleanupTemp(for: job)
        discardPartialOutput(for: job)
        scheduleConvert()
    }
    
    func removeConvertJob(job: TranscodeJob) {
        cancelConvertJob(job: job)
        withAnimation {
            convertJobs.removeAll { $0.id == job.id }
        }
    }
    
    func retryConvertJob(job: TranscodeJob) {
        job.state = .pending
        job.progress = 0
        job.fps = 0
        job.speedText = ""
        job.errorMessage = nil
        analyzeConvertJob(job: job)
    }
    
    public func clearCompletedConvertJobs() {
        withAnimation {
            convertJobs.removeAll { $0.state == .completed || $0.state == .cancelled }
        }
    }
    
    private func cleanupTemp(for job: TranscodeJob) {
        guard let dir = job.tempDirectory else { return }
        try? FileManager.default.removeItem(at: dir)
        job.tempDirectory = nil
        job.decryptedURL = nil
    }
    
    private func discardPartialOutput(for job: TranscodeJob) {
        guard let url = job.outputURL else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) && url.lastPathComponent.contains("-converted") {
            try? fm.removeItem(at: url)
        }
    }
    
    // MARK: - 从下载历史一键转码 (One-Click Convert from History)
    func convertDownloadedItem(item: DownloadHistoryItem, preset: Preset? = nil) {
        guard item.fileExists else { return }
        let targetPreset = preset ?? activePreset
        let job = TranscodeJob(inputURL: item.fileURL, preset: targetPreset)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.convertJobs.insert(job, at: 0)
            self.currentTab = .convert
        }
        analyzeConvertJob(job: job)
    }
    
    // MARK: - 原生 QuickLook 空格预览与访达定位
    public func previewItem(fileURL: URL) {
        QuickLookHelper.shared.preview(fileURL: fileURL)
    }
    
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
