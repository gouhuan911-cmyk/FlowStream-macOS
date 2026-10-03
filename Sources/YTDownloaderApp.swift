import SwiftUI
import AppKit

@main
struct FlowStreamDLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, idealWidth: 860, maxWidth: 1050, minHeight: 600, idealHeight: 660)
                .background(.ultraThinMaterial)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

/// 适配器：实现无边框沉浸式窗口、半透明毛玻璃底色以及全窗口背景可拖拽移动
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            // 设置窗口中文标题
            window.title = "流光下载"
            
            // 设置窗口半透明毛玻璃
            window.isOpaque = false
            window.backgroundColor = .clear
            
            // 启用背景全域拖拽移动
            window.isMovableByWindowBackground = true
            
            // 交通灯沉浸式融合
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
