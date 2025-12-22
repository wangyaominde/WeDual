# WeDual - macOS 微信双开工具

WeDual 是一个简单的 Shell 脚本，旨在帮助 macOS 用户轻松实现微信双开（同时登录两个微信账号）。

## 🚀 功能特点

- **一键启动**：自动检测环境，一键开启第二个微信实例。
- **独立运行**：通过复制并修改应用 Bundle ID，使第二个微信作为独立应用运行，互不干扰。
- **自动配置**：首次运行时自动完成应用复制、配置修改和重签名工作。

## 📋 前置要求

- macOS 操作系统
- 已安装官方 [微信 for Mac](https://mac.weixin.qq.com/) (默认路径为 `/Applications/WeChat.app`)
- 需要管理员权限（sudo）以复制和修改应用程序。
- 建议安装 Xcode Command Line Tools（用于应用重签名），通常 macOS 自带或会自动提示安装。

## 🛠 使用方法

1. **下载脚本**
   下载本项目到本地目录。

2. **赋予执行权限**
   在终端中进入脚本所在目录，并运行以下命令赋予脚本执行权限：
   ```bash
   chmod +x wechat_dou.sh
   ```

3. **运行脚本**
   直接运行脚本即可：
   ```bash
   ./wechat_dou.sh
   ```

   > **首次运行提示**：
   > 首次运行时，脚本需要复制微信应用并进行签名，会提示输入开机密码以获取 `sudo` 权限。请耐心等待“环境初始化成功”的提示。

4. **日常使用**
   - 正常打开第一个微信。
   - 运行此脚本打开第二个微信。

## ⚠️ 注意事项

- **安全性**：脚本仅进行本地文件复制和 Info.plist 修改，不包含任何恶意代码。
- **版本更新**：如果微信官方发布了更新，建议删除 `/Applications/WeChat2.app` 并重新运行此脚本以生成最新版本的双开应用。
- **卸载**：如果不再需要双开，只需删除 `/Applications/WeChat2.app` 即可：
  ```bash
  sudo rm -rf /Applications/WeChat2.app
  ```

## 📝 实现原理

1. 复制 `/Applications/WeChat.app` 到 `/Applications/WeChat2.app`。
2. 修改副本的 `CFBundleIdentifier` 为 `com.tencent.xinWeChat2`，防止系统将其识别为同一应用。
3. 对副本进行 Ad-hoc 重签名以通过 macOS 的安全检查。
4. 以后台模式启动修改后的微信实例。

---
*Disclaimer: 本工具仅供学习交流使用，请勿用于非法用途。*
