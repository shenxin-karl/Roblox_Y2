---
name: roblox-studio-operations
description: 使用 Roblox MCP 查询和核对 Studio 场景、存储、UI 与同步脚本，区分 Edit/Client/Server，并维护手工或 AI 模型的存放边界。涉及实例路径、节点属性、模型放置或 Script Sync 核验时使用。
---

# Roblox Studio 节点与同步

## 查询实际节点

1. 先用 `list_roblox_studios` 确定目标 Studio，再用 `get_studio_state` 确认当前模式和可用 DataModel。
2. 用 `search_game_tree` 查询目标子树，按需限定路径、类型、深度和数量；用 `inspect_instance` 读取具体属性、Attributes 和子节点。名称、完整路径、层级和 ClassName 以 MCP 返回为准，不猜测。
3. 编辑态查询使用 `Edit`；已有试玩中的运行时查询按目标使用 `Client` 或 `Server`。UI 模板查 `StarterGui`，玩家实际 UI 在客户端 DataModel 中查目标玩家的 `PlayerGui`，不把模板当作运行时界面。

- `Workspace`、`ServerStorage`、`StarterGui` 等非脚本实例在 Studio 中维护，不假设本地同步目录包含它们，不通过 Script Sync 创建。
- 涉及外部编辑器托管的源 UI、方块模型、资源或数值配置时，先按 [外部工具协作](../roblox-external-tools/SKILL.md) 回源及导出，再用本 skill 核验实际 Studio 结果；不在 Studio 手改托管产物来替代源内容修复。
- 修改现有 UI 节点前，先按 [UI 归属与业务接入](../roblox-external-tools/references/ui-integration.md) 将实际节点与 Generated View、源 UI 对应，确认是否由 UIEditor 管理；不能仅按名称或 `StarterGui` 位置判断，归属未明不写入。
- 只读查询可直接执行；所需运行时 DataModel 尚未开启时，说明待确认范围，仅在已有测试或试玩授权涵盖本次操作时启动游戏。
- MCP 不可用时报告当前实例结构尚未确认；本地脚本、模型副本和动态创建代码仅能说明预期结构，不能证明 Studio 实例已存在或同步完成。
- UI 文本与隐藏原型的 AutoLocalize 核验按 [本地化](../roblox-localization/SKILL.md)；代码中的节点加载按 [FXLoader 规则](../roblox-luau-standards/reference-rules.md#fxloader-节点与模块加载)。

## 手工或 AI 模型的存放

- 场景中直接摆放的模型统一放在 `game.Workspace.Decorations`。
- 供运行时克隆的可复用模板统一放在 `game.ReplicatedStorage.Assets.Decorations`。
- `game.Workspace.BlockMeshs`、`game.ReplicatedStorage.Assets.BlockMeshs` 及其子目录专供地图块编辑器管理，手工或 AI 模型及其本地副本均不得放入。
- 模型及上述容器在 Studio 中维护；确需本地副本时明确导出与导入步骤，不把本地保存当作 Studio 已更新。

## Script Sync 核验

- 对照本次本地改动，只读核对同步后脚本的完整路径、ClassName、RunContext（适用时）和内容。ModuleScript 与执行入口的类型约定见 [目录、命名与启动](../roblox-framework-dev/reference-project-structure.md)。
- Script Sync 无法确认或发生冲突时报告范围，不覆盖任一侧，不以磁盘保存成功代替同步成功。
- 语法编译、Studio 同步、场景保存与游戏运行是不同结果，分别报告实际核验状态；Luau 编译流程见 [验证规则](../roblox-luau-standards/reference-rules.md#验证)。
