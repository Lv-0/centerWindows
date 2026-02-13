# CenterWindow（macOS 窗口自动居中工具）

一个菜单栏常驻的 macOS 窗口管理工具：在应用启动时将前台窗口居中到当前屏幕可用区域（避开 Dock / 菜单栏）。

## 功能

- 启动即居中：应用打开时自动执行一次窗口居中。
- 手动居中：菜单栏点击“立即将前台窗口居中”。
- 权限引导：首次启动会触发屏幕录制权限和辅助功能权限请求。
- 多屏支持：按窗口当前所在屏幕计算居中坐标。
- 精确避让：通过 `screen.frame - screen.visibleFrame` 计算 Dock 与状态栏占用像素，再在剩余区域居中。

## 系统要求

- macOS 13 或更高版本
- Xcode Command Line Tools（`xcode-select --install`）
- 正式分发需 Apple Developer Program 账号（Developer ID）

## 本地构建与运行

```bash
swift test
swift build -c release
./.build/release/CenterWindow
```

## 生成可安装 `.app` 与 `.dmg`

```bash
scripts/build_app.sh
scripts/create_dmg.sh
```

说明：

- `scripts/build_app.sh` 每次都会重新绘制应用图标与状态栏图标，并重建 `.app`。
- 执行 `scripts/create_dmg.sh` 会基于最新 `.app` 重新生成 `.dmg`。

输出文件：

- `dist/CenterWindow.app`
- `dist/CenterWindow.dmg`

## 签名 + 公证（Developer ID 正式分发）

### 1) 前置：准备证书

在 Keychain 中安装你的 `Developer ID Application` 证书（Apple Developer 账号签发）。

用下面命令确认可用身份：

```bash
security find-identity -v -p codesigning
```

### 2) 前置：配置 notarytool 凭据

建议先保存一个 Keychain profile（只做一次）：

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

### 3) 执行签名与公证

```bash
export DEVELOPER_ID_APP="Developer ID Application: YOUR_NAME (TEAMID)"
export NOTARY_PROFILE="AC_NOTARY"
scripts/sign_and_notarize.sh
```

该脚本会依次执行：

1. 对 `.app` 进行 hardened runtime 签名
2. 验证 `.app` 签名
3. 对 `.dmg` 签名
4. 提交 Apple Notary
5. stapler 回填票据
6. Gatekeeper 验证

## 最终安装验证

```bash
spctl --assess --type open --verbose=4 dist/CenterWindow.dmg
```

然后双击 `dist/CenterWindow.dmg`，拖入 `Applications` 安装。

## 辅助功能权限说明（必须）

本软件通过 macOS Accessibility API 调整窗口位置，必须授予：

- `系统设置 -> 隐私与安全性 -> 辅助功能`

如果未授权，软件无法获取/设置窗口坐标。

另外首次启动会请求“屏幕录制”权限，用于获取完整屏幕可见区域上下文：

- `系统设置 -> 隐私与安全性 -> 屏幕录制`
