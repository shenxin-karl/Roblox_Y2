# 添加服务端玩家组件

位置：`ServerScriptService/Server/Player/SExampleCompClass.luau`。

```lua
local FX = _G.FX
local SExampleCompClass = FX.Class("SExampleCompClass", "FSPlayerCompClass")

--- 返回玩家内协作名。
--- @return string 组件名称。
function SExampleCompClass:GetCompName()
    return "SExampleComp"
end

--- 玩家档案就绪后执行登录相关业务。
function SExampleCompClass:OnPlayerLogin()
    -- 写入使用 PlayerDataConfig 中已声明的字段。
end

return SExampleCompClass
```

在 Main.server.luau 加载 Scripts/GameInit 完成框架初始化之后、玩家对象构造之前 require 此模块，
然后在 SPlayerObjectClass:Ctor 中 `self:AddComponent("SExampleCompClass")`。
取得组件用 `player:RequireComponent("SExampleComp")`。

协议只在玩家管理器或服务中注册一次，再通过已认证 userId 找组件；
不要在每位玩家的 Ctor 注册同名 RegClientMsgCallback。
日常开发不自动维护 Docs/功能验收清单.md；仅在用户明确调用 update-acceptance-checklist 时集中生成系统规则与数值条目清单。
