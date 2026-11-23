-- 金钱洒落：沿用 Y1 的金币数量和下落轨迹，复用当前项目的 HUD 图标。
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local FX = _G.FX
local FXLoader = FX.Loader
local UIRoot = FXLoader:RequireShared("Scripts.Framework.Client.FCUIRoot")

local MoneyRain = {}

--- 由领取成功的业务回调调用；每轮图标各自播放完毕并释放，连续领取不会截断上一轮。
function MoneyRain.Play()
    local template = FXLoader:PlayerGui("Main.HUD.Wallet.CashStat.Icon")
    local root = UIRoot.Get()
    local screenArea = GuiService:GetInsetArea(Enum.ScreenInsets.None)
    local screenSize = screenArea.Max - screenArea.Min
    local origin = root.AbsolutePosition
    local scale = math.min(screenSize.X / 1280, screenSize.Y / 720)
    for index = 1, 24 do
        local icon = template:Clone()
        icon.Name = "MoneyRain"
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        local start = screenArea.Min - origin + Vector2.new(
            math.random() * (screenSize.X - 80 * scale) + 40 * scale,
            -math.random(60, 420) * scale)
        icon.Position = UDim2.fromOffset(start.X, start.Y)
        local size = 64 * scale * math.random(65, 115) / 100
        icon.Size = UDim2.fromOffset(size, size)
        icon.Rotation = math.random(-45, 45)
        icon.Active = false
        icon.Interactable = false
        icon.Visible = true
        icon.ZIndex = 20
        icon.Parent = root

        local tween = TweenService:Create(icon,
            TweenInfo.new(math.random(150, 250) / 100, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.fromOffset(start.X + math.random(-100, 100) * scale,
                    screenArea.Max.Y - origin.Y + 100 * scale),
                Rotation = icon.Rotation + math.random(-240, 240),
            })
        --- 下落结束后释放当前轮的临时图标和补间。
        tween.Completed:Once(function()
            tween:Destroy()
            icon:Destroy()
        end)
        tween:Play()
    end
end

return MoneyRain
