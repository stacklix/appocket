# Appocket

Appocket 是统一入口 PWA：安装并打开 Appocket 后，先展示全部应用，选择 Sentra 进入使用；子应用顶部的“Appocket · 全部应用”返回入口。当前已接入 Sentra，后续应用继续加入列表。

## 子应用

| 应用 | 地址 | 功能 |
| --- | --- | --- |
| [Sentra](sentra/README.md) | `/sentra/` | 翻译、语法分析、地道表达、学习记录 |

## 构建与预览

需要 Flutter（已用 3.38.3 / Dart 3.10.1 验证）和 Python 3。首次准备依赖：

```sh
cd sentra
flutter pub get
cd ..
python3 scripts/build.py
python3 -m http.server 8080 --bind 127.0.0.1 --directory dist
```

打开 http://localhost:8080/ 或 http://localhost:8080/sentra/ 。开发时可在 `sentra` 目录运行 `flutter run -d chrome`；安装和离线验证请使用上述生产构建。

将 `dist/` 的内容部署到静态站点的域名根目录，保留 `/sentra/` 路径；线上必须使用 HTTPS。建议 `index.html`、`sw.js`、`flutter_bootstrap.js` 使用 `Cache-Control: no-cache`，其余没有内容哈希的资源也不要设置长期 immutable 缓存。不要将子应用的 service worker scope 提升到根目录。

## PWA 行为

- Android/桌面 Chrome 可从浏览器菜单安装；iOS Safari 使用“分享 → 添加到主屏幕”。
- 首次联网打开后，service worker 下载完整静态资源（含 Flutter 引擎与字体）；缓存完成后可断网重新打开并阅读已有记录。首次缓存需要一定时间，浏览器清理站点数据后需重新联网缓存。
- 新分析仍需要网络、用户自己的 API Token，以及允许浏览器 CORS 的服务商。
- 更新在旧版本的所有窗口关闭后生效；重新打开即可使用新版本。缓存名称包含子应用 scope 和构建内容哈希，不清理其他应用缓存。
- Appocket 自身可以安装，启动地址为 `/`，离线可打开应用列表。入口缓存仅包含首页与安装资源，不把子应用请求替换为首页。Sentra 使用更具体的 `/sentra/` service worker 与独立缓存。尚未联网打开并完成缓存的子应用需要联网首次加载。

## 验证

```sh
cd sentra
flutter analyze
flutter test
flutter test --platform chrome test/web_storage_test.dart
cd ..
# 预览服务器启动后，需本机 Chrome 及可被 Node 解析的 playwright 包：
node scripts/check-pwa.cjs
```

浏览器检查覆盖 manifest、缓存落地、断网重载、入口首次进入 Sentra、两者离线重载、离线选择应用及从子应用返回入口。

## 后续添加应用

新应用放入独立目录，构建到 `dist/<应用名>/`，在首页添加入口。为每个应用配置独立 manifest scope、service worker scope 和存储键前缀，并在 `scripts/build.py` 中加入对应构建步骤。

## GitHub Actions 构建

`.github/workflows/build-gh-pages.yml` 在推送到 `main` 时自动运行，也可在 Actions 页面手动触发（选择 `main`）。固定使用 Flutter 3.38.3，安装锁定依赖、执行静态分析与单元测试，再运行统一构建脚本。

构建成功后，仅将 `dist/` 的静态产物推送到 `gh-pages` 分支根目录，并添加 `.nojekyll`。每次生成一个无父提交的新提交，强制替换 `gh-pages`：该分支始终只有一条可达提交记录；`main` 保留正常源码历史。失败的构建不更新 `gh-pages`。工作流串行发布，使用内置 `GITHUB_TOKEN`，无需额外 Secret；仓库规则须允许 Actions 写入并强推 `gh-pages`。

这里只构建并更新产物分支，不自动配置 GitHub Pages。GitHub 官方说明：使用 `GITHUB_TOKEN` 推送的提交不会触发分支式 Pages 构建（[发布源说明](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)）。目前产物使用域名根路径部署；若托管到 `stacklix.github.io/appocket/`，需另行适配 `/appocket/` 基础路径。

自定义域名为 `appocket.stackli.me`。发布流程每次都会在 `gh-pages` 根目录生成 `CNAME`（内容为该域名），因此覆盖产物分支时不会丢失域名文件。
