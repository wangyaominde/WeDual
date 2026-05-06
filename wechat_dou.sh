#!/bin/bash

# 配置路径
ORIGINAL_APP="/Applications/WeChat.app"
DUAL_APP="/Applications/WeChat2.app"
BUNDLE_ID="com.tencent.xinWeChat2"
DATA_DIR="$HOME/Library/Containers/$BUNDLE_ID"
TMP_ENT="/tmp/wedual_entitlements.plist"

FORCE_REBUILD=false
# 4.1.x 起，开启 app-sandbox 但 entitlements 里没有合法 team-prefixed
# application-groups 时，WeChatAppEx 内部 CHECK 会失败 SIGTRAP。
# 默认去掉 app-sandbox；--with-sandbox 可强制启用做调试。
NO_SANDBOX=true
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE_REBUILD=true ;;
        --no-sandbox) NO_SANDBOX=true ;;
        --with-sandbox) NO_SANDBOX=false ;;
    esac
done

echo "------------------------------------------------"
echo "微信 macOS 一键双开工具 (v3 - 适配 4.1.x 沙盒)"
echo "------------------------------------------------"

# 检查原始微信是否存在
if [ ! -d "$ORIGINAL_APP" ]; then
    echo "❌ 错误：未在 /Applications 中找到原始微信应用。"
    exit 1
fi

# 预先获取 sudo 权限，避免后续静默失败
echo ">> 需要管理员权限来修改 /Applications，请输入开机密码："
if ! sudo -v; then
    echo "❌ 无法获取 sudo 权限，已中止。"
    exit 1
fi
# 后台保活，避免长时间签名过程中 sudo 超时
( while true; do sudo -n true 2>/dev/null; sleep 30; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

# 获取版本号
get_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null || echo "未知"
}

# 比较版本号 (返回 0 表示 $1 < $2)
version_lt() {
    [ "$1" = "$2" ] && return 1
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

# 校验 WeChat2.app 是否处于"已正确改过"的状态
is_dual_app_valid() {
    [ -d "$DUAL_APP" ] || return 1
    local id sig_id helper_id helper_inherit
    id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$DUAL_APP/Contents/Info.plist" 2>/dev/null)
    [ "$id" = "$BUNDLE_ID" ] || return 1
    sig_id=$(codesign -d --verbose=2 "$DUAL_APP" 2>&1 | awk -F= '/^Identifier=/{print $2}')
    [ "$sig_id" = "$BUNDLE_ID" ] || return 1
    # Helper 必须保持原 Bundle ID，且 entitlements 里要有 inherit
    if [ -d "$DUAL_APP/Contents/MacOS/WeChatAppEx.app" ]; then
        helper_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
            "$DUAL_APP/Contents/MacOS/WeChatAppEx.app/Contents/Info.plist" 2>/dev/null)
        [ "$helper_id" = "com.tencent.flue.WeChatAppEx" ] || return 1
        helper_inherit=$(codesign -d --entitlements :- \
            "$DUAL_APP/Contents/MacOS/WeChatAppEx.app" 2>/dev/null \
            | grep -c "com.apple.security.inherit")
        [ "$helper_inherit" -gt 0 ] || return 1
    fi
    return 0
}

ORIGINAL_VER=$(get_version "$ORIGINAL_APP")
DUAL_VER=$(get_version "$DUAL_APP")

echo "原版微信版本: $ORIGINAL_VER"

# 判断是否需要重建
NEED_INSTALL=false

if [ "$FORCE_REBUILD" = true ]; then
    echo "🔧 --force 已指定，强制重建。"
    NEED_INSTALL=true
elif [ ! -d "$DUAL_APP" ]; then
    echo "首次运行，正在初始化双开环境..."
    NEED_INSTALL=true
elif ! is_dual_app_valid; then
    echo "⚠️  检测到 WeChat2.app 状态异常（Bundle ID 或签名不正确），将重建。"
    NEED_INSTALL=true
