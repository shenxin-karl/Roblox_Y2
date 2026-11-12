local FX = _G.FX
local FXLoader = FX.Loader
local CWindowUIBaseCompClass = FX.Class("CWindowUIBaseCompClass", "FCUICompClass")

-- 关闭只影响当前模拟窗口，停止或重置恢复设计态。
function CWindowUIBaseCompClass:OnReady()
    local root = FXLoader:PlayerGui("MediumWindowUI")
    local titleBox = FXLoader:Here(root, "TitleBox")
    local panel = FXLoader:Here(root, "PopupPanelImg")
    local close = FXLoader:Here(root, "TitleBox.CloseSurfaceImg.CloseBtn")
    self:TrackConnection(close.Activated:Connect(function()
        titleBox.Visible = false
        panel.Visible = false
        self:EmitUIAction("Close", {})
    end))
end

return CWindowUIBaseCompClass