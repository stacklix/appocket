# Lingrove

SwiftUI 原生语言学习宿主（iOS 17+），使用 WKWebView 运行可独立更新的 Vue 3 + TypeScript + Vite 子应用。第一个子应用为重写后的 **Sentra**：翻译、语法分析、地道表达、流式结果、学习记录和服务商设置。没有 Lingrove 账号或登录服务。

应用对外名称为 **Lingrove**，子应用仍为 **Sentra**。为兼容现有安装和发布配置，工程路径、Bundle ID、SDK 命名空间、本地数据目录及 `appocket.stackli.me` 更新域名保持不变。

## 运行

需要 Node.js 24 LTS、npm、Python 3；原生构建需要 Xcode。

```sh
npm ci
npm run dev                  # 浏览器预览 Sentra
npm run build                # 构建网页、ZIP、目录及原生内置模块
open ios/Appocket.xcodeproj   # 选择 Appocket scheme，运行 iPhone/iPad 模拟器
```

Xcode 项目已提交，不需要安装工程生成器。先运行 `npm run build` 再使用 Xcode，`BuiltinModules/` 是自动生成资源。真机运行时在 Xcode 选择自己的签名 Team 和 Bundle ID。可选工程重生成：`ruby scripts/generate-xcode.rb`（需要 Ruby xcodeproj gem）。

## 仓库布局

- `ios/Appocket/`：原生首页、模块更新、安装器、WebView、网络桥、本地存储。
- `sentra/`：Vue 子应用，独立版本与 manifest。
- `packages/host-sdk/`：子应用公共 TypeScript SDK。
- `scripts/package-modules.mjs`：生成 ZIP、普通 JSON 目录和原生内置资源。
- `dist/`：可部署到 HTTPS 静态服务器/CDN 的发布产物。

## 唯一的宿主后端接口

原生冷启动通过 HTTPS 请求 `HostConfig.json` 中的 `catalogURL`。目录可以是 CDN 上的静态 `catalog.json`，无需动态业务服务器、登录鉴权或发布密钥。接口返回 HTTP 200 和普通 JSON：

```json
{"modules": []}
```

每个模块包含 `id`、`name`、`version`、`entry`、`minHostVersion`、`bridgeVersion`、`stateSchemaVersion`、`allowedOrigins`、`downloadUrl`、`size`、`sha256`。构建工具会自动生成完整目录。可选 `minimumAllowedVersion` 强制淘汰旧版。版本号使用三段数字（例如 `1.2.0`），目前不接受预发布标签。

目录和 ZIP 都必须通过 HTTPS 获取，使用系统默认 TLS 证书校验，不接受重定向。下载后校验包大小和 SHA-256，确认包与目录中的元数据一致。

## 配置自动更新

App 默认从 `https://appocket.stackli.me/catalog.json` 检查更新；首次发布前接口不可用时，仍可使用内置 Sentra。更换部署地址时按以下步骤修改。

1. 指定部署域名并构建：

```sh
MODULE_BASE_URL=https://your-domain.example npm run build
```

2. 将 `dist/` 上传至上述 HTTPS 域名。
3. 在 `ios/Appocket/Resources/HostConfig.json` 填入唯一配置：

```json
{"catalogURL":"https://your-domain.example/catalog.json"}
```

4. 构建原生 App。以后修改子应用并提升 `sentra/manifest.json` 中的版本，再构建发布，即可在下一次冷启动自动更新。

发布顺序：先上传不可变版本 ZIP，再替换目录。`catalog.json` 建议 `Cache-Control: no-cache`；版本包可设 immutable。GitHub Actions 直接构建并发布普通 JSON 目录，不需要配置发布密钥 Secret。

## GitHub Actions 发布

`.github/workflows/build-gh-pages.yml` 在推送 `main` 时自动执行，也可从 Actions 手动触发（选择 `main`）。流程安装锁定依赖、检查 TypeScript、运行测试，再构建并校验发布产物；校验通过才将 `dist/` 发布到 `gh-pages` 分支根目录。无需额外发布密钥 Secret。

发布后的分支结构：

```text
gh-pages/
├── .nojekyll
├── CNAME
├── index.html
├── catalog.json                  # App 启动拉取的包信息
├── packages/
│   └── sentra-1.0.0.zip           # 每个子应用独立版本包
└── sentra/
    ├── index.html                # 浏览器可直接访问
    ├── manifest.json
    ├── sw.js
    └── assets/                   # 与 ZIP 内文件逐字节一致
```

沿用仓库的域名 `appocket.stackli.me`，对应地址为：

- App 更新目录：`https://appocket.stackli.me/catalog.json`
- Sentra ZIP：`https://appocket.stackli.me/packages/sentra-1.0.0.zip`（版本变化后文件名相应变化）
- Sentra 网页：`https://appocket.stackli.me/sentra/`

目录为普通 `{ "modules": [...] }` JSON；模块记录包含 `webUrl`、`downloadUrl`、版本、包大小和 SHA-256。原生根据 `downloadUrl` 下载；`webUrl` 供浏览器访问。`npm run verify:release` 验证目录与所有包一一对应、哈希及大小正确、ZIP 与网页目录一致、HTML 引用的资源存在。

