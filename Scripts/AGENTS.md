# Roblox_Y1 Game 工作区指南

## 角色

你是一名 Roblox 游戏开发者。
项目使用 Luau 和 FX/FC/FS 组件框架，通过 Team Create 与 Studio Script Sync 协作开发。
本文件中的相对路径以当前 `Scripts/` 工作区为基准。Git 仓库根目录通过 `git rev-parse --show-toplevel` 确认，不假设当前目录就是仓库根。

## 重要目录
- `ReplicatedStorage/Scripts/Framework/`：FX/FC/FS 框架，按 Shared/Client/Server 分层；`ReplicatedStorage/Scripts/Game/Shared/`：公共配置与模块
- `ServerScriptService/Server/`：服务端业务入口、项目类和私有配置
- `StarterPlayerScripts/Client/`：客户端业务入口、玩家对象与项目组件；对应 Studio 的 `StarterPlayer.StarterPlayerScripts.Client`
- `Docs/功能验收清单.md`：当前已实现功能及其验收状态
- `Workspace`、`ServerStorage`、`StarterGui`：Studio 中的场景、服务器模板和 UI 节点；不假设当前本地目录包含这些非脚本实例

## 脚本入口与模块

- 客户端只有一个入口：`StarterPlayerScripts/Client/Main.local.luau`（LocalScript）。
- 服务端只有一个入口：`ServerScriptService/Server/Main.server.luau`（Script，RunContext 为 Server）。
- 其余业务类、组件、配置和工具使用 `.luau` ModuleScript，通过 `require` 加载，不另建执行入口。
- 脚本通过 Studio Script Sync 同步；场景、模型和 UI 节点在 Studio 中维护，通过 Roblox MCP 查询和核对。

## 脚本命名与归属

- 手写的端专属模块、类、组件和工具按归属命名；文件名、注册类名及组件协作名保持一致的前缀。
- `CXXX`：项目客户端，放在 `StarterPlayerScripts/Client/`；例如 `CMainUICompClass`。
- `FCXXX`：框架客户端，放在 `ReplicatedStorage/Scripts/Framework/Client/`；例如 `FCFriendInviteCompClass`。
- `SXXX`：项目服务端，放在 `ServerScriptService/Server/`；例如 `SPlayerObjectClass`。
- `FSXXX`：框架服务端，放在 `ReplicatedStorage/Scripts/Framework/Server/`；例如 `FSPlayerObjectClass`。
- 框架共享能力沿用 `FX` 前缀，放在 `Framework/Shared/`；两端公共的项目配置与业务模块不强加客户端或服务端前缀。
- `Main`、`GameInit`、`FClient/FServer/FShared/FrameworkInit` 等固定引导入口沿用既有名称；Generated 的名称由生成工具维护，不手工重命名。
- 普通项目开发只继承和接入框架；用户明确要求框架迁移或框架维护时，才修改授权范围内的框架代码。迁入框架的通用模块不得反向依赖 `Game/` 或项目客户端模块，项目差异通过既有 Provider 或项目子类接入。

## 技能使用

项目技能位于 `.agents/skills/`，由 Codex 根据各技能的 name 和 description 发现并选择。使用时读取对应 `SKILL.md`，参考文档按需渐进加载；不要默认读取全部技能。

扩展地图模板、添加处理器、组件、服务或通用工具时，使用 [框架开发技能](.agents/skills/roblox-framework-dev/SKILL.md)，先按能力复用索引查已有实现，再按模板文件职责选择扩展位置。已有能力通过现有接口接入，不重复实现支付、存档、背包、奖励、同步或 UI 基础设施，不把独立业务集中到 Main、玩家对象或杂项组件。

## 明确的禁止(必须遵守)
- 禁止修改 `StarterPlayerScripts/Client/UI/Generated/` 及其所有子目录中的脚本；这些脚本仅可只读查看，不得为修复报错而修改。
- 涉及 `Generated` 脚本的报错通常源于接入脚本，应优先排查并修复接入脚本，不因报错堆栈指向生成脚本就修改生成脚本。
- 如果无法通过修改接入脚本解决问题，必须告知用户当前报错、已排查的情况和无法修复的原因；不得擅自修改 `Generated` 中的脚本。
- 配置导出目录 `ReplicatedStorage/Scripts/Game/Configs/` 中由源配置生成的 `.luau` 文件仅可只读查看，禁止直接编辑、覆盖或临时修补；自定义导出目录中的生成配置同样遵守。配置变更必须通过配置 MCP 修改原始 XLSX，检查并保存成功后，再通过 MCP 导出更新对应文件。MCP 不可用或检查、保存、导出失败时，报告阻断，不绕过流程修改生成文件。
- 禁止一次性读取 `ReplicatedStorage/Scripts/Game/Configs/` 和 `ReplicatedStorage/Scripts/Game/Shared/` 整个目录；先使用 `rg` 定位目标配置和行号，再只读取完成任务所需的最小文件片段。
- 手工或 AI 制作的模型禁止放入 `game.Workspace.BlockMeshs` 和 `game.ReplicatedStorage.Assets.BlockMeshs`，包括它们的子目录；这两个目录专供地图块编辑器管理，对应本地目录也不得用于保存此类模型。

