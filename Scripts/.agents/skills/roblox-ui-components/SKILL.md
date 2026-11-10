---
name: roblox-ui-components
description: 开发 Roblox_Y2 普通客户端 UI 组件及通用显隐、生命周期接入；UIEditor 托管节点和生成界面改用 roblox-external-tools 的 UI 归属与业务接入参考。
---

# Roblox UI 组件

- 接入前读取 [界面来源与生命周期](reference-rules.md)。
- 先按 [外部工具协作](../roblox-external-tools/SKILL.md) 中的 [UI 归属与业务接入](../roblox-external-tools/references/ui-integration.md) 判断是否由 UIEditor 托管；有对应生成 View 时沿该参考接入，不套用普通组件示例重写展示层。
- 普通 UI 组件需要骨架时读取 [组件示例](reference-examples.md)。
- 确认框和 UI 动画接口见 [常用接法](reference-cheatsheet.md)。
- 商店购买按 [game-examples](../game-examples/SKILL.md) 的商店参考接入。
