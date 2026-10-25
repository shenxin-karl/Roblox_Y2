# UI 组件骨架

以下骨架用于普通界面；UIEditor 界面按 [界面接入规则](reference-rules.md) 继承生成展示类。

这是待按需求创建的示例模板，不代表当前已有 ExampleUI。
先在 StarterGui 创建 ScreenGui `ExampleUI`（ResetOnSpawn=false），子节点 CloseBtn 为 TextButton；
通过 Roblox MCP 确认 StarterGui 模板的实际层级后才能用此骨架；需要检查运行时界面时查询客户端 PlayerGui。

```lua
local FX = _G.FX
local CExampleUICompClass = FX.Class("CExampleUICompClass", "FCUICompClass")

--- 接管已确认的玩家 UI 克隆，按钮只绑定一次。
--- @param owner table 本地玩家对象。
function CExampleUICompClass:Ctor(owner)
    CExampleUICompClass.Super.Ctor(self, owner)
    self._rootNode = FX.Loader:PlayerGui("ExampleUI")
    local closeButton = self._rootNode:WaitForChild("CloseBtn")
    self:TrackConnection(closeButton.Activated:Connect(function()
        self:Hide()
    end))
    self:Hide()
end

--- 返回组件协作名。
--- @return string 组件名。
function CExampleUICompClass:GetCompName()
    return "CExampleUIComp"
end

return CExampleUICompClass
```

在客户端玩家对象实例化之前 require 该模块；然后在 CPlayerObjectClass:Ctor 中
`self:AddComponent("CExampleUICompClass")`，或在实例化后显式挂载。
基类清理 TrackConnection 连接；这个示例引用模板克隆，不自行 Destroy 它。
若项目改为动态创建 ScreenGui，则组件拥有该实例并应在 Dtor 销毁。
