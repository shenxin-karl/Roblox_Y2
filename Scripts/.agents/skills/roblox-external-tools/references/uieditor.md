# UIEditor 项目接入

通用发现、授权和交付流程先读 [外部工具协作](../SKILL.md)；已有上下文时复用。

- 工作区：`../UIEditorWorkspace`；负责源 UI 节点、布局、展示契约和 Roblox 导出，不负责真实扣费、发奖等游戏业务。
- 文档入口逻辑名为 `uie.docs.read`，显式传入 `file: "AGENTS.md"`；真实客户端工具名通过发现确认。读取返回的 UI 制作技能及任务所需编码、本地化参考，不复制公共制作规范。
- 实际制作前读取工作区 `AGENTS.LOCAL.md`、`styles/Game-DESIGN.md`，按其指引读取风格专项技能和匹配模板。模板原件改动需有对应授权。
- 用工具状态核对 workspacePath、当前 UI 与最新 session/revision；不能因工作区名称正确就假定文档也正确。
- 节点通过 MCP 修改，不手改工程 JSON。只有工具指南允许且有文件访问权限时，才编辑源 `.view.luau`、`.example.luau`；模拟代码不进入真实业务。
- 按工具技能保存、检查并导出，核验最终回执和 Studio 节点、生成脚本。`awaiting_studio` 仅是中间状态；不以本地文件存在代替导入成功。
- Scripts 中 `UI/Generated/` 只读；节点是否由 UIEditor 管理、管理范围、业务接入和回源授权遵循本 skill 的 [UI 归属与业务接入](ui-integration.md)。完成回源后重读更新的 View 契约。
- 当前 AI 直接串联回源和接入，不强制委派；UIEditor 模拟、Studio 同步和真实游戏测试分别报告，测试须有授权。
