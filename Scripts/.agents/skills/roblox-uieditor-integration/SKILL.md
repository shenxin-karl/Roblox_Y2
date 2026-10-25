---
name: roblox-uieditor-integration
description: 接入或排查 UIEditor 生成的 Roblox UI；UI/Generated 中存在界面对应脚本即适用。按 View 契约接入，能力不足时经用户授权委派 subagent 修改源 UI 并通过 MCP 导出到 Roblox。
---

# UIEditor 生成 UI 接入

## 界面来源判定

- `StarterPlayerScripts/Client/UI/Generated/`（简称 `UI/Generated/`）中存在该界面对应脚本，就判定为 UIEditor 生成的 UI，使用本 skill；不要求额外生成标记或其他来源证明。
- 没有对应脚本时，按 [普通 UI 组件](../roblox-ui-components/SKILL.md) 接入。已有证据表明生成脚本缺失或对应关系不清时，先说明并核对，不另写一套展示实现。
- ScreenGuiName 和 Roblox MCP 节点查询用于核对具体界面及接入路径，不作为额外的生成来源判定条件。

## 先确认契约

- 只读查看完整契约，沿父类链核对实际实现：Config/State 的结构与默认值、稳定业务 ID、初始化及刷新顺序、动作与 payload、扩展点、清理责任。
- 特别检查已有事件绑定、按钮文案/颜色/点击许可及其优先级、pending 和失败恢复。不能只参考旧接入或模拟脚本。
- 实现前简述项目提供的数据、处理的动作、使用的扩展点，以及 View 已负责的行为；契约歧义或与实现不符时先说明。

## 只接业务，不重做展示

| View 与公共展示基类 | 项目业务子类 |
| --- | --- |
| 节点、事件绑定、列表克隆与清理、状态到文案/颜色/图标/点击许可的映射、展示翻译、适配与动画 | 真实数据转换与订阅、业务请求、防重、权威结果及业务提示、按契约调用显隐和刷新 |

- 业务子类继承对应 View，放在 Generated 外，只挂载业务子类；在客户端玩家对象创建前加载，保留必要的父生命周期调用。
- 首次刷新前准备完整数据，沿实际初始化链调用 BindUIData/Render；不假设自动执行。后续按契约刷新。
- 通过 OnUIAction 和明确声明的扩展点接入，不重复绑定按钮或滑杆；请求防重同步到契约中的 pending，成功、失败均恢复并刷新。
- 资格、视觉状态与点击许可按契约分别表达。例如“置灰但可点击提示原因”必须由 View 支持，不伪造余额或等级来实现。
- 不覆写 Render、RenderButton、SetButtonEnabled、EmitUIAction 来替换或拦截原行为，不在父方法执行后再次写其管理的属性。声明的扩展点只用于约定用途。
- 数量格式化通过契约开放的方法接入项目 GameUtility；AutoLocalize 沿用生成内容，不加运行时开关。业务提示及交付属性核验遵循 [本地化规则](../roblox-localization/SKILL.md)。

## 复用 View 的翻译

- 沿 View 和基类核对文案来源、翻译调用及接口输入/输出；已有正确翻译的不再声明相同文案，也不另写一套状态到译文的映射。
- 优先复用契约开放的文案/格式化方法及其翻译结果；传入接入回调的文字也可能已翻译，例如 RenderButton 的 label。译文直接使用，不再交给 Text.Tr/TrSource，不按 `"Claim"` 等英文原文重新匹配或替换。
- 输入按契约传原文、定义、参数或译文，不把“已经翻译的字符串”传给还会执行 TrSource 的字段；业务判断使用稳定 ID/状态，不能依赖当前语言的显示文字。语言刷新沿用 View 机制，不缓存译文绕过刷新。
- 只有项目新增且不归 View 处理的业务文案才按本地化 skill 声明。View 翻译缺失、错误或接口无法表达需求时走下述回源改造，不在子类覆盖补译。

## View 不足：获授权后回源改造

1. 暂停受影响部分，说明具体 View/方法、当前与预期行为、所缺契约和改造范围，获得用户确认后再修改。用户已明确要求本次 UI 改造时可直接执行；仅要求接入或排查不等于授权改造。公共基类影响其他 UI 或需要扩大范围时另行确认。
2. 委派 subagent 在 `Scripts/` 的 `../UIEditorWorkspace` 工作区处理源 UI，不创建额外 Git worktree。交接：授权范围、界面身份及对应 View、当前/预期行为、所需数据与动作、兼容要求、目标 Studio。主 agent 不同时编辑同一源文件或操作同一编辑器会话。
3. subagent 先读取该工作区 `AGENTS.md`、`AGENTS.LOCAL.md`，按其指引加载 UI 制作技能及本次相关契约、编码和本地化规范；不复制制作细则到本项目。规范源由 UIEditor 的 `ProjectTypes/Roblox` 维护，不在本任务修改。
4. 通过 MCP 发现当前打开工作区接口，打开并核对目标工程；用 `uie.editor.get_state` 的 workspacePath 和工程身份确认确为上述目录。按实际能力打开对应 UI，不误改其他工程、模板或脏文档。
5. 在工作区源文件修复 View、必要节点和契约；交互与模拟代码可按工作区规范编辑 `.view.luau`、`.example.luau`，节点通过 MCP 修改，不直接改工程 JSON。同步模拟接入，验证本次状态和动作，保存并重开核对。模拟逻辑不进入游戏业务。
6. 由 AI 调用 `uie.document.export` MCP 导出到 Roblox；导出前确认当前 UI、编辑态和唯一目标 Studio，先保存源 UI。不以写本地文件或要求用户手动导入替代 MCP。检查目标和任务回执，`awaiting_studio` 不是成功；用 Roblox MCP 核对导入后的节点、生成脚本及内容，场景是否已保存另行说明。
7. subagent 返回源文件及契约变更、实际验证、导出目标/回执和待确认项。主 agent 重读更新后的 View，核对本地 Script Sync 与 Studio 内容后再继续业务接入；不同步或冲突时停止，不覆盖任一侧。

Generated、框架和导入元数据不得手工修补；生成内容只能经源 UI 改造及 MCP 导出更新。委派或 MCP 能力不可用、验证或导出失败时报告阻断，不改用子类旁路。

## 交付检查

- 核对数据、动作、pending、初始化与清理；确认没有父子两套展示规则、重复事件和二次翻译。已有绕过仅在本次授权范围内迁移，不能删掉有意保留的业务差异。
- 按项目规则做 Luau 语法验证和 Roblox MCP 只读同步核验；文本节点、隐藏原型及祖先 AutoLocalize 按本地化 skill 核验。
- 分别报告 UIEditor 模拟、MCP 导出、Studio/Script Sync 核对与真实游戏测试结果。UIEditor 模拟不代表游戏业务验证；未获试玩授权不启动 Roblox 游戏。
