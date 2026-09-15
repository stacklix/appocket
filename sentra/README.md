# Sentra PWA

从原 Sentra Flutter 项目迁入的 Web 子应用，保留翻译、语法、更地道三个独立 Tab、流式结果、学习记录的搜索/重开/删除，以及连接和学习偏好设置。源码及原有测试位于 `lib/` 和 `test/`，不包含 iOS/macOS 工程或构建缓存。

## 使用

1. 在“连接与偏好”中选择 OpenAI 兼容或 Anthropic 兼容接口，填写服务商 API Base URL、模型名和自己的 Token。
2. 选择解释语言及学习水平；翻译页单独选择目标语言。
3. 输入句子并提交。三个 Tab 独立保留输入与结果；“重新生成”会重新请求服务商。
4. “学习记录”中可以搜索、打开或删除已保存的内容。

模型调用由浏览器直接发往配置的服务商，无自建业务后台。服务商须支持页面来源的 CORS；两种协议的响应结构及流式处理沿用原项目。

## 本地数据

学习历史保存为带 `sentra.` 前缀的 localStorage 数据；连接设置及 Token 保存于当前标签页的 sessionStorage。刷新可恢复，关闭后是否恢复取决于浏览器会话恢复行为；需要立即删除 Token 时使用应用里的移除操作。不同域名/端口的数据不共享，原项目里的历史不会自动迁入。

Service worker 仅缓存构建时枚举的静态资源，不缓存模型请求。缓存完成后支持离线启动和历史阅读，离线不提供新的 AI 分析。应用关闭再打开时可能需要重新填写连接设置。

## 构建

从仓库根目录运行 `python3 scripts/build.py`，产物位于 `dist/sentra/`。此脚本同时生成离线资源清单；单独运行 `flutter build web` 不会生成完整 PWA 的 `sw.js`。

部署、安装与测试步骤见 [仓库说明](../README.md)。

## 实现

- `web/manifest.json`：相对 scope、start URL 和应用标识，支持安装到主屏幕。
- `web/flutter_bootstrap.js`：加载本地 Flutter 引擎并注册当前目录下的 service worker。
- `../scripts/sw.js`：只处理本应用范围内的静态资源，按构建版本更新缓存。
- `lib/core/storage_web.dart`：会话凭据与本地学习记录。

采用自有 service worker，避免依赖 Flutter 已弃用的自动生成机制，参见 [Flutter Web FAQ](https://docs.flutter.dev/platform-integration/web/faq)。

中文界面字体随应用打包，使用 Noto Sans CJK SC（SIL Open Font License，见 `assets/fonts/OFL.txt`），确保离线中文可读。其他语言的罕见字符仍可能依赖 Flutter 联网回退字体。
