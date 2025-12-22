#!/bin/bash

# 配置路径
ORIGINAL_APP="/Applications/WeChat.app"
DUAL_APP="/Applications/WeChat2.app"
BUNDLE_ID="com.tencent.xinWeChat2"

echo "------------------------------------------------"
echo "微信 macOS 一键双开工具"
echo "------------------------------------------------"

# 检查原始微信是否存在
if [ ! -d "$ORIGINAL_APP" ]; then
    echo "❌ 错误：未在 /Applications 中找到原始微信应用。"
    exit 1
fi

# 检测是否为首次运行（判断 WeChat2 是否存在）
if [ ! -d "$DUAL_APP" ]; then
    echo "首次运行，正在初始化双开环境..."
    
    # 1. 复制应用
    echo ">> 正在复制应用（可能需要输入开机密码）..."
    sudo cp -R "$ORIGINAL_APP" "$DUAL_APP"
    
    # 2. 修改 Bundle ID 防止冲突
    echo ">> 正在修改 Bundle ID..."
    sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$DUAL_APP/Contents/Info.plist"
    
    # 3. 重新签名
    echo ">> 正在重新签名（请稍候）..."
    sudo codesign --force --deep --sign - "$DUAL_APP"
    
    if [ $? -eq 0 ]; then
        echo "✅ 环境初始化成功！"
    else
        echo "❌ 签名失败，请检查是否安装了 Xcode 命令行工具。"
        exit 1
    fi
else
    echo "检测到双开环境已就绪。"
fi

# 启动第二个微信
echo ">> 正在启动第二个微信..."
nohup "$DUAL_APP/Contents/MacOS/WeChat" >/dev/null 2>&1 &

echo "------------------------------------------------"
echo "🚀 第二个微信已在后台启动。"
echo "请确保你已经手动打开了第一个微信。"
echo "------------------------------------------------"
