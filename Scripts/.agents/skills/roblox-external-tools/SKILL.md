---
name: roblox-external-tools
description: >-
  Roblox_Y2 外部工具路由与生成产物回源。以下任务使用本 skill：
  （1）UIEditor 管理的界面节点：UI/Generated 中对应 View 的 ScreenGuiName 所指向的 StarterGui 界面根及其导出子节点、布局、装饰、隐藏原型，PlayerGui 中的对应副本，以及 View 管理的展示行为；修改节点、层级、尺寸、颜色、文案、交互、列表原型，或接入、排查 Generated UI 时使用，不把所有 UI 节点都视为托管。
  （2）BlockModelEditor 管理的 game.Workspace.BlockMeshs、game.ReplicatedStorage.Assets.BlockMeshs 及其子树；修改其中的方块模型、几何、位置、材质、预制体、场景节点，或在 BlockEditorWorkspace 制作与导出方块资产时使用。
  （3）GameSimulator 管理的数值配置 ModuleScript：game.ReplicatedStorage.Scripts.Game.Configs.NumericalConfig，对应 NumericalConfig.luau；调整其数值、曲线、公式或字段，修改 SimulatorWorkspace/Data/config.json、模拟玩法代码、执行已授权模拟或导出时使用。
  （4）其他源头为 XLSX 的游戏配置：商品、商店、道具、游戏、活动配置的分类与组织，查询、增删字段或记录、修改数值、检查、保存和导出，使用 GameKit 的 StudioGameToolkit 配置 MCP，不与模拟器数值配置混用。
  （5）GameKit 的文生图、参考图编辑、抠图去背景、缩放裁切、图生 3D 模型与贴图，以及 Roblox 图片/模型资产、商品管理和游戏资源接入。
  仅普通 Luau 业务代码、手写配置或已确认非托管的普通 UI 修改，不因同属游戏开发就调用本 skill。
---

# 外部工具协作

本 skill 维护 Roblox_Y2 的任务路由、源头归属、生成 UI 业务接入、XLSX 配置分类与接入和交付边界；工具公共操作细则由各 MCP 提供。路径以 `Scripts/` 为基准，Git 根由 `git rev-parse --show-toplevel` 确认。

## 先选工具，再读相关参考

| 节点、文件或需求如何识别 | 修改与接入入口 | 按需读取 |
| --- | --- | --- |
| UI 节点归属不明，或 `UI/Generated/` 中有对应脚本；需要业务接入、View 契约核对、事件或展示排错 | 先读对应 View 的 `ScreenGuiName`、根节点与查找逻辑，再只读核对 Studio 中对应 `StarterGui` 模板或 `PlayerGui` 副本；业务逻辑在 Generated 外接入 | [UI 归属与业务接入](references/ui-integration.md) |
| 已确认 UIEditor 托管的界面根、导出子节点、布局、装饰、隐藏原型及 View 管理的展示行为；需要增删、改名、调层级、尺寸、颜色、文案、交互或列表原型 | `../UIEditorWorkspace` 源 UI 与 View → 保存、导出 → Studio 核验；不在 Studio 或 Generated 中直接修补。新建可编辑 UI 也走此入口 | [UIEditor](references/uieditor.md)，节点范围和业务边界见 [UI 接入](references/ui-integration.md) |
| `game.Workspace.BlockMeshs`、`game.ReplicatedStorage.Assets.BlockMeshs` 及其子树，或方块编辑器中的模型、几何、材质、预制体和场景资产 | `../BlockEditorWorkspace`；修改节点与模型使用 BlockModelEditor MCP，先核对模式、资产或场景身份，再按实际能力保存、交付 | [方块编辑器](references/block-editor.md) |
| `game.ReplicatedStorage.Scripts.Game.Configs.NumericalConfig` 数值配置节点，对应本地 `ReplicatedStorage/Scripts/Game/Configs/NumericalConfig.luau`；需调整字段、数值、曲线、公式或模拟玩法 | `../SimulatorWorkspace/Data/config.json` 及任务相关 `Code/` → 校验、保存、模拟器导出；配置 ModuleScript 是结果，不是可直接编辑的源，也不归 XLSX 工具 | [模拟器](references/simulator.md) |
| 其他确认由 XLSX 导出的配置模块或源表；配置分类与组织，查询表、字段、记录，修改数值或结构，检查、保存、导出 | `../GameKitWorkspace` 的 StudioGameToolkit 配置 MCP → 源 XLSX → 检查、保存、导出；业务分类和字段消费在游戏侧核对 | [XLSX 游戏配置](references/game-config.md)；分类任务再读 [配置分类与组织](references/config-categories.md)，工具目标见 [GameKit](references/gamekit.md) |
| 文生图、参考图编辑、抠图去背景、缩放裁切，或图生 3D 模型及贴图制作 | `../GameKitWorkspace` 的 StudioGameToolkit 资源制作能力；先核对输入、目标与授权，再按任务读取相关 MCP skill | [GameKit](references/gamekit.md) |
| Roblox 图片或模型资产、商品管理、上传发布及资源 ID 接入游戏；普通模型放置 | GameKit 负责实际已支持的资产与商品流程，Scripts 负责业务引用，Studio MCP 核验目标实例；普通模型不进入 `BlockMeshs` | [GameKit](references/gamekit.md) 与 [Studio 操作](../roblox-studio-operations/SKILL.md) |

