local FX = _G.FX
local FXLoader = FX.Loader
local CCloseButtonUIBaseCompClass = FX.Class("CCloseButtonUIBaseCompClass", "FCUICompClass")

-- 独立模板只发出关闭动作，窗口宿主决定关闭范围。
function CCloseButtonUIBaseCompClass:OnReady()
    local root = FXLoader:PlayerGui("CloseButtonUI")
    local close = FXLoader:Here(root, "CloseSurfaceImg.CloseBtn")
    self:TrackConnection(close.Activated:Connect(function()
        self:EmitUIAction("Close", {})
    end))
end

return CCloseButtonUIBaseCompClass