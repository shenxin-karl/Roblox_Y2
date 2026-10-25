-- 普通背包道具的手持图片；使用动作与特效由客户端播放。
local SItemToolVisual = {}

--- 复用道具图标制作双面卡片，透明握柄不遮挡图片，也不参与角色碰撞。
--- @param tool Tool 尚未放入背包的原生道具。
--- @param icon string ItemConfig.Display 中的图片 URI。
function SItemToolVisual.AddImageHandle(tool, icon)
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(1.5, 1.5, 0.08)
    handle.Transparency = 1
    handle.CanCollide = false
    handle.CanTouch = false
    handle.CanQuery = false
    handle.Massless = true
    handle.Parent = tool
    tool.RequiresHandle = true
    tool.Grip = CFrame.new(0, -0.55, 0)

    for index, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
        local surface = Instance.new("SurfaceGui")
        surface.Name = "CardImage" .. index
        surface.Face = face
        surface.CanvasSize = Vector2.new(256, 256)
        surface.LightInfluence = 0
        surface.Parent = handle

        local image = Instance.new("ImageLabel")
        image.Name = "Icon"
        image.BackgroundTransparency = 1
        image.Size = UDim2.fromScale(1, 1)
        image.Image = icon
        image.ScaleType = Enum.ScaleType.Fit
        image.Parent = surface
    end
end

return SItemToolVisual
