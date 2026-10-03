import Foundation
import AppKit
import QuickLookUI

/// 深度集成 macOS 原生系统级 QuickLook 空格预览控制器
public final class QuickLookHelper: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = QuickLookHelper()
    
    public var currentPreviewURL: URL?
    
    private override init() {
        super.init()
    }
    
    /// 唤起 macOS 原生半透明 QuickLook 浮窗播放预览
    public func preview(fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
            return
        }
        
        self.currentPreviewURL = fileURL
        
        DispatchQueue.main.async {
            if let panel = QLPreviewPanel.shared() {
                panel.dataSource = self
                panel.delegate = self
                panel.makeKeyAndOrderFront(nil)
                panel.reloadData()
            }
        }
    }
    
    // MARK: - QLPreviewPanelDataSource
    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return currentPreviewURL != nil ? 1 : 0
    }
    
    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard let url = currentPreviewURL else {
            return URL(fileURLWithPath: "") as QLPreviewItem
        }
        return url as QLPreviewItem
    }
}
