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
                // 1. 沉浸式顶部栏（交通灯安全边距、居中发光三舱切换药丸、右侧设置三件套与环境指示）
                HeaderBarView(viewModel: viewModel)
                
                // 2. 方案 A 核心结构：智能万能一体流输入区 + 6大预设卡片面板 (转换模式展现) + 快捷行动栏 (硬件加速开关)
                VStack(spacing: 10) {
                    UniversalInputBarView(viewModel: viewModel, isInputFocused: _isInputFocused)
                    
                    if viewModel.currentTab == .convert {
                        PresetCardsPanelView(viewModel: viewModel)
                    }
                    
                    SubActionBarView(viewModel: viewModel)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 10)
                
                Divider().opacity(0.12)
                
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
            Spacer().frame(width: 72) // 交通灯安全边距
            
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
            
            // 居中发光三舱切换药丸 (网络下载 / 万能转换 / 媒体历史) - 方案 A 专属流光样式
            HStack(spacing: 2) {
                tabButton(
                    tab: .queue,
                    title: viewModel.language == .zh ? "网络下载" : "Queue",
                    icon: "arrow.down.to.line",
                    count: viewModel.queueTasks.count
                )
                tabButton(
                    tab: .convert,
                    title: viewModel.language == .zh ? "万能转换" : "Convert",
                    icon: "arrow.triangle.2.circlepath",
                    count: viewModel.convertJobs.count
                )
                tabButton(
                    tab: .history,
                    title: viewModel.language == .zh ? "媒体历史" : "History",
                    icon: "clock.arrow.circlepath",
                    count: viewModel.historyItems.count
                )
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            
            Spacer()
            
            // 外观模式菜单 (黑夜 / 白天 / 系统)
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
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // 中英文即时切换
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleLanguage()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text(viewModel.language == .zh ? "中/EN" : "EN/中")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            
            // 偏好设置
            Button {
                viewModel.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .help(L10n.text(.settings, lang: viewModel.language))
            
            // VideoToolbox 硬件加速或环境状态灯
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.ffmpegReport.hasVideoToolbox ? Color.green : Color.orange)
                    .frame(width: 6.5, height: 6.5)
                    .shadow(color: viewModel.ffmpegReport.hasVideoToolbox ? .green.opacity(0.7) : .clear, radius: 4)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 48)
        .background(.ultraThinMaterial.opacity(0.85))
        .overlay(Divider().opacity(0.15), alignment: .bottom)
    }
    
    private func tabButton(tab: MainTab, title: String, icon: String, count: Int) -> some View {
        let isSelected = viewModel.currentTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.currentTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                if count > 0 {
                    Text("(\(count))")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 5.5)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                    } else {
                        Color.clear
                    }
                }
            )
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 0.1, green: 0.9, blue: 0.95), lineWidth: 1.5)
                            .shadow(color: Color(red: 0.1, green: 0.9, blue: 0.95).opacity(0.8), radius: 6)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2. 方案 A 智能万能输入条 (UniversalInputBarView)
