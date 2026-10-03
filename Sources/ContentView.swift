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
            // 背景毛玻璃液态材质
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. 沉浸式顶部栏（包含 Logo、中英语言切换、队列/历史 Tab 切换与环境指示灯）
                headerBar
                
                // 2. 顶部唯一输入与全局设置栏 (自适应多行、智能感知剪贴板、分析-开始流水线)
                VStack(spacing: 12) {
                    urlInputSection
                    storageAndSettingsBar
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 10)
                
                Divider().opacity(0.15)
                
                // 4. 主体内容区（下载队列 / 历史记录）
                ZStack {
                    if viewModel.currentTab == .queue {
                        queueView
                    } else {
                        historyView
                    }
                    
                    // 全域拖拽高光呼吸提示层
                    if viewModel.isDraggingOver {
                        dragAndDropOverlay
                    }
                }
            }
        }
        .frame(minWidth: 780, idealWidth: 840, maxWidth: 1000, minHeight: 580, idealHeight: 640)
        // 绑定全窗口拖拽监听
        .onDrop(of: ["public.url", "public.plain-text", "public.utf8-plain-text"], isTargeted: $viewModel.isDraggingOver) { providers in
            viewModel.handleDrop(providers: providers)
        }
        // 绑定全局空格一键预览快捷键（输入框打字时不拦截，防止重复绑定）
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
    
    // MARK: - 1. 自定义沉浸式顶部栏
    private var headerBar: some View {
        HStack(spacing: 14) {
            Spacer().frame(width: 68) // 交通灯安全间距
            
            // 软件中文品牌与流光极简图标
            HStack(spacing: 8) {
                if let nsImg = NSImage(contentsOfFile: Bundle.main.bundlePath + "/Contents/Resources/AppIcon.icns") ?? NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                
                Text(L10n.text(.appName, lang: viewModel.language))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // 核心功能标签页切换 (下载队列 / 历史记录)
            Picker("", selection: $viewModel.currentTab) {
                Text("\(L10n.text(.tabQueue, lang: viewModel.language)) (\(viewModel.queueTasks.count))")
                    .tag(MainTab.queue)
                Text("\(L10n.text(.tabHistory, lang: viewModel.language)) (\(viewModel.historyItems.count))")
                    .tag(MainTab.history)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            
            Spacer()
            
            // 偏好设置入口按钮
            Button {
                viewModel.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .help(L10n.text(.settings, lang: viewModel.language))
            
            // 中英文即时切换胶囊按钮
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleLanguage()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text(viewModel.language == .zh ? "EN" : "中")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .help("切换界面语言 / Toggle Language")
            
            // 环境状态微灯
            HStack(spacing: 5) {
                Circle()
                    .fill(viewModel.environmentStatus.isReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.environmentStatus.isReady ? L10n.text(.envOk, lang: viewModel.language) : L10n.text(.envMissing, lang: viewModel.language))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.trailing, 18)
        }
        .frame(height: 50)
        .background(.ultraThinMaterial.opacity(0.8))
        .overlay(Divider().opacity(0.15), alignment: .bottom)
    }
    
    // MARK: - 2. 顶部单一输入区 (支持多行自适应、无截断、智能感知剪贴板、分析-开始流水线)
    private var urlInputSection: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: viewModel.isClipboardAutoFilled ? "doc.on.clipboard.fill" : "link")
                    .foregroundColor(viewModel.isClipboardAutoFilled ? .cyan : .secondary)
                    .font(.system(size: 14))
                
                // 关键优化：支持多行垂直自适应高度 (lineLimit 1...4)，彻底解决粘贴小红书/抖音等带换行长文案时内容被顶部截断的问题
                TextField(
                    L10n.text(.inputPlaceholder, lang: viewModel.language),
                    text: $viewModel.urlInput,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit {
                    if !viewModel.urlInput.isEmpty {
                        viewModel.parseAndAdd(rawText: viewModel.urlInput)
                    }
                }
                
                // 剪贴板自动感知轻量角标提示
                if viewModel.isClipboardAutoFilled && !viewModel.urlInput.isEmpty {
                    Text(L10n.text(.autoFilledNotice, lang: viewModel.language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cyan.opacity(0.12)))
                }
                
                // 快捷清空按钮
                if !viewModel.urlInput.isEmpty {
                    Button {
                        viewModel.urlInput = ""
                        viewModel.isClipboardAutoFilled = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                viewModel.isClipboardAutoFilled
                                    ? Color.cyan.opacity(0.55)
                                    : Color.white.opacity(colorScheme == .dark ? 0.15 : 0.4),
                                lineWidth: 1
                            )
                    )
            )
            
            // 右侧“解析视频”按钮（分析阶段）
            Button {
                if !viewModel.urlInput.isEmpty {
                    viewModel.parseAndAdd(rawText: viewModel.urlInput)
                } else if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
                    let clean = YTDLPService.extractCleanURL(from: clip)
                    if clean.hasPrefix("http://") || clean.hasPrefix("https://") {
                        viewModel.parseAndAdd(rawText: clean)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                    Text(L10n.text(.parseVideo, lang: viewModel.language))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(minHeight: 40)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 4. 存储路径与特性配置条
    private var storageAndSettingsBar: some View {
        HStack(spacing: 12) {
            // 目录选择卡片
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                
                Text(L10n.text(.saveLocation, lang: viewModel.language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(viewModel.downloadFolderURL.path)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(viewModel.downloadFolderURL.path)
                
                Spacer()
                
                Button {
                    viewModel.selectOutputFolder()
                } label: {
                    Text(L10n.text(.changeFolder, lang: viewModel.language))
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    viewModel.openOutputFolder()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(L10n.text(.openFolder, lang: viewModel.language))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial.opacity(0.7))
            )
            
            // 无水印开关、自动下载控制与加速状态
            HStack(spacing: 8) {
                Toggle(isOn: $viewModel.removeWatermark) {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .foregroundColor(.cyan)
                        Text(L10n.text(.noWatermark, lang: viewModel.language))
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .toggleStyle(.checkbox)
                
                Divider().frame(height: 14)
                
                Toggle(isOn: Binding(
                    get: { viewModel.autoStartDownload },
                    set: {
                        viewModel.autoStartDownload = $0
                        UserDefaults.standard.set($0, forKey: "FlowStream_AutoStartDownload_v2")
                    }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle")
                            .foregroundColor(viewModel.autoStartDownload ? .blue : .secondary)
                        Text(L10n.text(.autoStart, lang: viewModel.language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(viewModel.autoStartDownload ? .primary : .secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .help("默认关闭：加入队列后先解析并呈现实时卡片，由您选择画质并手动点击开始；勾选后则加入即自动下载")
                
                Divider().frame(height: 14)
                
                HStack(spacing: 4) {
                    Image(systemName: "bolt.badge.automatic.fill")
                        .foregroundColor(.yellow)
                    Text(L10n.text(.acceleration, lang: viewModel.language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial.opacity(0.7))
            )
        }
    }
    
    // MARK: - 5. 视图：下载队列
    private var queueView: some View {
        VStack(spacing: 0) {
            if viewModel.queueTasks.isEmpty {
                emptyQueueView
            } else {
                // 队列快捷操作顶栏
                queueHeaderToolbar
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(viewModel.queueTasks) { item in
                            TaskCardItemView(item: item, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 50)
                }
            }
            
            // 底部队列控制状态栏
            if !viewModel.queueTasks.isEmpty {
                queueBottomToolbar
            }
        }
    }
    
    // MARK: - 队列顶部汇总与批量控制栏
    private var queueHeaderToolbar: some View {
        let readyCount = viewModel.queueTasks.filter { $0.status == .ready }.count
        let activeCount = viewModel.queueTasks.filter {
            if case .downloading = $0.status { return true }
            if case .merging = $0.status { return true }
            if $0.status == .queued { return true }
            return false
        }.count
        
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(viewModel.language == .zh ? "任务列表" : "Tasks")
                    .font(.system(size: 13, weight: .bold))
                Text("(\(viewModel.queueTasks.count))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                if readyCount > 0 {
                    Text("• \(readyCount) \(viewModel.language == .zh ? "个待下载" : "ready")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                }
                if activeCount > 0 {
                    Text("• \(activeCount) \(viewModel.language == .zh ? "个下载中/排队" : "active")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cyan)
                }
            }
            
            Spacer()
            
            // 全部开始
            if readyCount > 0 {
                Button {
                    viewModel.startAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text(L10n.text(.startAll, lang: viewModel.language))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
            
            // 全部暂停
            if activeCount > 0 {
                Button {
                    viewModel.pauseAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                        Text(L10n.text(.pauseAll, lang: viewModel.language))
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // 清空已完成
            Button {
                viewModel.clearCompleted()
            } label: {
                Text(L10n.text(.clearCompleted, lang: viewModel.language))
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    // MARK: - 6. 视图：历史记录
    private var historyView: some View {
        VStack(spacing: 0) {
            if viewModel.historyItems.isEmpty {
                emptyHistoryView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.historyItems) { item in
                            historyCardView(item)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 50)
                }
            }
            
            if !viewModel.historyItems.isEmpty {
                historyBottomToolbar
            }
        }
    }
    
    // MARK: - 7. 任务卡片视图（独立观察者结构体，保证状态变更 0 延迟即时重绘）
    struct TaskCardItemView: View {
        @ObservedObject var item: DownloadTaskItem
        @ObservedObject var viewModel: DownloadViewModel
        @Environment(\.colorScheme) private var colorScheme
        
        var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // 缩略图 / 占位
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.2))
                    
                    if let thumbStr = item.metadata?.thumbnail, let thumbURL = URL(string: thumbStr) {
                        AsyncImage(url: thumbURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                ProgressView().controlSize(.small)
                            }
                        }
                    } else {
                        Image(systemName: item.platform.iconName)
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 140, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
                
                // 右侧元数据与状态
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        // 平台徽章
                        HStack(spacing: 4) {
                            Image(systemName: item.platform.iconName)
                                .font(.system(size: 9))
                            Text(item.platform.rawValue)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(item.platform.themeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(item.platform.themeColor.opacity(0.12)))
                        
                        Text(item.metadata?.title ?? item.cleanURL)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .help(item.metadata?.title ?? item.cleanURL)
                        
                        Spacer()
                        
                        // 删除卡片
                        Button {
                            viewModel.removeTask(item: item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.7))
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // 状态说明文字
                    HStack(spacing: 10) {
                        if let dur = item.metadata?.formattedDuration {
                            Label(dur, systemImage: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        if let auth = item.metadata?.authorName {
                            Label(auth, systemImage: "person.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        if item.totalSize != "--" {
                            Label(item.totalSize, systemImage: "internaldrive")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // 状态与操作流转
                    switch item.status {
                    case .waiting:
                        HStack {
                            Text(L10n.text(.waiting, lang: viewModel.language))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    case .parsing:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.text(.parsing, lang: viewModel.language))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    case .ready:
                        HStack(spacing: 12) {
                            Picker("", selection: Binding(get: { item.quality }, set: { item.quality = $0 })) {
                                ForEach(DownloadQuality.allCases) { q in
                                    Text(q.localizedName(lang: viewModel.language)).tag(q)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 240)
                            
                            Spacer()
                            
                            Button {
                                viewModel.enqueueDownload(item: item)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                    Text(L10n.text(.startDownload, lang: viewModel.language))
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    case .queued:
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.small)
                                Text(L10n.text(.queued, lang: viewModel.language))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            
                            Spacer()
                            
                            Button {
                                viewModel.cancelTask(item: item)
                            } label: {
                                Text("取消排队")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    case .downloading, .merging:
                        VStack(spacing: 6) {
                            HStack {
                                Text(String(format: "%.1f%%", item.progress * 100))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                
                                Text(item.status == .merging ? L10n.text(.merging, lang: viewModel.language) : L10n.text(.downloading, lang: viewModel.language))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                if item.speed != "--" {
                                    Label(item.speed, systemImage: "bolt.fill")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.cyan)
                                }
                                if item.eta != "--" {
                                    Label("ETA: \(item.eta)", systemImage: "timer")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                Button {
                                    viewModel.cancelTask(item: item)
                                } label: {
                                    Image(systemName: "pause.circle.fill")
                                        .foregroundColor(.red.opacity(0.85))
                                        .font(.system(size: 13))
                                }
                                .buttonStyle(.plain)
                                .help("暂停当前下载")
                            }
                            
                            // 渐变进度条
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 6)
                                    Capsule()
                                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(0, min(g.size.width * CGFloat(item.progress), g.size.width)), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    case .completed(let url):
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(L10n.text(.completed, lang: viewModel.language))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.green)
                            }
                            
                            Spacer()
                            
                            // 空格预览播放
                            Button {
                                viewModel.previewItem(fileURL: url)
                            } label: {
                                Label(L10n.text(.quickLookPreview, lang: viewModel.language), systemImage: "eye.fill")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            // 在访达中打开
                            Button {
                                viewModel.revealInFinder(fileURL: url)
                            } label: {
                                Label(L10n.text(.revealInFinder, lang: viewModel.language), systemImage: "folder.fill")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    case .failed(let err):
                        HStack {
                            Text("失败: \(err)")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                                .lineLimit(2)
                            Spacer()
                            Button("重试") {
                                viewModel.retryTask(item: item)
                            }
                            .controlSize(.small)
                            
                            Button("移除") {
                                viewModel.removeTask(item: item)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    case .cancelled:
                        HStack {
                            Text("已暂停").font(.system(size: 11)).foregroundColor(.secondary)
                            Spacer()
                            Button("继续下载") {
                                viewModel.enqueueDownload(item: item)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 1)
                )
        )
    }
}
    
    // MARK: - 8. 历史卡片视图
    private func historyCardView(_ item: DownloadHistoryItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.2))
                
                if let thumbStr = item.thumbnailURL, let thumbURL = URL(string: thumbStr) {
                    AsyncImage(url: thumbURL) { p in
                        if let img = p.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "film").foregroundColor(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "film").foregroundColor(.secondary)
                }
            }
            .frame(width: 90, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: item.platform.iconName).font(.system(size: 8))
                        Text(item.platform.rawValue).font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(item.platform.themeColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(item.platform.themeColor.opacity(0.12)))
                    
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .help(item.title)
                }
                
                HStack(spacing: 12) {
                    Text(item.fileSizeString)
                    Text("•")
                    Text(item.formattedDate)
                    if !item.fileExists {
                        Text(L10n.text(.fileMissing, lang: viewModel.language))
                            .foregroundColor(.orange)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // 空格原生 QuickLook 播放
                Button {
                    viewModel.previewItem(fileURL: item.fileURL)
                } label: {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.text(.quickLookPreview, lang: viewModel.language))
                
                // 访达定位
                Button {
                    viewModel.revealInFinder(fileURL: item.fileURL)
                } label: {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.text(.revealInFinder, lang: viewModel.language))
                
                // 删除历史记录
                Button {
                    viewModel.removeHistory(item: item)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
    
    // MARK: - 9. 底部工具栏
    private var queueBottomToolbar: some View {
        HStack {
            Text("共 \(viewModel.queueTasks.count) 个任务")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button {
                viewModel.clearCompleted()
            } label: {
                Text(L10n.text(.clearCompleted, lang: viewModel.language))
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    private var historyBottomToolbar: some View {
        HStack {
            Text("共 \(viewModel.historyItems.count) 条已下载历史")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(role: .destructive) {
                viewModel.clearAllHistory()
            } label: {
                Text(L10n.text(.clearHistory, lang: viewModel.language))
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - 10. 空状态视图
    private var emptyQueueView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 44))
                .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(0.8)
            
            Text(L10n.text(.emptyQueueTitle, lang: viewModel.language))
                .font(.system(size: 16, weight: .bold))
            
            Text(L10n.text(.emptyQueueSubtitle, lang: viewModel.language))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
    
    private var emptyHistoryView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(L10n.text(.emptyHistoryTitle, lang: viewModel.language))
                .font(.system(size: 16, weight: .bold))
            
            Text(L10n.text(.emptyHistorySubtitle, lang: viewModel.language))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
    
    // MARK: - 11. 拖拽全屏流光覆盖层 (Drop Zone)
    private var dragAndDropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.blue.opacity(0.12))
                .background(.ultraThinMaterial)
            
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 3, dash: [8, 4])
                )
            
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text(L10n.text(.dropPrompt, lang: viewModel.language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
            }
        }
        .padding(16)
    }
}

// MARK: - 12. 偏好设置模态窗口
struct SettingsSheetView: View {
    @ObservedObject var viewModel: DownloadViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: SettingsTab = .general
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "下载偏好"
        case system = "内核环境"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .system: return "cpu"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航区
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(L10n.text(.settings, lang: viewModel.language))
                        .font(.system(size: 15, weight: .bold))
                }
                
                Spacer()
                
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Spacer()
                
                Button(L10n.text(.done, lang: viewModel.language)) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // 内容区域
            ScrollView {
                VStack(spacing: 20) {
                    switch selectedTab {
                    case .general:
                        generalSettingsSection
                    case .system:
                        systemSettingsSection
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 580, height: 440)
    }
    
    // MARK: - 下载与存储偏好设置
    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 保存路径
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text(.saveLocation, lang: viewModel.language))
                    .font(.system(size: 12, weight: .bold))
                
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                    Text(viewModel.downloadFolderURL.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button(L10n.text(.changeFolder, lang: viewModel.language)) {
                        viewModel.selectOutputFolder()
                    }
                    .controlSize(.small)
                    
                    Button(L10n.text(.openFolder, lang: viewModel.language)) {
                        viewModel.openOutputFolder()
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            }
            
            Divider()
            
            // 开关组
            VStack(spacing: 14) {
                Toggle(isOn: $viewModel.removeWatermark) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text(.noWatermark, lang: viewModel.language))
                            .font(.system(size: 13, weight: .medium))
                        Text("针对抖音、快手等平台，自动启用原生算法去除平台水印")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(isOn: $viewModel.autoStartDownload) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text(.autoStart, lang: viewModel.language))
                            .font(.system(size: 13, weight: .medium))
                        Text("视频链接解析完成后，无需手动点击，自动加入高速下载流水线")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - 系统内核环境
    private var systemSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("核心底层引擎状态")
                .font(.system(size: 12, weight: .bold))
            
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("yt-dlp 核心引擎")
                            .font(.system(size: 12, weight: .bold))
                        Text(viewModel.environmentStatus.ytdlpPath ?? "未检测到")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if viewModel.environmentStatus.ytdlpPath != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                
                HStack {
                    Image(systemName: "film.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ffmpeg 音视频合成转码器")
                            .font(.system(size: 12, weight: .bold))
                        Text(viewModel.environmentStatus.ffmpegPath ?? "未检测到")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if viewModel.environmentStatus.ffmpegPath != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            }
            
            HStack {
                Spacer()
                Button("重新检测环境") {
                    viewModel.refreshEnvironment()
                }
                .controlSize(.regular)
                Spacer()
            }
            .padding(.top, 8)
        }
    }
}

