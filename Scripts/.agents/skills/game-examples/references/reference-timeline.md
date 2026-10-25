# 动画接口

- UI 动画使用 `FC.UIAnim`（FCUIAnim.luau）：Open/Close、Move、FadeIn/FadeOut、Shake/Pulse、Progress，调用参数以实现为准。
- 场景动画组件：`ReplicatedStorage/Scripts/Framework/Shared/Object/FXModelAnimationCompClass.luau`。
- 播放任务由所属组件管理，隐藏或析构时取消；序列控制按实际需求接入。
