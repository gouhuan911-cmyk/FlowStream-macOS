#!/bin/bash
set -e

# ==============================================================================
# 流光下载 (FlowStream DL) - macOS 一键构建与打包脚本
# ==============================================================================

echo "🌊 开始构建 流光下载 (FlowStream DL)..."

# 1. 检查基础编译工具
if ! command -v swiftc &> /dev/null; then
    echo "❌ 错误: 未找到 swiftc 编译器。请先安装 Xcode Command Line Tools (运行: xcode-select --install)。"
    exit 1
fi

SDK_PATH=$(xcrun --show-sdk-path)
ARCH=$(uname -m)
APP_NAME="FlowStreamDL"
APP_BUNDLE="${APP_NAME}.app"
OUTPUT_DIR="build"

echo "📍 检测到架构: ${ARCH}, SDK 路径: ${SDK_PATH}"

# 2. 准备 App Bundle 目录结构
rm -rf "${APP_BUNDLE}" "${OUTPUT_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 3. 复制应用图标
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# 4. 生成 Info.plist
cat << 'EOF' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>FlowStreamDL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.flowstream.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>流光下载</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# 5. 编译 Swift 源码
echo "⚡️ 正在编译 Swift 源代码 (优化级别: -O)..."
swiftc -O -whole-module-optimization \
    -target "${ARCH}-apple-macos13.0" \
    -sdk "${SDK_PATH}" \
    Sources/*.swift \
    -o "${APP_BUNDLE}/Contents/MacOS/FlowStreamDL"

# 6. 代码签名
echo "🔏 正在进行本地代码签名..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "🎉 构建成功! 生成的应用位于: ./${APP_BUNDLE}"
echo "👉 双击 ./${APP_BUNDLE} 即可启动使用！"
