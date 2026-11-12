---
name: roblox-luau-standards
description: Roblox_Y2 的 Luau 编码、FXLoader、数值文案与验证规范。编写、重构、修复代码或审查可读性时使用。
---

# Roblox Luau 规范

新增处理器、组件、服务或通用工具时，先按 [框架开发技能](../roblox-framework-dev/SKILL.md) 的能力复用索引和项目职责参考确定复用入口，避免复制现有能力或随意另建重复入口。

新增或迁移模块、调整入口前，按框架 skill 的 [目录、命名与启动](../roblox-framework-dev/reference-project-structure.md) 确认归属。

编码或普通审查读取 [项目编码规则、FXLoader、数值文案与验证](reference-rules.md)。纯服务端安全审查使用 [服务端关键审查](../server-code-critical-review/SKILL.md)，不额外触发风格审查。

涉及动态文本或语言刷新时，读取 [本地化](../roblox-localization/SKILL.md)；涉及 UI 节点归属或 UIEditor 生成界面时，读取 [外部工具协作](../roblox-external-tools/SKILL.md) 和 [UI 归属与业务接入](../roblox-external-tools/references/ui-integration.md)。翻译与 View 接入细则分别在本地化 skill 和该参考维护。
