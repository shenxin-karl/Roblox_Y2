# 框架 UI 接口

确认框使用已挂载的 FCCommonUIComp：

```lua
local FC = _G.FC
FC.PlayerObject:RequireComponent("FCCommonUIComp"):ShowConfirm({
    Desc = "Continue?",
    ConfirmBtnTxt = "Continue",
    CancelBtnTxt = "Cancel",
    ConfirmCB = OnConfirm,
})
```

OnConfirm 为业务回调；文案按项目本地化规则处理。

动画使用 `FC.UIAnim`：`Open(node, duration, callback)`、`Close(node, callback, duration)`，注意参数顺序不同。
