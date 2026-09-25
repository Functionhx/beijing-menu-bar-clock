<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/banner-dark.svg">
    <img alt="北京时间 · Beijing Menu Bar Clock" src="docs/assets/banner-light.svg" width="100%">
  </picture>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-AppKit%20%2B%20SwiftUI-F05138?logo=swift&logoColor=white">
  <img alt="Network: update checks only" src="https://img.shields.io/badge/network-update%20checks%20only-16a34a">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue">
</p>

<p align="center">
  <b>中文</b> · <a href="#english">English</a>
</p>

> [!NOTE]
> **这是 Nano 极简版（`nano` 分支）**，应用名“北京时间 Nano”，可与完整版同时安装。只保留菜单栏时钟和一个小面板：日期 / 星期 / 秒 / 闪动开关、时区搜索、检查更新、退出。
> 省略了：App 时区白名单与自动接管、语音报时、设置窗口、右键菜单。下文的功能介绍描述的是完整版。
>
> **This is the Nano edition (`nano` branch)**: just the menu bar clock and a small panel with date / weekday / seconds / blinking toggles, time zone search, update check and quit. It omits the per-app time zone whitelist and auto-takeover, voice announcements, the settings window and the right-click menu. The feature descriptions below refer to the full edition.

---

**北京时间**是一个原生 macOS 菜单栏时钟：人在海外、系统时区不用动，菜单栏里始终显示北京时间。它还能让微信、QQ 这类指定 App 按北京时区启动，聊天记录和日程里的时间不再需要心算换算。

<p align="center">
  <img alt="菜单栏效果" src="docs/assets/menubar.png" width="460">
</p>

## ✨ 亮点

<table>
<tr><td width="160">🕗 <b>不动系统时区</b></td><td>系统保持当地时间，菜单栏单独显示北京时间（或任意时区）。</td></tr>
<tr><td>🧭 <b>App 级时区</b></td><td>把微信、QQ、备忘录等加入白名单，一键按指定时区重新打开，并实时显示是否已生效。</td></tr>
<tr><td>⚡ <b>自动接管</b></td><td>可选：从 Dock 或访达正常打开的白名单 App，会被自动切换到指定时区。基于系统事件，不轮询。</td></tr>
<tr><td>🔔 <b>整点报时</b></td><td>每小时、每半小时或每刻钟语音报时，可选系统提示音或自定义声音。</td></tr>
<tr><td>🔋 <b>低功耗</b></td><td>原生 AppKit 实现，实测稳定运行时平均不到 1 mW，与常见菜单栏小工具同一量级。</td></tr>
<tr><td>🔒 <b>隐私</b></td><td>只在检查更新时访问 GitHub，不定位、不收集任何数据，没有 Dock 图标。</td></tr>
</table>

## 🖼 设置界面

<p align="center">
  <img alt="时钟选项" src="docs/assets/settings.png" width="620">
</p>

## 🚀 安装

需要 macOS 14 或更高版本、Xcode，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。首次编译会自动下载 Sparkle 更新框架。

```bash
git clone https://github.com/Functionhx/beijing-menu-bar-clock.git
cd beijing-menu-bar-clock
./install.sh
```

安装脚本会编译 App、放到 `~/Applications`，并设置为开机自动启动。

如果菜单栏里没出现时钟，打开 **系统设置 → 菜单栏 → 允许在菜单栏中显示**，打开 **北京时间**。

只想编译不安装：运行 `./build.sh`，App 会生成在 `build/Beijing Clock.app`。

## 📦 发布 / 签名 / 自动更新