## 制作模型的存放规则

- 场景中直接摆放的模型统一放入 `game.Workspace.Decorations`。
- 供运行时克隆的可复用模型模板统一放入 `game.ReplicatedStorage.Assets.Decorations`。
- 模型与上述容器在 Studio 中维护，不通过 Script Sync 创建非脚本实例。确需保存本地模型副本时明确导出与导入步骤，不把本地保存当作 Studio 已更新；不得将模型放进 BlockMeshs。

## 补充说明
- 需要读取场景、存储或 UI 节点时，直接使用 Roblox MCP：先用 `list_roblox_studios` 确定目标 Studio，再用 `get_studio_state` 确认当前模式和可用 DataModel。
- 用 `search_game_tree` 查询目标子树，按需要限定路径、类型、深度和结果数量；用 `inspect_instance` 获取具体节点的属性、Attributes 和子节点。节点名称、完整路径、层级和 ClassName 以 MCP 返回结果为准，不猜测。
- 编辑态查询使用 `Edit`；已有试玩中的运行时查询按目标使用 `Client` 或 `Server`。UI 模板查 `StarterGui`，玩家实际界面在客户端 DataModel 中查目标玩家的 `PlayerGui`，不要把模板当作运行时界面。
- 只读节点查询直接进行；需要的运行时 DataModel 尚未开启时，说明待确认范围，按既有测试或试玩授权决定是否启动游戏。
- MCP 不可用时说明当前实例结构尚未确认；本地同步脚本、模型副本和动态创建代码可用于分析预期结构，但不能作为当前 Studio 或运行时节点已存在、同步已完成的证据。
- 业务模块显式声明 `local FX, FC, FS = _G.FX, _G.FC, _G.FS` 中实际用到的变量；每个 ModuleScript 返回有效结果。
- 项目协议声明在 `ReplicatedStorage/Scripts/Game/Shared/NetworkProtocol.luau` 的 `ClientMsgID/ServerMsgID`；框架协议在 `ReplicatedStorage/Scripts/Framework/FrameworkInit.luau`。
- 客户端、服务端的项目与框架代码按上文“脚本命名与归属”放置；普通项目开发通过项目子类继承和覆写接入框架，不直接修改框架实现。
- 框架采用 `Scripts/Framework/Shared`、`Client`、`Server` 分层，`FShared/FClient/FServer/FrameworkInit` 放在框架根目录。服务端框架仅由服务器初始化，私有配置仍放在 `ServerScriptService`。
- 代码使用 Roblox 原生服务、节点 API 和有效资源 URI。

## PowerShell 命令安全规范
- 运行 PowerShell 命令时，始终使用 PowerShell 安全语法，避免解析错误。
- 对正则/模式/glob 参数优先使用单引号，例如：`-g '*.luau'`、`'GetNumber\(|WatchDataChanged\('`。
- 不要在类似正则的参数中留下未加引号的 `|`、`*`、`(`、`)` 或 `"`；应显式加引号或转义。
- 在 PowerShell 中使用 `rg` 时，优先采用这种形式：`rg -n --max-count 200 -g '*.luau' 'pattern1|pattern2|pattern3' <path>`。
- 使用 `rg` 检索时，先只用 `-n` 精确定位行号；禁止默认使用 `-C`/`--context` 输出上下文。
- 必须限制返回量：优先加 `--max-count`，或先限定到更小的路径/文件段后再检索。
- 不要无范围地使用 `rg -u`、`rg -uu`、`rg -uuu`；确需检查隐藏或被忽略文件时，必须同时限定到明确目录和文件类型。
- 如果命令仍然会被 PowerShell 错误解析，在合适情况下使用 `--%` 来停止 PowerShell 的参数解析。

## FXLoader 节点与模块加载

- 框架初始化后的必需固定路径节点和模块优先用 `FX.Loader`；接口与等待语义见 `.agents/skills/roblox-luau-standards/reference-rules.md`。

## 数值文案显示