struct UniversalInputBarView: View {
    @ObservedObject var viewModel: DownloadViewModel
    @FocusState var isInputFocused: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                if viewModel.currentTab == .history {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    
                    TextField(
                        L10n.text(.searchHistoryPlaceholder, lang: viewModel.language),
                        text: $viewModel.historySearchText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isInputFocused)
                    
                    if !viewModel.historySearchText.isEmpty {
                        Button {
                            viewModel.historySearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Image(systemName: viewModel.isClipboardAutoFilled ? "doc.on.clipboard.fill" : (viewModel.currentTab == .convert ? "folder.badge.plus" : "link.badge.plus"))
                        .foregroundColor(viewModel.isClipboardAutoFilled ? .cyan : .secondary)
                        .font(.system(size: 14))
                    
                    TextField(
                        inputPlaceholder,
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
                    .help("浏览本地视频、音频或加密音乐 (NCM/MFLAC)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.black.opacity(0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        isInputFocused
                            ? LinearGradient(colors: [.cyan.opacity(0.85), .blue.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                        lineWidth: isInputFocused ? 1.5 : 1
                    )
            )
            
            // 亮青色行动大按钮 (智能解析 / 转换 / 下载)
            if viewModel.currentTab != .history {
                Button {
                    viewModel.smartHandleInput()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                        Text(actionButtonTitle)
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
    
    private var inputPlaceholder: String {
        if viewModel.currentTab == .convert {
            return L10n.text(.convertInputPlaceholder, lang: viewModel.language)
        }
        return L10n.text(.inputPlaceholder, lang: viewModel.language)
    }
    
    private var actionButtonTitle: String {
        if viewModel.currentTab == .convert {
            return viewModel.language == .zh ? "智能解析 / 转码" : "Smart Transcode"
        }
        return viewModel.language == .zh ? "智能解析 / 下载" : "Smart Download"
    }
}

// MARK: - 3. 方案 A 专属：6大高频预设卡片面板 (PresetCardsPanelView)
struct PresetCardsPanelView: View {
    @ObservedObject var viewModel: DownloadViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            // 6 大核心高频预设卡片 (完全还原 Scheme A 样式)
            presetCard(
                title: "MP4 (H.264)",
                presetId: viewModel.useHardwareAcceleration ? "mp4-h264-hw" : "mp4-h264",
                iconType: .mp4
            )
            
            presetCard(
                title: "4K HEVC",
                presetId: viewModel.useHardwareAcceleration ? "mp4-hevc-hw" : "mp4-hevc",
                iconType: .hevc4k
            )
            
            presetCard(
                title: "ProRes 422",
                presetId: "mov-prores",
                iconType: .prores
            )
            
            presetCard(
                title: "GIF",
                presetId: "gif",
                iconType: .gif
            )
            
            presetCard(
                title: "320K MP3",
                presetId: "audio-mp3",
                iconType: .mp3
            )
            
            presetCard(
                title: "NCM音乐解锁",
                presetId: "audio-flac",
                iconType: .ncm
            )
            
            // 更多 28 大预设下拉菜单
            morePresetsMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
    
    enum CardIconType {
        case mp4, hevc4k, prores, gif, mp3, ncm
    }
    
    private func isCardSelected(type: CardIconType) -> Bool {
        let activeId = viewModel.activePreset.id
        switch type {
        case .mp4:
            return activeId == "mp4-h264" || activeId == "mp4-h264-hw"
        case .hevc4k:
            return activeId == "mp4-hevc" || activeId == "mp4-hevc-hw"
        case .prores:
            return activeId == "mov-prores"
        case .gif:
            return activeId == "gif"
        case .mp3:
            return activeId == "audio-mp3"
        case .ncm:
            return activeId == "audio-flac"
        }
    }
    
    private func presetCard(title: String, presetId: String, iconType: CardIconType) -> some View {
        let isSelected = isCardSelected(type: iconType)
        return Button {
            if let p = PresetLibrary.preset(id: presetId) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    viewModel.selectPreset(p)
                }
            }
        } label: {
            VStack(spacing: 6) {
                iconView(for: iconType)
                    .frame(height: 28)
                
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.38) : Color.white.opacity(0.06), lineWidth: isSelected ? 1.2 : 1)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.25) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func iconView(for type: CardIconType) -> some View {
        switch type {
        case .mp4:
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.2)
                    .frame(width: 24, height: 26)
                Text("MP4")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
        case .hevc4k:
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.2)
                    .frame(width: 27, height: 26)
                VStack(spacing: 0.5) {
                    Text("4K")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                    Text("HEVC")
                        .font(.system(size: 6.5, weight: .bold))
                }
                .foregroundColor(.white)
            }
        case .prores:
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.2)
                    .frame(width: 38, height: 22)
                Text("ProRes 422")
                    .font(.system(size: 6.8, weight: .bold))
                    .foregroundColor(.white)
            }
        case .gif:
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.2)
                    .frame(width: 26, height: 26)
                Text("GIF")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
        case .mp3:
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.2)
                    .frame(width: 24, height: 26)
                VStack(spacing: 1) {
                    Image(systemName: "music.note")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("MP3")
                        .font(.system(size: 6.5, weight: .heavy))
                }
                .foregroundColor(.white)
            }
        case .ncm:
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.9))
                Image(systemName: "music.note")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.cyan)
                    .offset(x: 2, y: 2)
            }
            .frame(height: 26)
        }
    }
    
    private var isNonStandardSelected: Bool {
        let id = viewModel.activePreset.id
        return !["mp4-h264", "mp4-h264-hw", "mp4-hevc", "mp4-hevc-hw", "mov-prores", "gif", "audio-mp3", "audio-flac"].contains(id)
    }
    
    private var morePresetsMenu: some View {
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
            VStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                HStack(spacing: 2) {
                    Text(isNonStandardSelected ? viewModel.activePreset.name : L10n.text(.morePresets, lang: viewModel.language))
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                }
            }
            .foregroundColor(isNonStandardSelected ? .cyan : Color.white.opacity(0.72))
            .frame(width: 74, height: 66)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isNonStandardSelected ? Color.cyan.opacity(0.14) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isNonStandardSelected ? Color.cyan.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - 4. 辅助设置与状态控制栏 (SubActionBarView)
