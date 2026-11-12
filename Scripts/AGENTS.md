# Roblox_Y2 Game 工作区指南

## 项目与协作

- 你是一名 Roblox 游戏开发者；项目使用 Luau、FX/FC/FS 框架，通过 Team Create 与 Studio Script Sync 协作。
- 本文件中的相对路径以 `Scripts/` 为基准；Git 仓库根目录用 `git rev-parse --show-toplevel` 确认。
- 直接在现有 checkout 中开发，不创建或切换 Git worktree。不覆盖他人未提交的改动；同一脚本出现协作修改或 Script Sync 冲突时，说明冲突并询问用户。
- 完成修改和验证后汇报；提交、推送仅按用户明确请求执行。
- 除非用户明确要求编写或更新文档，否则不在 `Docs/` 及其子目录新增、修改或生成文档；开发、修复、验证和审查结果直接在回复中汇报。

## 必须始终遵守的边界

- `StarterPlayerScripts/Client/UI/Generated/` 及其子目录只读，禁止手工修改；对应界面的导出节点、隐藏原型及 View 管理的展示行为归 UIEditor 管理，结构或展示改动须回源。修改 UI 节点前按 [UI 归属与接入规则](.agents/skills/roblox-external-tools/references/ui-integration.md) 确认范围，不把所有 `StarterGui` 节点一概视为托管节点。
- `ReplicatedStorage/Scripts/Game/Configs/` 及自定义导出目录中的生成配置只读；按来源回源：XLSX 配置通过 GameKit 配置 MCP 检查、保存后导出；`NumericalConfig.luau` 从 `../SimulatorWorkspace/Data/config.json` 经模拟器校验、导出。来源不明先确认，失败时不临时修补生成文件。
- 不一次性读取 `ReplicatedStorage/Scripts/Game/Configs/` 或 `ReplicatedStorage/Scripts/Game/Shared/` 整个目录；先用 `rg` 定位，再读取最小必要片段。
- 普通项目开发通过现有 Provider、回调或项目子类接入框架；只有用户明确要求框架维护或迁移时，才修改授权范围内的框架实现。
- 玩家存档仅经公开接口访问，禁止绕过 PlayerKV 封装获取或修改底层 DB、原始表和会话内部状态；接口细则见框架 skill。
- 手工或 AI 制作的模型不得放入 `game.Workspace.BlockMeshs`、`game.ReplicatedStorage.Assets.BlockMeshs` 及其子目录或对应本地目录。
- 场景、模型和 UI 非脚本实例以 Studio 中的实际状态为准；外部编辑器制作的内容须经受支持流程导入，查询、修改或核验实际节点时使用 Studio 操作 skill，不把本地文件或动态创建代码当作实例已存在、已同步的证据。
- 未获用户明确测试或试玩授权，不运行 Lua/Luau 脚本或启动游戏；只读 MCP 查询可直接进行。

## 外部工具协作

- `Scripts/` 是游戏开发主入口，不是能力边界。涉及 UI 制作、方块模型、图片与模型资源、资产、配置或数值模拟时，主动读取 [外部工具协作](.agents/skills/roblox-external-tools/SKILL.md)，按任务选择 MCP，不要求用户跨工作区转述。
- 默认由当前 AI 在同一会话中串联工具和业务接入，不强制委派 subagent，不因跨工具自动创建新任务或切换工作区。外部工具的公共指南、技能与 API 从对应 MCP 按需读取，不复制到本地。
- 工具业务读写前核对实际目标工程；读取通用文档无需绑定工程，当前目录、编辑器窗口或读到工具说明都不证明业务目标已绑定。项目规则、文件访问权限与用户授权仍分别生效。

## 按任务读取技能

技能位于 `.agents/skills/`。先读对应 `SKILL.md`，再按任务读取所需参考；不要默认加载全部技能和参考。细则在对应技能中维护，不复制回本文件。

| 任务 | 技能与规则归属 |
| --- | --- |
| 框架接入、项目扩展、脚本命名与目录、入口与启动、玩家数据、组件、服务、协议 | [框架开发](.agents/skills/roblox-framework-dev/SKILL.md)；新增能力前先查复用索引 |
| 编写、重构、修复 Luau 或普通代码审查；FXLoader、数值文案、语法与同步验证 | [Luau 规范](.agents/skills/roblox-luau-standards/SKILL.md) |
| Studio 场景、存储或 UI 节点查询；模型存放；Script Sync 核验 | [Studio 操作](.agents/skills/roblox-studio-operations/SKILL.md) |
| 跨工作区调用 UIEditor、方块编辑器、GameKit 或模拟器；资源制作、资产、数值配置及导出接入 | [外部工具协作](.agents/skills/roblox-external-tools/SKILL.md)；只读对应工具参考 |
| 普通客户端 UI 组件、显隐与生命周期 | [UI 组件](.agents/skills/roblox-ui-components/SKILL.md) |
| UI 节点归属判定；`UI/Generated/` 中存在对应脚本的 UI 接入或排错 | [外部工具协作](.agents/skills/roblox-external-tools/SKILL.md) → [UI 归属与业务接入](.agents/skills/roblox-external-tools/references/ui-integration.md) |
| 动态文本、翻译定义、语言刷新、AutoLocalize 核验 | [本地化](.agents/skills/roblox-localization/SKILL.md) |
| XLSX 游戏配置分类、查询、修改、检查、保存与导出 | [外部工具协作](.agents/skills/roblox-external-tools/SKILL.md) → [XLSX 游戏配置](.agents/skills/roblox-external-tools/references/game-config.md) |
| 服务端安全、高危逻辑、存档或支付风险审查 | [服务端关键审查](.agents/skills/server-code-critical-review/SKILL.md) |
| 已明确需要协议、背包、商店、排行榜等具体接法示例 | [接入示例](.agents/skills/game-examples/SKILL.md) |
| 用户显式调用 `$checklist 更新` 或 `$checklist 验收` | [验收清单](.agents/skills/checklist/SKILL.md)；仅手动调用，不随日常开发自动维护 Docs |

## 文件与命令操作

- 文本读写显式使用 UTF-8。PowerShell 的 `Get-Content/Set-Content/Select-String/Import-Csv/Export-Csv` 使用 `-Encoding UTF8`；其他工具使用自身编码选项，不依赖系统默认编码。
- 编辑现有文件优先用 `apply_patch` 做局部修改；禁止用 `>`、`>>` 写文本。
- PowerShell 的正则、模式和 glob 参数优先用单引号，避免未引用的 `|`、`*`、括号等被解析。必要时用 `--%`。
- 检索先用 `rg -n --max-count <数量>` 定位，限定路径和文件类型；不默认输出上下文，不无范围使用 `rg -u/-uu/-uuu`。
- `git diff --check` 从仓库根执行；汇报以实际检查结果为准。

## Git 推送

- 用户要求“推送”或“提交并推送”，即授权推送本次任务到当前分支配置的 upstream；先从 Git 核对分支、upstream 和对应远端地址，不默认 `origin/main`，不推送其他分支或标签。
- detached HEAD、缺少 upstream 或目标无法确认时，只询问缺失的目标信息，不擅自设置远端或更换分支。
- 使用普通推送；非快进拒绝时报告原因，不自动强推、rebase 或合并。
- 自动审批拦截时，说明被拦截的操作及原因，不绕过审批，不将未完成的推送报告为成功。
