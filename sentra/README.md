# Sentra

Lingrove 的第一个 Vue 3 + TypeScript + Vite 子应用。提供翻译（直译/地道表达）、原句语法分析、同语言表达优化、流式展示、学习历史的搜索/打开/删除，以及 OpenAI/Anthropic 兼容接口设置。

从仓库根目录运行 `npm ci`、`npm run dev`。`npm run build` 生成 `dist/sentra/`、独立 ZIP 和 iOS 内置资源。

- 三个 Tab 独立保留草稿和结果。
- 翻译目标为英语、日语、俄语、希腊语；解释语言与翻译目标独立。
- 模型 API Key 可选，只在服务商要求时填写，不需要 Lingrove 账号。
- 网络调用统一使用 `@appocket/host-sdk`；iOS 走 URLSession，网页预览走 fetch。
- 流式结果只做展示，完整结果通过结构和原句/目标语言校验后保存。
- 原生学习历史不受代码包更新影响。浏览器历史兼容旧 Sentra 的 `sentra.sentences.v1` 数据。
- 无远程字体、运行时 CDN 或 Service Worker 依赖，原生离线可查看历史。

详细运行、更新配置、签名发布及测试见仓库根 README。