- 默认由当前 AI 连续完成已授权的跨工具工作，再继续 Scripts 接入；不要求切换会话、创建任务或委派 subagent。工作区路径用于目标确认，不意味着必须改变当前目录。
- 一个需求可调用多个工具，但只加载本次相关参考；生成 UI 业务接入与 XLSX 配置统一使用本 skill 的对应参考，其他业务代码、普通 UI 与 Studio 核验继续使用各自项目 skill。
- 仅做 Scripts 侧生成 UI 接入时，先读业务接入参考，不提前打开外部编辑器或加载其 MCP 文档；需要回源或调用工具时再执行下述发现流程。
- 从消费代码与导出信息确认产物源头，不仅按目录、文件名或“配置”一词选工具。多个工具不得争写同一产物，来源冲突先确认。
- 表中的节点路径用于识别托管范围，不证明实例当前已存在；具体 Studio 状态仍须查询。普通 UI、手写配置、GameKit 生成模型和方块编辑器模型分别处理，不因同在一个容器或都称“模型/配置”就混用入口。进入本 skill 也不等于获得编辑、付费、上传、导出或运行授权。

## 文档发现与复用

1. 通过工具发现查找对应服务的文档入口和真实 schema，不把逻辑接口名当作客户端一定存在的调用名。
2. 本会话首次使用某个 MCP，或开始在其工作区工作时，显式读取该服务 `AGENTS.md`，再从返回的 skills 摘要选择相关 `file`。当前上下文已有同修订说明时复用，不预加载全部工具。
3. 已知包内路径直接读取；不知道细节位置时使用该服务文档搜索，只按需读取命中文档。技能及参考路径取实际返回值，不假定统一目录。
4. `file` 相对工具文档包根目录，正文链接相对当前文档解析；不要把工作区绝对路径传给文档接口，也不把包内路径当作本地文件。
5. 修订变化或上下文丢失必要规则时，重新加载入口及任务依赖。转入新技能只加载所缺技能，不逐次业务调用重读入口。

工具文档是使用说明，不覆盖项目规则、不自动安装原生 skill，也不授予编辑、上传、付费、导出或运行权限。

## 目标、授权与写入

- 工具通用说明通过 MCP 读取；实际处理项目文件前，另读目标工作区存在的 `AGENTS.md`、`AGENTS.LOCAL.md` 及任务相关项目规则。缺少本地公共入口不构成自行复制手册的理由。
- 先用各工具的只读状态或项目查询核对规范化工作区路径、项目身份和当前文档；涉及 Studio 时按 [Studio 操作](../roblox-studio-operations/SKILL.md) 确认唯一目标。导出接口显式接收路径时也必须校验，不盲信当前窗口。
- 切换工程、文档或会话前检查脏状态；保留用户草稿和并行修改，不擅自丢弃、覆盖或强制合并。写入使用工具返回的最新 session/revision 等标识，不自行推算。
- 在用户已授权且工具允许的范围内继续，不对每次普通调用重复索取确认；扩大范围、覆盖模板、付费生成、资产上传或发布等未获覆盖的操作先确认。
- 不因阅读 skill 就启动 App、Roblox 游戏、Lua/Luau 脚本、模拟测试或长期校准；遵守项目和工具各自的明确授权要求。
- 文件工具的写权限与 MCP 业务权限独立。需要编辑兄弟目录源文件而权限不足时申请必要访问，不通过切换目录、代理脚本或修改生成结果绕过。

## 完成标准与阻断

- 按工具规定修改源内容、检查、保存、导出；工具已有的确定性交付流程由工具执行，不由 AI 手工模拟或重建。
- 区分源内容已修改、检查通过、已保存、已导出、目标已接收、Studio/Script Sync 已核验、场景已保存和游戏已测试。仅报告实际证据支持的阶段；提交成功或 `awaiting_studio` 不等于接收成功。
- 导出后核对本次涉及的字段、View 契约、资产引用或节点，再接入 Scripts；未同步或契约不一致时停止受影响部分。
- 文档或业务接口不可用、返回未知工具或 schema 不符时，记录实际调用及错误，核对服务暴露的接口；不因工具可发现就宣称可用，不自动退回旧接口、启动程序或安装替代工具。
- 未取得必要说明、能力或权限时报告该环节阻断，仅继续独立且依据充分的工作。不手改 Generated、生成配置、编辑器工程 JSON、框架或导入元数据作为旁路。