自动更新基于 [Sparkle](https://sparkle-project.org)：App 每天读取一次本分支的 `appcast.xml`，下载的更新包必须通过 EdDSA 签名校验才会安装。

每个分支（`control-panel` / `liquid` / `ultra` / `nano`）的身份只在 **`Config/Branch.xcconfig`** 一个文件里配置：`BMC_BRANCH`（决定更新源和发布标签）、`BMC_PRODUCT_NAME`、`BMC_BUNDLE_ID`、`BMC_DISPLAY_NAME`，以及版本号 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`（每次发布都要递增）。

打包发布：

```bash
./scripts/release.sh
```

脚本会归档 → 签名 →（可选）公证 → 打 zip → 用钥匙串里的 Sparkle 私钥签名 → 更新 `appcast.xml`。它**不会**上传或推送任何东西，最后会打印需要你手动执行的 `gh release create` 和 `git push` 命令。

- **有 Apple 开发者账号（付费）**：先存一次公证凭据，再带上环境变量运行：
  ```bash
  xcrun notarytool store-credentials beijing-clock-notary --apple-id <你的 Apple ID> --team-id <TEAMID> --password <App 专用密码>
  SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" NOTARY_PROFILE=beijing-clock-notary ./scripts/release.sh
  ```
  得到开启 Hardened Runtime、经过公证并装订票据的正式版本，用户首次打开不会看到 Gatekeeper 警告。
- **没有开发者账号**：直接运行，得到 ad-hoc 签名版本。自动更新照常工作（靠 Sparkle 的 EdDSA 签名保证安全），但用户第一次打开时需要在「系统设置 → 隐私与安全性」里点「仍要打开」。

> Sparkle 私钥保存在发布用 Mac 的登录钥匙串里（账户 `beijing-menu-bar-clock`）。换电脑发布前用 `Vendor/Sparkle/bin/generate_keys --account beijing-menu-bar-clock -x key.txt` 导出、在新电脑上用 `-f key.txt` 导入，导入后立刻删除 key.txt。丢失私钥将无法再向已安装的用户推送更新。

<details>
<summary><b>完整功能列表</b></summary>

- 原生 AppKit 菜单栏 + SwiftUI 设置窗口
- 可选 macOS 时区库里的任意时区，重启后保留
- 可选"使用系统时区"模式
- App 时区白名单：原生选择器添加 App，每个 App 可单独设置时区
- 从菜单栏快速打开白名单 App
- 实时检测运行中的白名单 App 是否已拿到指定时区
- 可选的自动接管：从 Dock / 访达正常打开的 App 也会被切换
- 一键全局开关自动接管，也可逐个 App 设置
- 可选显示日期、星期、秒，时间分隔符可闪烁
- 每小时 / 半小时 / 刻钟语音报时，内置提示音或自定义音频
- 开机自动启动，无 Dock 图标
- 基于 Sparkle 的自动更新（EdDSA 签名校验）

本工具只做数字时钟，不提供指针表盘模式。

</details>

<details>
<summary><b>隐私与工作原理</b></summary>

App 不使用定位；唯一的网络访问是每天一次向 GitHub 检查更新（关闭方法：`defaults write com.chen.dualtime SUEnableAutomaticChecks -bool false`）。它读取系统时钟，再按设置里选择的时区（默认 `Asia/Shanghai`）格式化显示。开启"使用系统时区"后，以 macOS 当前时区为准。

对白名单 App，时钟会请求 macOS 启动一个新的 App 进程，并带上 `TZ` 环境变量和一个本地校验标记，目标 App 本身不会被修改。设置窗口通过读取运行中进程的环境变量，区分"已按指定时区启动"和"正常打开"的 App。这只对遵循标准时区环境变量的 App 有效，而且只在从本时钟启动时生效；有些 App 可能仍使用系统时区，或显示服务器格式化好的时间。

自动接管需要逐个 App 手动开启。开启后，时钟监听 macOS 的 App 启动和退出事件：白名单 App 如果被正常打开、没有带校验标记，会被请求退出并立即按指定时区重新打开。进程启动后就不再检查，直到下一次启动或退出事件，不做持续轮询。自动接管不会强制退出 App。

</details>

---

<a id="english"></a>

## English

**Beijing Menu Bar Clock** is a small native macOS menu bar clock that always shows Beijing time (`Asia/Shanghai`) — or any time zone you pick — without changing the system time zone. It can also relaunch selected apps (WeChat, QQ, Notes, …) in a chosen time zone and verify that it took effect.

### Highlights

- **Leave the system alone** — your Mac keeps local time; the menu bar shows Beijing time.
- **Per-app time zones** — allowlist apps and reopen them in a chosen time zone, with live status.
- **Automatic takeover** (opt-in) — apps opened normally from the Dock or Finder are switched automatically. Event-driven, no polling.
- **Spoken announcements** — every hour, half hour, or quarter hour, with built-in or custom sounds.
- **Low power** — native AppKit; measured under 1 mW on average in steady state.
- **Private** — network is used only for update checks; no location, no Dock icon.
- **Auto-update** — Sparkle with EdDSA-signed updates.

### Install

Requires macOS 14+, Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The first build downloads the Sparkle update framework.

```bash
git clone https://github.com/Functionhx/beijing-menu-bar-clock.git
cd beijing-menu-bar-clock
./install.sh
```

The installer builds the app, copies it to `~/Applications`, and adds a per-user LaunchAgent so it starts at login. If the clock doesn't appear, enable it under **System Settings → Menu Bar → Allow in the Menu Bar → Beijing Time**.

To build without installing, run `./build.sh`; the app is created at `build/Beijing Clock.app`.

### Releases, signing and auto-update

Updates are delivered with [Sparkle](https://sparkle-project.org): the app reads its branch's `appcast.xml` once a day and only installs archives whose EdDSA signature matches the public key baked into the app.

Each branch configures its identity in **`Config/Branch.xcconfig`** only: `BMC_BRANCH` (update feed and release tags), `BMC_PRODUCT_NAME`, `BMC_BUNDLE_ID`, `BMC_DISPLAY_NAME`, plus `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` (bump both for every release).

Run `./scripts/release.sh` to archive, sign, optionally notarize, zip, EdDSA-sign and prepend an item to `appcast.xml`. It never uploads or pushes; it prints the `gh release create` and `git push` commands to run yourself.

- **With a paid Apple Developer account:** store notarization credentials once with `xcrun notarytool store-credentials beijing-clock-notary --apple-id <Apple ID> --team-id <TEAMID> --password <app-specific password>`, then run `SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=beijing-clock-notary ./scripts/release.sh` for a hardened-runtime, notarized and stapled build.
- **Without one:** the script signs ad-hoc. Auto-update still works and is protected by the EdDSA signature, but users have to approve the app once under **System Settings → Privacy & Security → Open Anyway**.

The Sparkle private key lives in the release Mac's login keychain (account `beijing-menu-bar-clock`). Losing it means installed copies can no longer be updated — export it with `generate_keys -x` and keep a secure backup.

### Privacy

The app reads the system clock and formats it with the selected time zone; it never uses Location Services, and its only network access is a daily update check against GitHub (turn it off with `defaults write com.chen.dualtime SUEnableAutomaticChecks -bool false`). For allowlisted apps, it asks macOS to launch a fresh process with a `TZ` environment value and a local verification marker — the target app is not modified. This only affects apps that honor the standard time-zone environment and only when launched from this clock. Automatic takeover is opt-in per app, listens for launch/termination events only, and never force-quits an app.

## License

[MIT](LICENSE)