每次运行还保存一份 `lingrove-release` Actions artifact，保留 14 天。发布保留既有的单提交策略：只替换 `gh-pages` 产物分支，`main` 源码历史不变。仓库规则须允许 Actions 的 `GITHUB_TOKEN` 写入及强推 `gh-pages`；工作流同时申请 `pages: write` 以请求 Pages 构建。

仓库现有 GitHub Pages 配置为 `gh-pages` 分支根目录、自定义域名 `appocket.stackli.me`。因为 `GITHUB_TOKEN` 推送不会自动触发分支式 Pages 构建，工作流推送后通过 [GitHub Pages 构建 API](https://docs.github.com/en/rest/pages/pages#request-a-github-pages-build) 显式触发构建，并等待本次产物提交构建成功；失败或超时会使工作流失败。无需切换 Pages 发布源，也不会修改 DNS 设置。

新增子应用时，在根 `package.json` 的 workspaces 和 `modules.json` 中加入目录名，提供该子应用的 `build` 命令、`manifest.json`，并构建到 `dist/<目录名>/`；manifest 的 `id` 与目录名保持一致。统一构建脚本会依次构建清单中的所有子应用并生成相应 ZIP、网页目录和原生内置资源。

## 更新行为

- 首页立即展示；冷启动检查完成前暂不进入模块。
- 检查目录中的所有模块，逐个下载兼容的新版本；目录中新模块也会安装。
- 验证目录结构、包大小和 SHA-256，在临时目录解包，验证 manifest 后原子切换注册表。
- ZIP 只接受发布工具生成的 **ZIP_STORED**（不压缩），拒绝加密、压缩、路径越界、符号链接和重复文件。单包最大 50 MiB、2000 个文件。
- 普通下载失败保留旧版本；低于最低允许版本则禁止进入。离线时沿用缓存的最低版本限制。
- 当前会话不替换资源；若手动检查时模块仍打开，更新会延后到下次检查。
- 页面 20 秒内未调用 `runtime.ready`、导航失败或 Web 内容进程退出时尝试回退；不会回退至已被强制淘汰版本。失败版本会被记录，等待更高版本。
- 记录、偏好与代码包分开保存，更新和回退不覆盖学习数据。目前只接受 stateSchemaVersion=1，未来数据迁移需显式升级协议。

## 多域名网络桥

子应用通过 `host.http` 对应的 SDK `request()` 调用网络：

```ts
import { request } from '@appocket/host-sdk';
const response = await request({
  url: 'https://dictionary.example.com/search?q=apple',
  method: 'GET'
});
```

原生使用 URLSession，不受浏览器 CORS 限制。每个模块支持多个 `allowedOrigins`，按 HTTPS 协议、域名和端口精确匹配，禁止重定向和隐式 Cookie。自定义服务商由子应用设置页触发 `authorizeOrigin()`，原生弹窗展示目标域名并记录用户授权，可从原生设置撤销。模块不能自行把任意域名加到可信发布清单。

桥支持 JSON/文本响应、SSE 分块、取消、超时及响应大小限制。原生注入 CSP，阻止网页绕过网络桥访问远程资源。浏览器开发模式使用 fetch，仍需要服务商正确配置 CORS。服务商 API Key 是 Sentra 可选的第三方凭据，不是 Lingrove 登录；只留在当前页面内存/浏览器 sessionStorage，不写原生历史文件。

## 数据与迁移

原生历史及偏好保存至 Application Support/Appocket/State/<模块 ID>，由主框架身份限定命名空间。浏览器历史沿用 `sentra.sentences.v1`；原 Flutter Web 的记录在相同来源下可继续读取，API 设置可从旧 sessionStorage 恢复。原生不能自动读取 Safari 或旧 PWA 的存储。未完成/格式不合格的流式结果不写历史；损坏历史会停止写入以保护数据。

旧 Flutter 源码和 PWA 构建已由 Vue 替代，原实现可从 Git 历史获取。发布时提供退出旧 service worker 的脚本；浏览器预览不再承诺 PWA 离线缓存，离线使用由原生内置/下载模块提供。

## 验证

```sh
npm run check                 # TypeScript、前端测试、生产构建
scripts/test-native.sh        # Swift 核心：目录校验、安装、版本、域名、回滚、损坏包
xcodebuild -project ios/Appocket.xcodeproj -scheme Appocket \
  -sdk iphonesimulator -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build
# 在可用的 iPhone 模拟器上运行 UI 测试：
xcodebuild -project ios/Appocket.xcodeproj -scheme Appocket \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

前端测试使用模拟模型响应，不调用收费服务。WebKit 集成测试使用本地模拟响应验证原生 SSE 转发、域名拦截和持久存储。iOS UI 测试检查内置 Vue 页面、通信桥和跨重启偏好保存；请在专用测试模拟器运行。

## 发布边界

未自动部署服务器、推送 Git 或执行 App Store 提交。上架前需配置签名团队、应用图标/商店资料，并确认 Apple 4.7 对下载 HTML 应用、原生桥、模块索引和隐私共享的要求。本项目的技术实现不代表已获审核许可。
