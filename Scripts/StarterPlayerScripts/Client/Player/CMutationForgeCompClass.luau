-- 变异熔炉的常驻客户端动画，和商人的交互及变异请求独立。
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local FX = _G.FX
local Comp = FX.Class("CMutationForgeCompClass", "FCPlayerCompClass")
local ForgeTag = "MutationForgeAnimation"
local Turn = 2 * math.pi

--- 炉体整体流入后记录初始姿势，连接随客户端玩家组件释放。
--- @param owner CPlayerObjectClass 当前客户端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    local function track(machine)
        local blade, ring, catalyst = machine.FloatingBlade, machine.EnergyRing, machine.Catalyst
        local light = machine.ChamberGlow:FindFirstChildOfClass("PointLight")
        self._forge = {Machine = machine, Blade = blade, BladeRest = blade:GetPivot(),
            Ring = ring, RingRest = ring:GetPivot(), Catalyst = catalyst, CatalystRest = catalyst:GetPivot(),
            Light = light, Brightness = light.Brightness}
    end
    self:TrackConnection(CollectionService:GetInstanceAddedSignal(ForgeTag):Connect(track))
    self:TrackConnection(CollectionService:GetInstanceRemovedSignal(ForgeTag):Connect(function(machine)
        if self._forge and self._forge.Machine == machine then
            self._forge = nil
        end
    end))
    local machine = CollectionService:GetTagged(ForgeTag)[1]
    if machine then
        track(machine)
    end
    self:TrackConnection(RunService.PreRender:Connect(function()
        local forge = self._forge
        if not forge then
            return
        end
        local time = workspace:GetServerTimeNow() % 120
        local wave = math.sin(time * Turn / 4)
        forge.Blade:PivotTo(forge.BladeRest * CFrame.new(0, 0.48 * wave, -0.46)
            * CFrame.Angles(0, 0.1 * wave, 0.2 * math.sin(time * Turn / 6)))
        forge.Ring:PivotTo(forge.RingRest * CFrame.Angles(0, 0, time * Turn / 12))
        forge.Catalyst:PivotTo(forge.CatalystRest * CFrame.new(0, 0.34 + 0.24 * wave, 0)
            * CFrame.Angles(0, time * Turn / 5, 0))
        forge.Light.Brightness = forge.Brightness * (1 + 0.35 * wave)
    end))
end

--- 释放组件时还原仍在场景中的装饰件。
function Comp:Dtor()
    Comp.Super.Dtor(self)
    local forge = self._forge
    if forge and forge.Machine.Parent then
        forge.Blade:PivotTo(forge.BladeRest)
        forge.Ring:PivotTo(forge.RingRest)
        forge.Catalyst:PivotTo(forge.CatalystRest)
        forge.Light.Brightness = forge.Brightness
    end
end

return Comp
