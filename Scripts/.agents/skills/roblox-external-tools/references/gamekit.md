# GameKit 项目接入

通用发现、授权和交付流程先读 [外部工具协作](../SKILL.md)；已有上下文时复用。

- 工作区：`../GameKitWorkspace`；服务为 StudioGameToolkit，负责生图、图片编辑与处理、生模型、Roblox 资产及 XLSX 配置等实际已暴露能力。
- 文档入口逻辑名为 `sgtk.docs.read`，显式传入 `file: "AGENTS.md"`，从摘要选择资源、资产或配置相关 skill。通过工具发现确认实际接口，不从本地缓存手册猜参数。
- 业务操作前核对当前工程、资源任务或工作簿身份；工具通用文档能读不代表已绑定此工作区。不要输出整个设置文件、凭据或无关资源数据。
- 图片、模型制作按服务 skill 处理输入、版本、任务状态和输出；付费生成先有明确授权，并按实际 schema 设置确认和数量限制。生成授权不自动包括 Roblox 上传、覆盖或发布。
- 制作完成、文件落盘、Roblox 上传、获得资产 ID、Studio 放置是不同阶段。接入脚本前核对最终资源引用及访问条件；节点存在与放置位置通过 Studio MCP 核验。
- 普通模型遵循 [Studio 模型存放规则](../../roblox-studio-operations/SKILL.md)，不写入方块编辑器专属 `BlockMeshs`。
- XLSX 查询、业务分类和编辑使用本 skill 的 [XLSX 游戏配置](game-config.md) 及其 [配置分类与组织](config-categories.md)；当前配置接口、检查、保存和导出细则从 MCP 读取。`NumericalConfig.luau` 不归 XLSX 工具管理，转 [模拟器](simulator.md)。
- 若入口返回未知工具或文档与实际服务不匹配，报告客户端工具清单与服务实现的接入问题。仅在当前服务明确提供、且能取得必要指南时评估旧接口；不自动猜用 `sgtk.api.read` 或旧参数，不通过直接修改 XLSX、生成文件或调用未公开后端绕过。
