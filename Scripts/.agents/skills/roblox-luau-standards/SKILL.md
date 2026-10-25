---
name: roblox-luau-standards
description: Roblox_Y1 的 Luau 编码与普通审查规范。编写、重构、修复代码或审查可读性时使用。
---

# Roblox Luau 规范

新增处理器、组件、服务或通用工具时，先按 [框架开发技能](../roblox-framework-dev/SKILL.md) 的能力复用索引和模板职责参考确定复用入口，避免复制现有能力或随意另建预留入口。

编写或迁移手写模块前先按 [AGENTS.md 的脚本命名与归属](../../../AGENTS.md) 确认：`C` 项目客户端、`FC` 框架客户端、`S` 项目服务端、`FS` 框架服务端；框架共享使用 `FX`。文件、类注册及组件协作名遵循同一归属。

编码或普通审查读取 [项目编码规则与 FXLoader](reference-rules.md)。配置读取、文案和验证要求遵循 AGENTS.md。纯服务端安全审查使用 `server-code-critical-review`，不额外触发风格审查。

涉及游戏动态文本或语言刷新时，使用 [Roblox 项目本地化 skill](../roblox-localization/SKILL.md)。不改 Generated；接入 UIEditor 生成界面时，遵循 [生成 UI 接入](../roblox-uieditor-integration/SKILL.md)，展示翻译缺失或错误走回源改造流程，不在项目中覆盖补译；已处理的不重复补。无 Generated 对应的业务动态消息由所属脚本处理；各文件独立定义且 Key 唯一，配置引用与静态节点不补翻译定义。
