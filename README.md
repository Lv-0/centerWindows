# centerWindows

[English](./README.en.md) | 简体中文

`centerWindows` 是一个 macOS 菜单栏窗口管理工具：应用启动后立即将前台窗口居中，并支持自动检测居中（可开关、可调间隔）。

## 功能

- 启动立即居中一次
- 自动居中检测开关（菜单勾选）
- 检测间隔切换（1s / 2s / 5s）
- 排除 Dock 与状态栏后居中（基于 `screen.frame - screen.visibleFrame`）
- 菜单栏图标与应用图标自动生成

## 系统要求

- macOS 13+
- Xcode Command Line Tools（`xcode-select --install`）

## 本地构建

```bash
swift test
swift build -c release
./.build/release/centerWindows
```

## 打包

```bash
scripts/build_app.sh
scripts/create_dmg.sh
```

输出：

- `dist/centerWindows.app`
- `dist/centerWindows.dmg`

DMG 打开后会包含两个项目：

- `centerWindows.app`
- `Applications`（系统应用目录快捷方式）

安装方式：将 `centerWindows.app` 拖到 `Applications`。

## 签名与公证（Developer ID）

```bash
export DEVELOPER_ID_APP="Developer ID Application: YOUR_NAME (TEAMID)"
export NOTARY_PROFILE="AC_NOTARY"
scripts/sign_and_notarize.sh
```

## 安装说明
1. 打开 DMG，将 `centerWindows.app` 拖到 `Applications`。
2. 到 `Applications` 中右键 `centerWindows.app` -> `打开` -> 再次点击 `打开`。
3. 若仍被拦截：`系统设置 -> 隐私与安全性` 页面底部点击“仍要打开”。
4. 若仍失败，可在终端执行：

```bash
xattr -dr com.apple.quarantine /Applications/centerWindows.app
```

注意：这是非公证分发的常见安装流程，不是应用自身代码损坏。

## 权限

### 辅助功能（Accessibility）

- 路径：`系统设置 -> 隐私与安全性 -> 辅助功能`
- 为什么需要：  
  应用通过 macOS Accessibility API 读取前台窗口的位置/尺寸，并写入新位置来执行“窗口居中”。
- 不授权会怎样：  
  无法获取窗口几何信息，也无法移动窗口，居中功能不可用。

### 屏幕录制（Screen Recording）

- 路径：`系统设置 -> 隐私与安全性 -> 屏幕录制`
- 为什么需要：  
  需要获取完整屏幕可见区域上下文，以便正确识别可用显示区域并精确避开 Dock/状态栏进行居中。
- 不授权会怎样：  
  屏幕上下文能力受限，可能导致多屏或复杂布局下的居中判断不稳定。

### 权限边界说明

- 本项目不会上传屏幕内容，不会进行网络采集。
- 权限仅用于本地窗口几何计算与窗口位置调整。

## 开源协议

MIT License，见 [LICENSE](./LICENSE)。
