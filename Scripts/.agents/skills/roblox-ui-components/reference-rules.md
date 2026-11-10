# 界面接入

- `StarterPlayerScripts/Client/UI/Generated/` 中有界面对应脚本，就属于 UIEditor 生成的 UI，不要求额外生成标记。实际节点与托管范围按 [UI 归属与业务接入](../roblox-external-tools/references/ui-integration.md) 确认；节点查询按 [Studio 操作](../roblox-studio-operations/SKILL.md)。
- 有对应生成 View 时使用 [外部工具协作](../roblox-external-tools/SKILL.md) 的 UI 接入参考；契约、职责边界与回源改造流程只在该参考维护。
- 无对应生成类的普通界面使用 FCUICompClass 或已有项目 UI 基类。

# UI 生命周期

- 普通组件提供 GetCompName 和 _rootNode，或覆盖 GetRootNode；附加显隐行为使用 OnShow/OnHide，Show 不重复绑定事件。
- 数据订阅和组件清理遵循 [框架规则](../roblox-framework-dev/reference-rules.md)；网络回调用 UnRegServerMsgCallback 解除。
- 模板克隆与组件自建实例区分所有权。长生命周期界面使用 ResetOnSpawn=false，或明确处理重生后的重新绑定。
