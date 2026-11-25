# 无水印视频下载 · iOS 版（源码）

支持 **抖音 / B站 / TikTok** 的 iOS 原生 App 源码。你在 **Windows** 上就能把它编译出来、免费签名装到自己的 iPhone。

> 重要认知：**iOS App 必须在 Mac 上编译**，苹果规定如此。但我们用 **GitHub 的免费云 Mac** 来完成编译，你全程不需要自己的 Mac，也不用花 99 美元开发者账号——用你自己的普通 Apple ID 免费签名即可。

---

## 一、这套方案的全流程

```
Windows 上改/看源码
   → 上传到 GitHub（仓库）
   → GitHub 云 Mac 自动编译出 .ipa
   → 下载 .ipa 到 Windows
   → Sideloadly 用你的 Apple ID 免费签名 + 数据线装到 iPhone
   → 每 7 天续签一次
```

**费用：0 元**（GitHub 免费额度 + 免费个人签名）。
**限制**：免费签名 7 天过期需续签；只能装自己手机；同时最多 3 个自签 App。你的下载 App 不受其他功能限制。

---

## 二、第一次发布（约 15 分钟，只需做一次）

### 1. 注册 GitHub 账号
去 https://github.com 注册（免费）。

### 2. 新建仓库并上传本项目
- 点右上角 **+ → New repository**
- 仓库名随便，例如 `douyin-saver-ios`，选 **Public**（私有仓库也能编译，但 GitHub Actions 免费分钟数对私有仓库有限制）
- 建好后，回到本机 Windows，进入本项目目录 `DouyinSaverIOS`，执行：

```bash
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/你的用户名/douyin-saver-ios.git
git push -u origin main
```

> 如果没装 git：https://git-scm.com/download/win 下载安装，或让 WorkBuddy 帮你执行这几条命令。

### 3. 触发云编译
- 打开你的仓库网页 → 点顶部 **Actions** 标签
- 左侧点 **Build Unsigned IPA** → 右侧点 **Run workflow** → 绿色按钮 **Run workflow**
- 等待约 3–8 分钟，完成后会出现一个 **DouyinSaverIOS_unsigned** 的构建产物，点进去下载 `.ipa` 文件到 Windows。

> 之后每次改了源码，`git add . && git commit -m "xxx" && git push` 就会自动重新编译。

---

## 三、免费签名并安装到 iPhone（用 Windows）

### 1. 安装 Sideloadly
去 https://sideloadly.io 下载 Windows 版并安装（免费）。

### 2. 准备 iPhone
- 数据线连接 iPhone 和电脑，手机弹窗点 **信任此电脑** 并输密码。
- iOS 16 以上：手机进 **设置 → 隐私与安全性 → 开发者模式**，打开并重启。

### 3. 签名安装
- 打开 Sideloadly，把下载的 `.ipa` 拖进应用框。
- 在 **Apple ID** 栏填你的苹果账号密码（建议用 App 专用密码：在 appleid.apple.com 生成；Sideloadly 也支持"登录"按钮走苹果验证）。
- 点 **Start**，等待签名+安装完成。
- 手机上：**设置 → 通用 → VPN与设备管理** → 点你的 Apple ID → **信任**。

### 4. 7 天后续签
到期 App 打不开时，数据线重连电脑，把同一个 `.ipa` 再拖进 Sideloadly 点一次 **Start** 即可（不用重新编译）。
> 想省事可以装 AltStore，它能 WiFi 自动续签（同样免费）。

---

## 四、App 使用方法
1. 抖音 / B站 / TikTok 里 **分享 → 复制链接**
2. 打开本 App，点 **从剪贴板读取**（或直接粘贴到输入框）
3. 点 **下载并保存到相册**，等待完成，视频自动进「照片」。

- **TikTok** 需要手机网络能打开 TikTok（你的 iPhone 已确认可以）。
- B站走官方接口，抖音/TikTok 走云端解析接口，均无需登录。

---

## 五、常见问题

**Q：为什么要 GitHub 云编译，本机不能直接编吗？**
A：苹果规定 iOS App 只能在 macOS + Xcode 上编译，Windows 无法直接编译。GitHub 提供免费云 Mac，绕开这个限制。

**Q：一定要付费开发者账号吗？**
A：不需要。免费个人签名就能把自己编的 App 装自己手机，只是 7 天过期、不能发给别人。想要"发给别人/上架/TestFlight"才需要 $99/年。

**Q：云编译失败怎么办？**
A：到仓库 Actions 页面点开失败的那次构建，看红色报错日志。常见原因是 Xcode 版本升级导致配置变化，把报错发我即可。

**Q：Sideloadly 提示密码错误？**
A：Apple ID 需要 App 专用密码（在 appleid.apple.com 的"安全性"里生成），填那个而不是登录密码。

---

## 六、项目文件说明
| 文件 | 作用 |
|---|---|
| `VideoParser.swift` | 链接识别 + B站/抖音/TikTok 解析 |
| `Downloader.swift` | 断点续传下载 + 多候选轮换 |
| `PhotoSaver.swift` | 保存到相册 |
| `DownloadModel.swift` | 下载流程编排 |
| `ContentView.swift` | SwiftUI 界面 |
| `DouyinSaverIOSApp.swift` | App 入口 + URL Scheme |
| `Info.plist` | 权限声明（相册、网络、URL Scheme） |
| `.github/workflows/build.yml` | GitHub 云编译配置 |

Bundle ID：`com.workbuddy.douyinsaver.ios`（如需改，改 project.pbxproj 里的 PRODUCT_BUNDLE_IDENTIFIER）。
