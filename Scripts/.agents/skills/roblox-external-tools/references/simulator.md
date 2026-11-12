# 模拟器项目接入

通用发现、授权和交付流程先读 [外部工具协作](../SKILL.md)；已有上下文时复用。

- 工作区：`../SimulatorWorkspace`；服务为 GameSimulator，负责数值源配置、玩法模拟及数值配置导出，不替代 XLSX 配置工具。
- 文档入口逻辑名为该服务的 `docs.read`，显式传入 `file: "AGENTS.md"`；从摘要按任务选择配置、项目代码或结构技能，再按需读参考。不要与其他服务的同名入口混用。
- 本项目数值源为 `../SimulatorWorkspace/Data/config.json`；游戏生成结果为 `ReplicatedStorage/Scripts/Game/Configs/NumericalConfig.luau`，对应 Studio 中 `game.ReplicatedStorage.Scripts.Game.Configs.NumericalConfig` 配置 ModuleScript。涉及该节点内容、字段、数值、曲线或公式的修改都先回本工具；它不是场景模型，也不代表模拟器管理所有配置节点。用户所说的 numericconfig 先核对实际文件，不另造同名配置。
- 修改字段、曲线或公式前，同时读取源配置相关片段与游戏消费代码，确认字段类型、单位、ID、边界和导出语义。玩法实现变化另读相关 `Code/` 与项目设计，不批量加载整个项目。
- 业务操作按接口要求核对当前项目或显式 workspaceDir。源配置通过工具指南允许的方式修改；需要文件写入时取得该工作区访问权限，不把项目文件路径传给只读文档接口。
- 校验并保存源配置后，使用实际暴露的确定性导出接口，确认目标路径、输出内容与工具返回的状态；禁止手改 `NumericalConfig.luau`，也不让 XLSX 导出覆盖它。
- 配置修改和导出不自动授权玩法测试、长期模拟或全局数值校准；未获授权只做允许的只读核对和静态检查，所需运行验证单列待确认。
- 导出后只读核验本次字段的本地生成结果与 Studio Script Sync；源配置校验、导出成功、同步成功和实际玩法结果分别报告。不重写模拟器框架，也不复制公共 API 或 skill 到工作区。