struct SubActionBarView: View {
    @ObservedObject var viewModel: DownloadViewModel
    
    var body: some View {
        HStack(spacing: 12) {
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
            
            // 中间舱位专属操作按钮组
            if viewModel.currentTab == .queue {
                queueControls
            } else if viewModel.currentTab == .convert {
                convertControls
            } else {
                historyControls
            }
            
            // 右侧 VideoToolbox 硬件加速开关药丸 (效果图方案 A 标配)
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(viewModel.useHardwareAcceleration ? .yellow : .secondary)
                    .font(.system(size: 11))
                Text(viewModel.language == .zh ? "VideoToolbox 硬件加速" : "VideoToolbox Turbo")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(viewModel.useHardwareAcceleration ? .primary : .secondary)
                Toggle("", isOn: $viewModel.useHardwareAcceleration)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(Color(red: 0.1, green: 0.85, blue: 0.85))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
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
                        Text(L10n.text(.stopTranscode, lang: viewModel.language))
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
                        Text("\(L10n.text(.startAllTranscode, lang: viewModel.language)) (\(runnableCount))")
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
        HStack(spacing: 10) {
            Text("共 \(viewModel.filteredHistoryItems.count) 条记录")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            
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
            if viewModel.filteredHistoryItems.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(viewModel.historyItems.isEmpty ? L10n.text(.emptyHistoryTitle, lang: viewModel.language) : "未找到匹配的历史记录")
                        .font(.system(size: 15, weight: .medium))
                    Text(viewModel.historyItems.isEmpty ? L10n.text(.emptyHistorySubtitle, lang: viewModel.language) : "请尝试更改搜索关键字")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.filteredHistoryItems) { item in
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

// MARK: - 发光青色霓虹进度条 (GlowingProgressBar)
struct GlowingProgressBar: View {
    var progress: Double
    var height: CGFloat = 3.5
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: height)
                
                let fillWidth = max(0, min(geo.size.width, geo.size.width * CGFloat(progress)))
                if fillWidth > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.1, green: 0.92, blue: 0.98), Color(red: 0.0, green: 0.78, blue: 0.92)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: height)
                        .shadow(color: Color(red: 0.1, green: 0.9, blue: 0.95).opacity(0.85), radius: 5, x: 0, y: 0)
                }
            }
        }
        .frame(height: height)
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
                
                // 发光细青色进度条
                if case .downloading = item.status {
                    VStack(spacing: 4) {
                        GlowingProgressBar(progress: item.progress, height: 3.5)
                        HStack {
                            Text("\(Int(item.progress * 100))%").font(.system(size: 10, weight: .bold)).foregroundColor(.cyan)
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

// MARK: - 9. 方案 A 转换任务卡片 (TranscodeJobCardView)
struct TranscodeJobCardView: View {
    @ObservedObject var viewModel: DownloadViewModel
    @ObservedObject var job: TranscodeJob
    
    var body: some View {
        VStack(spacing: 7) {
            // 顶行：左侧格式小标 + 文件名流向 + 右侧实时状态/FPS/解密徽章 + 删除按钮
            HStack(spacing: 10) {
                // 左侧格式徽标小图标 (如效果图中的 MOV / CD / MKV)
                leadingFormatIcon
                
                // 文件名 ➔ 目标格式
                HStack(spacing: 6) {
                    Text(job.fileName)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Text(job.targetSummary)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Color.cyan)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // 右侧指标与状态
                trailingStatusAndMetrics
                
                // 移除/取消按钮
                Button {
                    viewModel.removeConvertJob(job: job)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
            
            // 发光细青色进度条线 (贯穿卡片宽度，如效果图)
            GlowingProgressBar(progress: job.state == .completed ? 1.0 : job.progress)
            
            // 底部辅助信息条 (分辨率、时长、直拷说明、完成后的预览与定位)
            if job.state == .completed, let outURL = job.outputURL {
                HStack(spacing: 12) {
                    Text(job.durationLabel).font(.system(size: 11)).foregroundColor(.secondary)
                    Spacer()
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
            } else if job.state == .ready || job.state == .pending {
                HStack(spacing: 10) {
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
                        .padding(.vertical, 3.5)
                        .background(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var leadingFormatIcon: some View {
        if job.isEncryptedSource {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.85))
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.cyan)
                    .offset(x: 2, y: 2)
            }
            .frame(width: 26, height: 26)
        } else if job.mediaInfo?.video == nil && job.mediaInfo?.audio != nil {
            Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundColor(.cyan)
                .frame(width: 26, height: 26)
        } else {
            // 视频文档标签 (MOV, MKV, MP4 等)
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 26, height: 26)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    .frame(width: 26, height: 26)
                
                VStack(spacing: 0) {
                    Image(systemName: "film")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.8))
                    Text(job.sourceFormatLabel.prefix(4))
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundColor(.cyan)
                }
            }
        }
    }
    
    @ViewBuilder
    private var trailingStatusAndMetrics: some View {
        if job.state == .running {
            HStack(spacing: 6) {
                Text("\(Int(job.progress * 100))%").font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
                if job.fps > 0 {
                    Text("\(Int(job.fps)) FPS").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                }
                if job.isHardwareAccelerated {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundColor(.yellow)
                        Text("VideoToolbox").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
        } else if job.isEncryptedSource && job.state == .completed {
            HStack(spacing: 6) {
                Text("100%").font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
                Text("✓ 已秒级解锁 (Lossless FLAC)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 0.2, green: 0.95, blue: 0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.2)))
                    .overlay(Capsule().stroke(Color.green.opacity(0.6), lineWidth: 1))
                    .shadow(color: Color.green.opacity(0.4), radius: 4)
            }
        } else if job.state == .completed {
            HStack(spacing: 6) {
                Text("100%").font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
                Text("✓ 转换完成")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
            }
        } else if job.isDirectCopy {
            HStack(spacing: 4) {
                Image(systemName: "shuffle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        } else if job.state == .decrypting {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("解密中...").font(.system(size: 11)).foregroundColor(.purple)
            }
        } else if job.state == .analyzing {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("分析中...").font(.system(size: 11)).foregroundColor(.cyan)
            }
        } else if job.state == .failed {
            Text(job.errorMessage ?? "失败").font(.system(size: 10)).foregroundColor(.red).lineLimit(1)
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
            
            Picker("浏览器登录态 Cookie", selection: $viewModel.browserCookieSource) {
                ForEach(BrowserCookieSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .help("导入浏览器已登录 Cookie，可解锁 B站大会员 1080P60/4K 原画及 YouTube 私享视频")
            
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
            
            Toggle("任务完成发送 macOS 系统通知", isOn: $viewModel.enableSystemNotifications)
            
            HStack {
                Text("系统依赖状态:")
                Spacer()
                Text(viewModel.environmentStatus.isReady ? "已就绪" : "缺失依赖")
                    .foregroundColor(viewModel.environmentStatus.isReady ? .green : .red)
            }
        }
    }
}