elif [ "$ORIGINAL_VER" != "$DUAL_VER" ]; then
    if version_lt "$ORIGINAL_VER" "$DUAL_VER"; then
        echo "ℹ️  原版($ORIGINAL_VER) 比 微信2($DUAL_VER) 旧，跳过同步以防降级。"
    else
        echo "⚠️  版本不一致！微信2版本: $DUAL_VER → 同步到原版: $ORIGINAL_VER"
        echo ""
        echo "📦 你的聊天记录保存在:"
        echo "   $DATA_DIR"
        echo "   更新应用包不会影响聊天记录，放心！"
        echo ""
        NEED_INSTALL=true
    fi
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

    # 3. 修改主 Bundle ID
    echo ">> 正在修改 Bundle ID..."
    sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$DUAL_APP/Contents/Info.plist"

    # 4. 修改内嵌扩展的 Bundle ID，避免与原版冲突
    for ext_path in "$DUAL_APP"/Contents/PlugIns/*.appex; do
        [ -d "$ext_path" ] || continue
        ext_name=$(basename "$ext_path" .appex)
        sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}.${ext_name}" \
            "$ext_path/Contents/Info.plist" 2>/dev/null
    done

    # 5. 不要修改 WeChatAppEx.app 的 Bundle ID
    # (原版是 com.tencent.flue.WeChatAppEx，与内部 framework com.tencent.flue.framework 配对，
    #  framework 内部会自检该 ID，改了必崩。Helper 由主程序按路径直接拉起，不走 LaunchServices，
    #  保留原 ID 不会与原版微信冲突。)
    HELPER_APP="$DUAL_APP/Contents/MacOS/WeChatAppEx.app"

    # 6. 抽取原版 entitlements 并清理掉绑定 Team ID 的项
    echo ">> 正在生成 entitlements..."
    codesign -d --entitlements :- "$ORIGINAL_APP" > "$TMP_ENT" 2>/dev/null

    if [ ! -s "$TMP_ENT" ]; then
        echo "❌ 抽取 entitlements 失败。"
        exit 1
    fi

    # 这几个键带 Team ID，ad-hoc 签名无法保留，必须删除
    /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$TMP_ENT" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$TMP_ENT" 2>/dev/null
    # application-groups 完全删除会让 WeChat 的共享容器访问 CHECK 失败 → SIGTRAP 闪退。
    # 保留一个不带 Team 前缀的同名分组，让进程内的容器路径查询走通。
    /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$TMP_ENT" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" "$TMP_ENT" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups:0 string $BUNDLE_ID" "$TMP_ENT" 2>/dev/null

    # --no-sandbox: 完全去掉 app-sandbox（fallback 方案，
    # 数据目录会从 ~/Library/Containers/ 变成 ~/Library/Application Support/）
    if [ "$NO_SANDBOX" = true ]; then
        echo "⚠️  --no-sandbox 模式：移除 app-sandbox entitlement"
        /usr/libexec/PlistBuddy -c "Delete :com.apple.security.app-sandbox" "$TMP_ENT" 2>/dev/null
        /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$TMP_ENT" 2>/dev/null
    fi

    # 7. 清理旧签名与商店收据
    echo ">> 正在清理旧签名..."
    sudo rm -rf "$DUAL_APP/Contents/_CodeSignature"
    sudo rm -rf "$DUAL_APP/Contents/_MASReceipt"
    sudo find "$DUAL_APP/Contents/MacOS" -name "*.sig" -delete 2>/dev/null

    # 8. 由内向外重签：先 Frameworks → 扩展 → Helper → 主体
    echo ">> 正在重签 Frameworks..."
    if [ -d "$DUAL_APP/Contents/Frameworks" ]; then
        # framework 目录
        find "$DUAL_APP/Contents/Frameworks" -maxdepth 1 -type d -name "*.framework" | while read -r fw; do
            sudo codesign --force --sign - "$fw" 2>/dev/null
        done
        # dylib / 独立可执行
        find "$DUAL_APP/Contents/Frameworks" -maxdepth 1 -type f | while read -r f; do
            sudo codesign --force --sign - "$f" 2>/dev/null
        done
    fi

    echo ">> 正在重签扩展(.appex)..."
    for ext_path in "$DUAL_APP"/Contents/PlugIns/*.appex; do
        [ -d "$ext_path" ] || continue
        # 扩展用各自的 entitlements，但同样剥掉 team-tied keys
        EXT_ENT="/tmp/wedual_ext_$(basename "$ext_path").plist"
        codesign -d --entitlements :- "$ext_path" > "$EXT_ENT" 2>/dev/null
        if [ -s "$EXT_ENT" ]; then
            /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$EXT_ENT" 2>/dev/null
            /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$EXT_ENT" 2>/dev/null
            /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$EXT_ENT" 2>/dev/null
            sudo codesign --force --sign - --entitlements "$EXT_ENT" "$ext_path"
        else
            sudo codesign --force --sign - "$ext_path"
        fi
        rm -f "$EXT_ENT"
    done

    if [ -d "$HELPER_APP" ]; then
        echo ">> 正在重签 Helper(WeChatAppEx)..."

        # 先重签 Helper 内嵌的 frameworks（不要带 entitlements）
        if [ -d "$HELPER_APP/Contents/Frameworks" ]; then
            find "$HELPER_APP/Contents/Frameworks" -type d -name "*.framework" | sort -r | while read -r fw; do
                sudo codesign --force --sign - "$fw" 2>/dev/null
            done
            find "$HELPER_APP/Contents/Frameworks" -type f \
                \( -name "*.dylib" -o -perm +111 \) 2>/dev/null | while read -r f; do
                sudo codesign --force --sign - "$f" 2>/dev/null
            done
        fi

        # 用 Helper 自己的 entitlements（保留 com.apple.security.inherit）重签
        HELPER_ENT="/tmp/wedual_helper_ent.plist"
        codesign -d --entitlements :- "$ORIGINAL_APP/Contents/MacOS/WeChatAppEx.app" > "$HELPER_ENT" 2>/dev/null
        if [ -s "$HELPER_ENT" ]; then
            /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$HELPER_ENT" 2>/dev/null
            /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$HELPER_ENT" 2>/dev/null
            /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$HELPER_ENT" 2>/dev/null
            sudo codesign --force --sign - --entitlements "$HELPER_ENT" "$HELPER_APP"
        else
            sudo codesign --force --sign - "$HELPER_APP"
        fi
        rm -f "$HELPER_ENT"
    fi

    echo ">> 正在重签主程序..."
    if ! sudo codesign --force --sign - --entitlements "$TMP_ENT" "$DUAL_APP"; then
        echo "❌ 主程序签名失败，已中止。"
        exit 1
    fi

    # 9. 验证 Bundle ID 是否真的改成功（最关键的成功标志）
    NEW_SIG_ID=$(codesign -d --verbose=2 "$DUAL_APP" 2>&1 | awk -F= '/^Identifier=/{print $2}')
    if [ "$NEW_SIG_ID" = "$BUNDLE_ID" ]; then
        echo "✅ 重建完成！版本: $ORIGINAL_VER, 签名 ID: $NEW_SIG_ID"
    else
        echo "❌ 重建后签名 ID 仍为 \"$NEW_SIG_ID\"（应为 $BUNDLE_ID），可能启动失败。"
        exit 1
    fi

    rm -f "$TMP_ENT"
else
    echo "✅ 双开环境已就绪。"
fi

# 先关闭所有微信进程，确保干净启动
echo ">> 正在关闭所有微信进程..."
killall WeChat 2>/dev/null
sleep 1

# 先启动原版微信
echo ">> 正在启动第一个微信（原版）..."
open "$ORIGINAL_APP"

# 等待原版微信完全启动
echo ">> 等待第一个微信就绪..."
for i in $(seq 1 15); do
    if pgrep -f "$ORIGINAL_APP/Contents/MacOS/WeChat" >/dev/null 2>&1; then
        echo "✅ 第一个微信已启动。"
        break
    fi
    sleep 1
done

sleep 2

# 再启动第二个微信
echo ">> 正在启动第二个微信..."
nohup "$DUAL_APP/Contents/MacOS/WeChat" >/dev/null 2>&1 &

echo "------------------------------------------------"
echo "🚀 双开完成！两个微信都已启动。"
echo "------------------------------------------------"
