# 新手引导接入

现有服务端 STutorialGuideCompClass 在 SPlayerObjectClass.luau 内定义并已挂载，
使用 TutorialGuideConfig 与 PlayerData.Guide。
当前 TutorialGuideConfig 为空。客户端只有 FCTutorialGuideCompClass 基类，尚未挂载项目引导表现。

按实际需求：
1. 复用业务成功事件，在 TutorialGuideConfig 中填写分组 DSL，不新增客户端“直接完成”权限。
2. 在客户端新增继承 FCTutorialGuideCompClass 的组件，覆盖 GetCompName/GetGuideConfig/GetGuideStorage。
3. 覆盖 OnEnterGuide/OnExitGuide；目标 DSL 由本项目的表现约定确定，不假设已有 UI 高亮框架。
4. require 后在 CPlayerObjectClass 挂载。基类 OnReady 订阅 Guide 字段，回放当前步骤。
5. 服务端真实业务成功后由玩家对象或组件 PublishEvent 推进步骤。
   当前引导匹配事件名，不读取事件参数作为条件，不把参数过滤能力写成已支持。

DSL 示例（需按业务新增，节点坐标也必须从实际场景确认）：

```lua
FirstLogin = {
    startEvent = "PlayerLogin",
    steps = {
        {
            finishEvent = "ExampleActionSucceeded",
            target = { type = "ExampleTarget" },
        },
    },
},
```

Guide 字段已为 table、Sync=true，默认含 activeGuideId/guideMap/target。
客户端的 target 仅用于表现；进度由服务器存档决定。
世界箭头调用 ShowGuideArrowToPosition(Vector3)，退出时 HideGuideArrow。
UI 高亮、遮罩和文案需要真实节点与需求。关闭、换步骤、重生、析构均清理表现，
不要在每帧重新创建箭头。
