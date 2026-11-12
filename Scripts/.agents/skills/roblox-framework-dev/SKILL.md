---
name: roblox-framework-dev
description: Roblox FX/FC/FS 框架接入与项目扩展；脚本命名、目录、入口与启动，玩家数据、组件、服务和协议。新增或迁移模块、接入业务能力时使用；纯 UI 样式修改不触发。
---

# Roblox 框架开发

新增或扩展处理器、组件、服务、工具前，先读 [框架能力复用索引](reference-framework-capabilities.md)，按任务定位能力并核对当前源码。已有能力满足需求时直接复用；项目差异通过现有处理器、Provider、回调或子类接入，不复制框架实现。索引未覆盖时先搜索相关目录，确认缺口后再新增，不为复用增加无关抽象。

新增或迁移模块、调整入口时，先读 [目录、命名与启动](reference-project-structure.md)。只有用户明确要求框架维护或迁移时才修改对应框架实现；通用模块不得反向加载项目模块。

先查现有同类实现，接入框架前必读 [框架规则](reference-rules.md)，涵盖玩家数据、组件生命周期、协议和异步会话校验。其余参考按任务读取：

- 扩展项目、添加服务端业务或选择已有入口时，读取 [项目文件职责与扩展位置](reference-template-extension.md)，再接入加载与生命周期。
- 代码风格、FXLoader、数量文案与验证：[Luau 规范](../roblox-luau-standards/SKILL.md)。
- 数据、组件、网络接口：[API 速查](reference-cheatsheet.md)。
- 数据同步接法：[同步示例](reference-examples.md)。
- 新增协议或组件骨架：按 [game-examples](../game-examples/SKILL.md) 路由。
