import SwiftUI
import AppKit

public struct ContentView: View {
    @StateObject private var viewModel = DownloadViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isInputFocused: Bool
    @State private var keyMonitor: Any? = nil
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 背景毛玻璃液态深色碳素材质
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. 沉浸式顶部栏（交通灯、居中双舱/三舱切换药丸、右侧设置三件套与环境指示）
                HeaderBarView(viewModel: viewModel)
                
                // 2. 方案二核心：智能万能一体流输入区 + 常用预设胶囊横条 + 快捷行动栏
                VStack(spacing: 10) {
                    UniversalInputBarView(viewModel: viewModel, isInputFocused: _isInputFocused)
                    PresetPillsStripView(viewModel: viewModel)
                    SubActionBarView(viewModel: viewModel)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 10)
                
                Divider().opacity(0.15)
                
                // 3. 主体工作区（根据顶栏分段器展示：下载舱 / 转换舱 / 媒体历史库）
                ZStack {
                    switch viewModel.currentTab {
                    case .queue:
                        QueueDeckView(viewModel: viewModel)
                    case .convert:
                        ConvertDeckView(viewModel: viewModel)
                    case .history:
                        HistoryDeckView(viewModel: viewModel)
                    }
                    
                    // 全域拖拽高光呼吸提示层
                    if viewModel.isDraggingOver {
                        DragAndDropOverlayView(viewModel: viewModel)
                    }
                }
            }
        }
        .frame(minWidth: 800, idealWidth: 880, maxWidth: 1100, minHeight: 600, idealHeight: 660)
        .preferredColorScheme(viewModel.appearanceMode.colorScheme)
        // 绑定全窗口拖拽监听（支持网络 URL、本地文件、文本）
        .onDrop(of: ["public.file-url", "public.url", "public.plain-text", "public.utf8-plain-text"], isTargeted: $viewModel.isDraggingOver) { providers in
            viewModel.handleDrop(providers: providers)
        }
        // 绑定全局空格一键预览快捷键
        .onAppear {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 49 {
                    if let responder = NSApp.keyWindow?.firstResponder,
                       responder.isKind(of: NSTextView.self) {
                        return event
                    }
                    viewModel.previewActiveOrLatestCompletedItem()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let m = keyMonitor {
                NSEvent.removeMonitor(m)
                keyMonitor = nil
            }
        }
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsSheetView(viewModel: viewModel)
        }
    }
}

// MARK: - 1. 沉浸式顶部栏 (HeaderBarView)
struct HeaderBarView: View {
    @ObservedObject var viewModel: DownloadViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 68) // 交通灯安全边距
            
            // 品牌 Logo 与标题
            HStack(spacing: 8) {
                if let nsImg = NSImage(contentsOfFile: Bundle.main.bundlePath + "/Contents/Resources/AppIcon.icns") ?? NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                
                Text(L10n.text(.appName, lang: viewModel.language))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // 居中发光分段切换药丸 (网络下载 / 万能转换 / 媒体历史)
            Picker("", selection: $viewModel.currentTab) {
                Text("\(L10n.text(.tabQueue, lang: viewModel.language)) (\(viewModel.queueTasks.count))")
                    .tag(MainTab.queue)
                Text("\(L10n.text(.tabConvert, lang: viewModel.language)) (\(viewModel.convertJobs.count))")
                    .tag(MainTab.convert)
                Text("\(L10n.text(.tabHistory, lang: viewModel.language)) (\(viewModel.historyItems.count))")
                    .tag(MainTab.history)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
            
            Spacer()
            
            // 外观模式菜单 (白天 / 黑夜 / 系统)
            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.appearanceMode = mode
                        }
                    } label: {
                        HStack {
                            Text(mode.displayName(lang: viewModel.language))
                            Spacer()
                            Image(systemName: mode.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.appearanceMode.icon)
                        .font(.system(size: 11))
                    Text(viewModel.appearanceMode.displayName(lang: viewModel.language))
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // 偏好设置
            Button {
                viewModel.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .help(L10n.text(.settings, lang: viewModel.language))
            
            // 中英文即时切换
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleLanguage()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text(viewModel.language == .zh ? "EN" : "中")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary))
            }
            .buttonStyle(.plain)
            
            // VideoToolbox 硬件加速或环境状态灯
            HStack(spacing: 5) {
                Circle()
                    .fill(viewModel.ffmpegReport.hasVideoToolbox ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: viewModel.ffmpegReport.hasVideoToolbox ? .green.opacity(0.6) : .clear, radius: 4)
                Text(viewModel.ffmpegReport.hasVideoToolbox ? "⚡️ VideoToolbox" : L10n.text(.envOk, lang: viewModel.language))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(viewModel.ffmpegReport.hasVideoToolbox ? .green : .secondary)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 48)
        .background(.ultraThinMaterial.opacity(0.85))
        .overlay(Divider().opacity(0.15), alignment: .bottom)
    }
}

