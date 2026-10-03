#!/bin/bash
set -e

# ==============================================================================
# 流光下载 (FlowStream DL) - macOS DMG 与 发布包打包脚本
# ==============================================================================

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="2.2.0"
APP_NAME="流光下载"
APP_BUNDLE="${ROOT}/FlowStreamDL.app"
VOL_NAME="流光下载 v${VERSION}"
DMG_NAME="FlowStreamDL-v${VERSION}-macOS.dmg"
ZIP_NAME="FlowStreamDL-v${VERSION}-macOS.zip"
OUTPUT_DIR="${ROOT}/build"
STAGING="${OUTPUT_DIR}/dmg-staging"
TMP_DMG="${OUTPUT_DIR}/.tmp.dmg"
FINAL_DMG="${ROOT}/${DMG_NAME}"
FINAL_ZIP="${ROOT}/${ZIP_NAME}"

echo "📦 开始打包 流光下载 v${VERSION}..."

# 1. 检查或构建 app
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "⚡️ 未找到编译完成的 App Bundle，正在执行构建..."
    "${ROOT}/build.sh"
fi

mkdir -p "${OUTPUT_DIR}"
rm -rf "${STAGING}" "${TMP_DMG}" "${FINAL_DMG}" "${FINAL_ZIP}"
mkdir -p "${STAGING}"

# 2. 复制并重命名应用为中文友好名称
echo "📂 准备 DMG 安装目录..."
cp -R "${APP_BUNDLE}" "${STAGING}/${APP_NAME}.app"
ln -s /Applications "${STAGING}/Applications"

# 3. 创建 DMG
echo "💿 正在生成 DMG 镜像: ${DMG_NAME}..."
hdiutil create -srcfolder "${STAGING}" -volname "${VOL_NAME}" -fs HFS+ \
    -format UDZO -imagekey zlib-level=9 "${FINAL_DMG}"

# 4. 创建 ZIP 归档
echo "🗜️ 正在生成 ZIP 压缩包: ${ZIP_NAME}..."
cd "${STAGING}"
zip -r -y "${FINAL_ZIP}" "${APP_NAME}.app"
cd "${ROOT}"

# 5. 清理中间文件
rm -rf "${STAGING}" "${TMP_DMG}"

echo "🎉 打包完成!"
echo "📍 DMG 文件: ${FINAL_DMG}"
echo "📍 ZIP 文件: ${FINAL_ZIP}"
