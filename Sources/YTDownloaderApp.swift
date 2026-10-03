import SwiftUI
import AppKit
import UserNotifications

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

/// 适配器：实现无边框沉浸式窗口、半透明毛玻璃底色、全窗口背景可拖拽移动、系统通知代理与进程生命周期管理
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 请求 macOS 系统通知权限并设置前台展示代理
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
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
    
    // 应用前台运行也支持弹出通知横幅
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    // 点击通知横幅直接在 Finder 中高亮定位文件
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["filePath"] as? String {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        completionHandler()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 彻底终止所有进行中的子进程，防止孤儿进程占用系统资源
        DownloadViewModel.shared?.cleanupOnTerminate()
    }
}
