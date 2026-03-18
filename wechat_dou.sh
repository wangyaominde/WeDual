#!/bin/bash

# 配置路径
ORIGINAL_APP="/Applications/WeChat.app"
DUAL_APP="/Applications/WeChat2.app"
BUNDLE_ID="com.tencent.xinWeChat2"
DATA_DIR="$HOME/Library/Containers/$BUNDLE_ID"

echo "------------------------------------------------"
echo "微信 macOS 一键双开工具 (v2 - 支持更新)"
echo "------------------------------------------------"

# 检查原始微信是否存在
if [ ! -d "$ORIGINAL_APP" ]; then
    echo "❌ 错误：未在 /Applications 中找到原始微信应用。"
    exit 1
fi

# 获取版本号
get_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null || echo "未知"
}

# 比较版本号，返回 0 表示 $1 > $2
version_gt() {
    [ "$(printf '%s\n%s' "$1" "$2" | sort -V | tail -1)" != "$2" ]
}

ORIGINAL_VER=$(get_version "$ORIGINAL_APP")
DUAL_VER=$(get_version "$DUAL_APP")

echo "原版微信版本: $ORIGINAL_VER"

# 判断是否需要更新或首次安装
NEED_INSTALL=false

if [ ! -d "$DUAL_APP" ]; then
    echo "首次运行，正在初始化双开环境..."
    NEED_INSTALL=true
elif version_gt "$ORIGINAL_VER" "$DUAL_VER"; then
    echo "⚠️  检测到新版本！微信2版本: $DUAL_VER → 需要更新到: $ORIGINAL_VER"
    echo ""
    echo "📦 你的聊天记录保存在:"
    echo "   $DATA_DIR"
    echo "   更新应用包不会影响聊天记录，放心！"
    echo ""
    NEED_INSTALL=true
elif [ "$ORIGINAL_VER" != "$DUAL_VER" ]; then
    echo "⚠️  版本不一致：微信2版本($DUAL_VER) 高于原版微信($ORIGINAL_VER)，跳过降级。"
else
    echo "微信2版本: $DUAL_VER（已是最新，无需更新）"
fi

if [ "$NEED_INSTALL" = true ]; then
    # 1. 删除旧应用包（数据在 Containers 中，不受影响）
    if [ -d "$DUAL_APP" ]; then
        echo ">> 正在移除旧版应用包..."
        sudo rm -rf "$DUAL_APP"
    fi

    # 2. 复制新版应用
    echo ">> 正在复制新版微信（可能需要输入开机密码）..."
    sudo cp -R "$ORIGINAL_APP" "$DUAL_APP"

    # 3. 修改 Bundle ID（保持与数据目录一致）
    echo ">> 正在修改 Bundle ID..."
    sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$DUAL_APP/Contents/Info.plist"

    # 4. 同时修改内嵌的 Info.plist（部分版本微信有多层签名检查）
    HELPER_PLIST="$DUAL_APP/Contents/Resources/Info.plist"
    if [ -f "$HELPER_PLIST" ]; then
        sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$HELPER_PLIST" 2>/dev/null
    fi

    # 5. 移除签名验证相关文件（防止新版微信加强校验导致闪退）
    echo ">> 正在处理签名..."
    sudo rm -rf "$DUAL_APP/Contents/_CodeSignature"
    sudo rm -rf "$DUAL_APP/Contents/MacOS/"*.sig 2>/dev/null

    # 6. 重新签名
    sudo codesign --force --deep --sign - "$DUAL_APP"

    if [ $? -eq 0 ]; then
        echo "✅ 更新完成！版本: $ORIGINAL_VER"
    else
        echo "❌ 签名失败，请确保已安装 Xcode 命令行工具："
        echo "   运行: xcode-select --install"
        exit 1
    fi
else
    echo "✅ 双开环境已就绪。"
fi

# 启动第二个微信
echo ">> 正在启动第二个微信..."
nohup "$DUAL_APP/Contents/MacOS/WeChat" >/dev/null 2>&1 &

echo "------------------------------------------------"
echo "🚀 第二个微信已在后台启动。"
echo "请确保你已经手动打开了第一个微信。"
echo "------------------------------------------------"
