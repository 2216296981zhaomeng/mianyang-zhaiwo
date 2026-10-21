# 免费 iOS App Store 包：GitHub Actions 离线构建

Windows 无法运行文档里的 Xcode 离线打包；这里用 GitHub Actions 的免费 macOS 26 机器执行同一套
DCloud iOS Vapor SDK 流程，产出可上传 App Store Connect 的 IPA。

## 已具备

- App Store 描述文件：`证书/pingguopro.mobileprovision`（App ID `com.zhaiwo.my`，`get-task-allow=false`，无注册设备）
- 发布证书：`证书/zhaiwomls-my-pro.p12`（iPhone Distribution: Zhijun Guo / 3Q57K52TU5，口令 `tcwang`）
- iOS 资源导出：`unpackage/resources/app-ios`（191.7MB）
- 可直接上传的资源压缩包：`unpackage/ios-github/app-ios-resources-1.1.01.zip`（102.5MB）
- 构建脚本：`.github/workflows/ios-appstore.yml`、`scripts/ios/*`

## 你需要做的一次性准备

1. 新建一个 GitHub 仓库（私有即可），把本仓库的以下内容推上去：
   - `.github/workflows/ios-appstore.yml`
   - `scripts/ios/build-ipa.sh`
   - `scripts/ios/build-plugins.rb`
   - `scripts/ios/configure-host.rb`
   - `scripts/ios/merge-plist.py`
   - `scripts/ios/ExportOptions.plist`
2. 把 `unpackage/ios-github/app-ios-resources-1.1.01.zip` 上传到你的 OSS / GitHub Release，
   拿到一个 HTTPS 下载地址（下面叫 `RESOURCES_URL`）。
3. 在 GitHub 仓库 **Settings → Secrets and variables → Actions** 添加三个 Secret：
   - `IOS_P12_BASE64`：`证书/zhaiwomls-my-pro.p12` 的 Base64
   - `IOS_P12_PASSWORD`：`tcwang`
   - `IOS_PROFILE_BASE64`：`证书/pingguopro.mobileprovision` 的 Base64

本机生成 Base64（PowerShell，直接复制到剪贴板，不要写进文件/仓库）：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('D:\ZM\mianyangzhaiwo\证书\zhaiwomls-my-pro.p12')) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes('D:\ZM\mianyangzhaiwo\证书\pingguopro.mobileprovision')) | Set-Clipboard
```

## 运行

GitHub → Actions → **iOS App Store IPA** → Run workflow：

- `resources_url`：填第 2 步的 HTTPS 地址
- `sdk_url`：保持默认（DCloud iOS Vapor SDK 5.26）
- `run_plugins`：保持 `true`

构建完成后下载 artifact **ios-appstore-ipa**，用 AppUploader / Transporter 上传 App Store Connect。

## 流水线做什么

1. 下载 DCloud iOS Vapor SDK（780MB，有缓存）与 App 资源包
2. 以 SDK 自带 `UniAppXVaporDemo` 为主工程模板
3. 替换 `uni-app-x/apps/__UNI__607FC4F`
4. 写 Info.plist：AppID、`uniRuntimeVersion 5.26`、`channel appstore`、权限文案、URL Scheme，
   并合并 `zw-alipay-auth` / `zw-ttlock` 的插件 Info.plist
5. 把 `uni_modules/*/utssdk/app-ios/src/*.swift` 逐个编译成 `unimodule*.xcframework`
   （TTLock 链接自带的静态 `TTLock.xcframework`；腾讯 IM 通过 CocoaPods 安装 `TXIMSDK_Plus_iOS`）
6. 主工程设置 `com.zhaiwo.my` / `3Q57K52TU5` / `pingguopro`，移除调试用 `DCloudDebugServe`
7. `xcodebuild archive` + `-exportArchive`（`app-store-connect`）导出 IPA
8. 校验 Bundle ID、版本、签名并输出 SHA-256

## 已知迭代点

- 插件工程由 `xcodeproj` 动态生成，首次运行可能需要在日志里修正个别插件的 pod / 链接参数；
  失败时把 `ios-build-logs` artifact 里对应的 `plugin-*.log` 发我。
- 每次 macOS 构建约 40–60 分钟（含 780MB SDK 下载；缓存命中会快很多）。
- 私有仓库免费额度 2000 分钟/月，macOS 按 10 倍计；一次构建在免费额度内。
- 生成的 IPA 是否通过 App Store 审核还取决于 App 内容（例如启动页下载资源、微信 Universal Link 等）；
  这里只保证包结构与签名正确。