// MARK: - 2. 方案二智能万能输入条 (UniversalInputBarView)
struct UniversalInputBarView: View {
    @ObservedObject var viewModel: DownloadViewModel
    @FocusState var isInputFocused: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: viewModel.isClipboardAutoFilled ? "doc.on.clipboard.fill" : "link.badge.plus")
                    .foregroundColor(viewModel.isClipboardAutoFilled ? .cyan : .secondary)
                    .font(.system(size: 14))
                
                TextField(
                    L10n.text(.smartInputPlaceholder, lang: viewModel.language),
                    text: $viewModel.urlInput,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...3)
                .focused($isInputFocused)
                .onSubmit {
                    if !viewModel.urlInput.isEmpty {
                        viewModel.smartHandleInput()
                    }
                }
                
                if !viewModel.urlInput.isEmpty {
                    Button {
                        viewModel.urlInput = ""
                        viewModel.isClipboardAutoFilled = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                
                // 本地媒体文件选择按钮
                Button {
                    viewModel.selectLocalFilesForConvert()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12))
                        Text(L10n.text(.selectFiles, lang: viewModel.language))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                }
                .buttonStyle(.plain)
                .help("浏览本地视频、音频或加密音乐")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        isInputFocused
                            ? LinearGradient(colors: [.cyan.opacity(0.8), .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        lineWidth: isInputFocused ? 1.5 : 1
                    )
            )
            
            // 亮青色行动大按钮 (智能解析 / 转换)
            Button {
                viewModel.smartHandleInput()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                    Text(L10n.text(.smartActionBtn, lang: viewModel.language))
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.9, blue: 0.95), Color(red: 0.05, green: 0.75, blue: 0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color.cyan.opacity(0.35), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 3. 28大预设快捷药丸横条 (PresetPillsStripView)
struct PresetPillsStripView: View {
    @ObservedObject var viewModel: DownloadViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Label(L10n.text(.quickPresetsTitle, lang: viewModel.language), systemImage: "slider.horizontal.3")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.quickPresets) { preset in
                        let isSelected = viewModel.activePreset.id == preset.id
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.selectPreset(preset)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: preset.symbol)
                                    .font(.system(size: 10))
                                Text(preset.name)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            }
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Group {
                                    if isSelected {
                                        LinearGradient(colors: [.cyan.opacity(0.85), .blue.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
                                    } else {
                                        LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                                    }
                                }
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.cyan : Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: isSelected ? Color.cyan.opacity(0.3) : .clear, radius: 4)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // 更多 28 大预设下拉菜单
                    Menu {
                        Section("🎬 视频常用格式") {
                            ForEach(PresetLibrary.presets(in: .video)) { p in
                                Button(p.name) {
                                    viewModel.selectPreset(p)
                                }
                            }
                        }
                        Section("🎵 音频提取与无损") {
                            ForEach(PresetLibrary.presets(in: .audio)) { p in
                                Button(p.name) {
                                    viewModel.selectPreset(p)
                                }
                            }
                        }
                        Section("🖼️ 动图") {
                            ForEach(PresetLibrary.presets(in: .animation)) { p in
                                Button(p.name) {
                                    viewModel.selectPreset(p)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(L10n.text(.morePresets, lang: viewModel.language))
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.quaternary))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - 4. 辅助设置与状态控制栏 (SubActionBarView)
struct SubActionBarView: View {
    @ObservedObject var viewModel: DownloadViewModel
    
    var body: some View {
        HStack(spacing: 14) {
            // VideoToolbox 硬件加速开关药丸
            Button {
                viewModel.useHardwareAcceleration.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.useHardwareAcceleration ? "bolt.fill" : "bolt.slash")
                        .foregroundColor(viewModel.useHardwareAcceleration ? .green : .secondary)
                        .font(.system(size: 11))
                    Text(L10n.text(.hardwareAcceleration, lang: viewModel.language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(viewModel.useHardwareAcceleration ? .primary : .secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.useHardwareAcceleration ? Color.green.opacity(0.12) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(viewModel.useHardwareAcceleration ? Color.green.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("利用 Apple Silicon M系列芯片内置媒体引擎，转码速度快 6 倍")
            
            // 保存位置指示
            HStack(spacing: 4) {
                Text(L10n.text(.saveLocation, lang: viewModel.language))
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                
                Button {
                    if viewModel.currentTab == .convert {
                        viewModel.selectConvertOutputFolder()
                    } else {
                        viewModel.selectOutputFolder()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text((viewModel.currentTab == .convert ? viewModel.convertOutputFolderURL : viewModel.downloadFolderURL).lastPathComponent)
                            .font(.system(size: 11, weight: .medium))
                            .underline()
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // 右侧舱段专属操作按钮组
            if viewModel.currentTab == .queue {
                queueControls
            } else if viewModel.currentTab == .convert {
                convertControls
            } else {
                historyControls
            }
        }
        .font(.system(size: 11))
    }
    
    private var queueControls: some View {
        HStack(spacing: 8) {
            let readyCount = viewModel.queueTasks.filter { if case .ready = $0.status { return true } else { return false } }.count
            let isAnyDownloading = viewModel.queueTasks.contains { if case .downloading = $0.status { return true } else { return false } }
            
            if readyCount > 0 {
                Button {
                    viewModel.startAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text("\(L10n.text(.startAll, lang: viewModel.language)) (\(readyCount))")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            
            if isAnyDownloading {
                Button {
                    viewModel.pauseAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill").font(.system(size: 9))
                        Text(L10n.text(.pauseAll, lang: viewModel.language))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                }
                .buttonStyle(.plain)
            }
            
            Button {
                viewModel.clearCompleted()
            } label: {
                Text(L10n.text(.clearCompleted, lang: viewModel.language))
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
    }
    
    private var convertControls: some View {
        HStack(spacing: 8) {
            let runnableCount = viewModel.convertJobs.filter { $0.state == .ready || $0.state == .pending }.count
            
            if viewModel.isConverting {
                Button {
                    viewModel.stopConverting()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill").font(.system(size: 9))
                        Text("⏹️ 停止转换")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            } else if runnableCount > 0 {
                Button {
                    viewModel.startConverting()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 9))
                        Text("⚡️ 开始全部转换 (\(runnableCount))")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .cyan.opacity(0.3), radius: 3)
                }
                .buttonStyle(.plain)
            }
            
            Button {
                viewModel.clearCompletedConvertJobs()
            } label: {
                Text(L10n.text(.clearCompleted, lang: viewModel.language))
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
    }
    
    private var historyControls: some View {
        Button {
            viewModel.clearAllHistory()
        } label: {
            Text(L10n.text(.clearHistory, lang: viewModel.language))
                .foregroundColor(.secondary)
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 5. 网络下载队列舱 (QueueDeckView)
struct QueueDeckView: View {
    @ObservedObject var viewModel: DownloadViewModel
    
    var body: some View {
        Group {
            if viewModel.queueTasks.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(L10n.text(.emptyQueueTitle, lang: viewModel.language))
                        .font(.system(size: 15, weight: .medium))
                    Text(L10n.text(.emptyQueueSubtitle, lang: viewModel.language))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.queueTasks) { item in
                            DownloadTaskCardView(viewModel: viewModel, item: item)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                }
            }
        }
    }
}

// MARK: - 6. 万能转换舱 (ConvertDeckView)
struct ConvertDeckView: View {
    @ObservedObject var viewModel: DownloadViewModel
    
    var body: some View {
        Group {
            if viewModel.convertJobs.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                LinearGradient(colors: [.cyan.opacity(0.5), .blue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 1.8, dash: [8, 6])
                            )
                            .frame(maxWidth: 520, minHeight: 200)
                            .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial.opacity(0.4)))
                        
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            
                            Text(L10n.text(.emptyConvertTitle, lang: viewModel.language))
                                .font(.system(size: 15, weight: .bold))
                            
                            Text(L10n.text(.emptyConvertSubtitle, lang: viewModel.language))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            Button {
                                viewModel.selectLocalFilesForConvert()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text(L10n.text(.selectFiles, lang: viewModel.language))
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .padding(24)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.convertJobs) { job in
                            TranscodeJobCardView(viewModel: viewModel, job: job)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                }
            }
        }
    }
}

// MARK: - 7. 媒体历史记录舱 (HistoryDeckView)
struct HistoryDeckView: View {
    @ObservedObject var viewModel: DownloadViewModel
    
    var body: some View {
        Group {
            if viewModel.historyItems.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(L10n.text(.emptyHistoryTitle, lang: viewModel.language))
                        .font(.system(size: 15, weight: .medium))
                    Text(L10n.text(.emptyHistorySubtitle, lang: viewModel.language))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.historyItems) { item in
                            HistoryItemCardView(viewModel: viewModel, item: item)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                }
            }
        }
    }
}

// MARK: - 8. 单个下载任务卡片 (DownloadTaskCardView)
struct DownloadTaskCardView: View {
    @ObservedObject var viewModel: DownloadViewModel
    @ObservedObject var item: DownloadTaskItem
    
    var body: some View {
        HStack(spacing: 14) {
            // 封面与平台徽标
            ZStack(alignment: .bottomTrailing) {
                if let thumb = item.metadata?.thumbnail, let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.black.opacity(0.2)
                        }
                    }
                    .frame(width: 88, height: 62)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 88, height: 62)
                        .overlay(
                            Image(systemName: item.platform.iconName)
                                .font(.system(size: 24))
                                .foregroundColor(item.platform.themeColor.opacity(0.8))
                        )
                }
                
                // 平台微标
                HStack(spacing: 3) {
                    Image(systemName: item.platform.iconName).font(.system(size: 8))
                    Text(item.platform.rawValue).font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(item.platform.themeColor.opacity(0.85))
                .clipShape(Capsule())
                .padding(3)
            }
            
            // 详情与进度
            VStack(alignment: .leading, spacing: 6) {
                Text(item.metadata?.title ?? item.cleanURL)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                HStack(spacing: 10) {
                    if let meta = item.metadata {
                        Text(meta.authorName).font(.system(size: 11)).foregroundColor(.secondary)
                        Text(meta.formattedDuration).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Text(item.totalSize).font(.system(size: 11)).foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // 状态说明
                    statusBadge
                }
                
                // 进度条
                if case .downloading = item.status {
                    VStack(spacing: 3) {
                        ProgressView(value: item.progress)
                            .progressViewStyle(.linear)
                            .tint(.cyan)
                        HStack {
                            Text("\(Int(item.progress * 100))%").font(.system(size: 10)).foregroundColor(.cyan)
                            Spacer()
                            Text("\(item.speed) · ETA \(item.eta)").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
                
                // 操作区
                HStack(spacing: 8) {
                    if case .ready = item.status {
                        Picker("", selection: $item.quality) {
                            ForEach(DownloadQuality.allCases) { q in
                                Text(q.localizedName(lang: viewModel.language)).tag(q)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        
                        Button {
                            viewModel.enqueueDownload(item: item)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.to.line").font(.system(size: 10))
                                Text(L10n.text(.startDownload, lang: viewModel.language))
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if case .completed(let outURL) = item.status {
                        Button {
                            viewModel.previewItem(fileURL: outURL)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "eye.fill").font(.system(size: 10))
                                Text(L10n.text(.quickLookPreview, lang: viewModel.language)).font(.system(size: 11))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            viewModel.revealInFinder(fileURL: outURL)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "folder").font(.system(size: 10))
                                Text(L10n.text(.revealInFinder, lang: viewModel.language)).font(.system(size: 11))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                        }
                        .buttonStyle(.plain)
                        
                        // 一键转码按钮
                        Button {
                            let history = DownloadHistoryItem(
                                title: item.metadata?.title ?? "视频",
                                thumbnailURL: item.metadata?.thumbnail,
                                platform: item.platform,
                                filePath: outURL.path,
                                fileSizeString: item.totalSize,
                                durationString: item.metadata?.formattedDuration ?? ""
                            )
                            viewModel.convertDownloadedItem(item: history)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                                Text(L10n.text(.oneClickConvert, lang: viewModel.language)).font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.cyan.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Button {
                        viewModel.removeTask(item: item)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .waiting:
            Text(L10n.text(.waiting, lang: viewModel.language)).font(.system(size: 11)).foregroundColor(.orange)
        case .parsing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text(L10n.text(.parsing, lang: viewModel.language)).font(.system(size: 11)).foregroundColor(.cyan)
            }
        case .ready:
            Text(L10n.text(.readyStatus, lang: viewModel.language)).font(.system(size: 11)).foregroundColor(.green)
        case .queued:
            Text(L10n.text(.queued, lang: viewModel.language)).font(.system(size: 11)).foregroundColor(.orange)
        case .downloading:
            Text(L10n.text(.downloading, lang: viewModel.language)).font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
        case .merging:
            Text(L10n.text(.merging, lang: viewModel.language)).font(.system(size: 11)).foregroundColor(.purple)
        case .completed:
            Text(L10n.text(.completed, lang: viewModel.language)).font(.system(size: 11, weight: .bold)).foregroundColor(.green)
        case .failed(let err):
            Text(err).font(.system(size: 10)).foregroundColor(.red).lineLimit(1)
        case .cancelled:
            Text("已取消").font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}

// MARK: - 9. 单个转换任务卡片 (TranscodeJobCardView)
struct TranscodeJobCardView: View {
    @ObservedObject var viewModel: DownloadViewModel
    @ObservedObject var job: TranscodeJob
    
    var body: some View {
        HStack(spacing: 14) {
            // 格式大图标胶囊
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 58, height: 58)
                
                VStack(spacing: 2) {
                    Image(systemName: job.isEncryptedSource ? "lock.open.fill" : job.preset.symbol)
                        .font(.system(size: 18))
                        .foregroundColor(.cyan)
                    Text(job.sourceFormatLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.cyan)
                }
            }
            
            // 任务详情与规格
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(job.fileName)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // 硬件加速标签或直拷标签
                    if job.isDirectCopy {
                        Text("🚀 无损直拷 (0.1s)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    } else if job.isHardwareAccelerated {
                        Text("⚡️ VideoToolbox 硬编")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.cyan.opacity(0.12)))
                    }
                    
                    // 目标预设徽标
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right").font(.system(size: 9))
                        Text(job.preset.name).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(LinearGradient(colors: [.cyan.opacity(0.8), .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)))
                }
                
                HStack(spacing: 12) {
                    if !job.resolutionLabel.isEmpty {
                        Text(job.resolutionLabel).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    if !job.durationLabel.isEmpty {
                        Text(job.durationLabel).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    if let strategy = job.plan?.humanReadable, !strategy.isEmpty {
                        Text(strategy).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 状态说明或 FPS
                    if job.state == .running {
                        HStack(spacing: 6) {
                            if job.fps > 0 {
                                Text("\(Int(job.fps)) FPS").font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
                            }
                            if !job.speedText.isEmpty {
                                Text(job.speedText).font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                    } else {
                        jobStateBadge
                    }
                }
                
                // 进度条
                if job.state == .running || job.state == .decrypting {
                    VStack(spacing: 3) {
                        ProgressView(value: job.progress)
                            .progressViewStyle(.linear)
                            .tint(.cyan)
                        HStack {
                            Text(job.state == .decrypting ? "解密中 \(job.formattedProgress)" : "转码中 \(job.formattedProgress)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.cyan)
                            Spacer()
                        }
                    }
                }
                
                // 操作栏
                HStack(spacing: 8) {
                    if job.state == .ready || job.state == .pending {
                        Button {
                            viewModel.startConverting()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill").font(.system(size: 9))
                                Text(L10n.text(.startTranscode, lang: viewModel.language))
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if job.state == .completed, let outURL = job.outputURL {
                        Button {
                            viewModel.previewItem(fileURL: outURL)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "eye.fill").font(.system(size: 10))
                                Text(L10n.text(.quickLookPreview, lang: viewModel.language)).font(.system(size: 11))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            viewModel.revealInFinder(fileURL: outURL)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "folder").font(.system(size: 10))
                                Text(L10n.text(.revealInFinder, lang: viewModel.language)).font(.system(size: 11))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Button {
                        viewModel.removeConvertJob(job: job)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var jobStateBadge: some View {
        switch job.state {
        case .pending:
            Text("等待中").font(.system(size: 11)).foregroundColor(.orange)
        case .decrypting:
            Text("离线解密中...").font(.system(size: 11)).foregroundColor(.purple)
        case .analyzing:
            Text("探测分析中...").font(.system(size: 11)).foregroundColor(.cyan)
        case .ready:
            Text("已就绪").font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
        case .running:
            Text("正在极速转码...").font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
        case .completed:
            Text("转换完成").font(.system(size: 11, weight: .bold)).foregroundColor(.green)
        case .failed:
            Text(job.errorMessage ?? "转换失败").font(.system(size: 10)).foregroundColor(.red).lineLimit(1)
        case .cancelled:
            Text("已取消").font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}

// MARK: - 10. 单个历史记录卡片 (HistoryItemCardView)
struct HistoryItemCardView: View {
    @ObservedObject var viewModel: DownloadViewModel
    let item: DownloadHistoryItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标与平台标识
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.platform.themeColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: item.platform.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(item.platform.themeColor)
            }
            
            // 文本信息
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                HStack(spacing: 10) {
                    Text(item.platform.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(item.platform.themeColor)
                    Text(item.fileSizeString)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if !item.durationString.isEmpty {
                        Text(item.durationString)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text(item.formattedDate)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 操作按钮群
            HStack(spacing: 6) {
                // 空格预览
                Button {
                    viewModel.previewItem(fileURL: item.fileURL)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.fill").font(.system(size: 10))
                        Text(L10n.text(.quickLookPreview, lang: viewModel.language)).font(.system(size: 11))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .help("空格一键播放")
                
                // 访达定位
                Button {
                    viewModel.revealInFinder(fileURL: item.fileURL)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder").font(.system(size: 10))
                        Text(L10n.text(.revealInFinder, lang: viewModel.language)).font(.system(size: 11))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary))
                }
                .buttonStyle(.plain)
                
                // 一键转码
                Button {
                    viewModel.convertDownloadedItem(item: item)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                        Text(L10n.text(.oneClickConvert, lang: viewModel.language)).font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.cyan.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("把下载的原片立即送入万能转换舱")
                
                // 删除记录
                Button {
                    viewModel.removeHistory(item: item)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                        .padding(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - 11. 拖拽全域呼吸遮罩 (DragAndDropOverlayView)
struct DragAndDropOverlayView: View {
    @ObservedObject var viewModel: DownloadViewModel
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            
            VStack(spacing: 14) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text(L10n.text(.dropPrompt, lang: viewModel.language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Text("丢入网址自动下载 · 丢入本地视频/音频/加密音乐自动转码")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
            )
        }
    }
}

// MARK: - 12. 偏好设置面板 (SettingsSheetView)
struct SettingsSheetView: View {
    @ObservedObject var viewModel: DownloadViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack {
                Text(L10n.text(.settings, lang: viewModel.language))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(L10n.text(.done, lang: viewModel.language)) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            // 选项卡切换
            Picker("", selection: $selectedTab) {
                Text("📥 网络下载").tag(0)
                Text("🔄 格式转换").tag(1)
                Text("🎨 外观与常规").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            
            // 内容区域
            Form {
                if selectedTab == 0 {
                    downloadSettingsSection
                } else if selectedTab == 1 {
                    convertSettingsSection
                } else {
                    generalSettingsSection
                }
            }
            .padding()
            
            Spacer()
        }
        .frame(width: 520, height: 440)
    }
    
    private var downloadSettingsSection: some View {
        Section("网络下载偏好") {
            HStack {
                Text("下载保存路径:")
                Spacer()
                Text(viewModel.downloadFolderURL.lastPathComponent).foregroundColor(.secondary)
                Button(L10n.text(.changeFolder, lang: viewModel.language)) {
                    viewModel.selectOutputFolder()
                }
            }
            
            Toggle("自动开始下载 (无需手动点击)", isOn: $viewModel.autoStartDownload)
            Toggle("无水印高清原画 (支持平台自动去印)", isOn: $viewModel.removeWatermark)
            
            Stepper("并发下载分片数: \(viewModel.concurrentFragments)", value: $viewModel.concurrentFragments, in: 1...16)
        }
    }
    
    private var convertSettingsSection: some View {
        Section("万能转换与硬件加速") {
            Toggle("VideoToolbox 硬件加速 (Apple Silicon GPU 编码)", isOn: $viewModel.useHardwareAcceleration)
            
            Picker("默认输出预设", selection: Binding(get: { viewModel.activePreset.id }, set: { id in
                if let p = PresetLibrary.preset(id: id) { viewModel.selectPreset(p) }
            })) {
                ForEach(viewModel.allPresets) { p in
                    Text("\(p.name) (\(p.summary))").tag(p.id)
                }
            }
            
            HStack {
                Text("转换输出目录:")
                Spacer()
                Text(viewModel.convertOutputFolderURL.lastPathComponent).foregroundColor(.secondary)
                Button(L10n.text(.changeFolder, lang: viewModel.language)) {
                    viewModel.selectConvertOutputFolder()
                }
            }
            
            HStack {
                Text("系统硬件加速支持:")
                Spacer()
                Text(viewModel.ffmpegReport.hardwareBadgeText)
                    .foregroundColor(viewModel.ffmpegReport.hasVideoToolbox ? .green : .secondary)
            }
        }
    }
    
    private var generalSettingsSection: some View {
        Section("常规与外观") {
            Picker("外观显示模式", selection: $viewModel.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName(lang: viewModel.language)).tag(mode)
                }
            }
            
            Picker("界面语言 / Language", selection: $viewModel.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            
            HStack {
                Text("系统依赖状态:")
                Spacer()
                Text(viewModel.environmentStatus.isReady ? "已就绪" : "缺失依赖")
                    .foregroundColor(viewModel.environmentStatus.isReady ? .green : .red)
            }
        }
    }
}