- 力量、货币、经验、价格、收益等数量文案，统一调用 `ReplicatedStorage/Scripts/Game/Shared/GameUtility.luau` 的 `GameUtility.NumberToText`；不要在各 UI 中重复实现单位换算或小数格式化。
- 大数使用该方法定义的 `K/M/B/T/Qa/...` 英文缩写；小数沿用通用方法的两位小数规则，例如 `2/3` 显示为 `0.67`。明确需要取整显示时使用 `NumberToTextFloor`。
- 等级、序号、背包件数/容量、时间和百分比按各自语义显示，不强制使用数量缩写。
- 格式化仅用于文案；计算、比较、存档和服务端发奖始终使用原始数值。均分收益先计算再格式化，不使用格式化后的字符串参与计算。

## 游戏内动态文本翻译

- 涉及业务动态文本、翻译定义或语言刷新时，先读取并遵循 [Roblox 项目本地化 skill](.agents/skills/roblox-localization/SKILL.md)；声明、Key 稳定性、运行时接口及验证规则统一在该 skill 维护。
- 不修改 Generated 或生成配置，不为静态节点、配置引用或已正确翻译的动态文本重复补定义；编码任务不手工修改翻译文件、不通过 Roblox MCP 维护翻译表或上传云端。
- UIEditor 导入的 UI 节点与 `UI/Generated/` 展示脚本已在制作阶段处理动态文本及 AutoLocalize；接入时默认沿用节点配置和克隆继承，不在 OnReady、Render 或刷新逻辑中重复关闭。接入完成后按 [本地化 skill](.agents/skills/roblox-localization/SKILL.md) 通过 Roblox MCP 批量只读检查本次 UI 的文本节点及隐藏原型；属性异常或无法核验时反馈用户，不自动修改生成节点或补运行时开关。

- AutoLocalize 只在需要处理的具体文本节点上关闭，不关闭图片父节点、按钮、容器或整组子树。祖先关闭会阻断后代，子节点 true 不能恢复；MCP 核验须检查祖先和后代，发现翻译层级冲突反馈用户。

## Luau 验证规则
- 新增或修改 Luau 后默认只做编译/语法验证，以及通过 Roblox MCP 只读核对同步后的脚本类型、RunContext 和内容，不自行运行 Lua 脚本或启动游戏。用户明确要求运行测试或试玩时，以该授权为准，并在结果中区分语法、同步核对与实际运行验证。
- 通过 Roblox MCP 只读查询当前场景或 UI 节点属于开发信息读取，可直接执行；这不等于启动试玩或运行游戏测试。
- 先确认本地可用的 Luau 编译器；缺失时报告未完成语法验证。Script Sync 无法确认或发生冲突时报告待核对范围，不把磁盘保存成功当作同步成功。
- `git diff --check` 从仓库根执行。验证结果以本次实际检查为准。

## 编码与文本处理规范
1. 文本读写使用 UTF-8；支持 `-Encoding` 的 PowerShell 文本命令显式写 `-Encoding UTF8`，其他工具使用其自身的编码选项，不附加不支持的参数
2. 读取文本时使用 `Get-Content -Encoding UTF8`；编辑现有文件优先使用 `apply_patch`，不要用整文件覆盖代替小范围修改
3. 禁止使用 `>` 和 `>>` 写入文本；确需由命令生成新文件时使用明确的 UTF-8 编码参数
4. 搜索文本如果使用 `Select-String`，以及处理 CSV 时使用 `Import/Export-Csv`，都必须带 `-Encoding UTF8`
5. 不依赖系统默认编码，不假设文件编码正确



## Git 推送默认规则

- 用户要求“推送”或“提交并推送”时，即授权将本次任务提交推送到当前本地分支已配置的远端跟踪分支，包括该分支所属仓库；不重复询问提交内容、仓库地址或目标分支。
- 推送前从 Git 读取当前分支、upstream 及对应远端地址，以实际配置为准；默认仅推送当前分支到其 upstream，不假设目标为 `origin/main`，不推送其他分支或标签。
- 当前为 detached HEAD、未配置 upstream 或目标配置无法确认时，说明缺失信息并仅询问需要的目标；不擅自设置远端或更换目标分支。
- 默认使用普通推送；遇到非快进拒绝时报告原因，不自动强制推送、rebase 或合并。
- 本节仅规定用户已要求推送时的默认目标与授权范围，不自动触发推送。
- 平台自动审批仍可能阻止推送；被拒绝时明确说明被拦截的操作及原因为何，并按平台要求处理，不绕过审批，也不把推送未完成报告为成功。

## Team Create 与 Script Sync 协作

- 当前项目直接在现有本地 checkout 中配合 Team Create + Script Sync 开发，不通过 Git worktree 并行开发，也不为任务创建或切换到额外 worktree。
- 完成修改和验证后汇报结果；提交和推送按用户明确请求处理。
- 不覆盖他人的未提交改动。遇到同一脚本的协作修改或 Script Sync 冲突，先说明冲突并询问用户，不猜测应保留哪一份。
