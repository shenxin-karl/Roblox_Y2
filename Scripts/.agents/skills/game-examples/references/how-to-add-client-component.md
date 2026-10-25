# 添加客户端玩家组件

位置：`StarterPlayerScripts/Client/Player/CExampleCompClass.luau`。
UI 业务组件放 Client/UI，按 [UI 接入规则](../../roblox-ui-components/reference-rules.md) 选择父类。

```lua
local FX = _G.FX
local CExampleCompClass = FX.Class("CExampleCompClass", "FCPlayerCompClass")

--- 返回业务协作名。
--- @return string 组件名称。
function CExampleCompClass:GetCompName()
    return "CExampleComp"
end

--- 握手完成后执行需要初始玩家数据的逻辑。
function CExampleCompClass:OnReady()
    -- 按明确需求读取或订阅配置中已声明且 Sync=true 的字段。
end

return CExampleCompClass
```

在 Main.local.luau 加载 Scripts/GameInit 完成框架初始化之后、创建 PlayerClass.New 之前 require 业务模块（UIEditor 界面由业务模块先加载对应生成展示类），
然后在 `Client/Player/CPlayerObjectClass.luau` 的 Ctor 挂载：
`self:AddComponent("CExampleCompClass")`。

若覆盖 Ctor/Dtor 调用 Super。订阅连接用 TrackConnection；
FX 网络注册是每客户端协议唯一回调，需要 Dtor 解除。任务与自建节点单独清理。
