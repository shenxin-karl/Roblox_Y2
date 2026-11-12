-- 私人矿石呈现：仅将本人同步存档还原为本地节点，沿用现有标签和采矿特效。
local CollectionService = game:GetService("CollectionService")
local FX = _G.FX
local FXLoader = FX.Loader
local Settings = FXLoader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Rocks = {}
Rocks.__index = Rocks

--- 缓存配置中的模板；本地矿石不会复制给其他玩家。
--- @return table 当前玩家矿石呈现对象。
function Rocks.New()
    local self = setmetatable({}, Rocks)
    self._templates, self._rocks = {}, {}
    for id, rockType in pairs(_G.GameConfig.MiningRockData) do
        self._templates[id] = FXLoader:Shared(rockType.ModelPath)
    end
    self._folder = Instance.new("Folder")
    self._folder.Name = "PrivateMiningRocks"
    self._folder.Parent = FXLoader:Workspace("Decorations")
    return self
end

--- 同轮只更新采集次数；新轮整批替换，避免每次命中重建模型或重放变异。
--- @param data table 服务端同步的本人 MiningData。
function Rocks:Refresh(data)
    if self._deadline ~= data.NextRefresh then
        self._folder:ClearAllChildren()
        table.clear(self._rocks)
        self._deadline = data.NextRefresh
    end
    for id, state in pairs(data.Rocks) do
        local rock = self._rocks[id]
        if not rock and state.Hits > 0 then
            local config = _G.GameConfig.MiningRockData[state.Grade]
            rock = self._templates[state.Grade]:Clone()
            rock.Name = "Rock_" .. id
            rock:ScaleTo(rock:GetScale() * config.ModelScale)
            rock:PivotTo(CFrame.new(state.X, state.Y, state.Z) * CFrame.Angles(0, state.Angle, 0))
            for index, part in ipairs(rock:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Anchored = true
                    part.CanTouch = false
                end
            end
            rock:SetAttribute("MiningRockId", id)
            rock:SetAttribute("RockGrade", state.Grade)
            rock:SetAttribute("MutationId", state.MutationId)
            rock:SetAttribute("MaxHits", state.MaxHits)
            rock:SetAttribute("RemainingHits", state.Hits)
            self._rocks[id] = rock
            rock.Parent = self._folder
            CollectionService:AddTag(rock, Settings.RockTag)
        elseif rock then
            rock:SetAttribute("RemainingHits", state.Hits)
            if state.Hits == 0 then
                -- 先发布击碎终态供特效消费，隐藏本体直到下轮统一清理。
                for index, node in ipairs(rock:GetDescendants()) do
                    if node:IsA("BasePart") then
                        node.Transparency = 1
                        node.CanCollide = false
                        node.CanQuery = false
                    elseif node:IsA("Light") then
                        node.Enabled = false
                    end
                end
            end
        end
    end
end

--- 只销毁本组件创建的私人矿石，由标签移除通知现有特效释放连接。
function Rocks:Destroy()
    self._folder:Destroy()
    table.clear(self._rocks)
end

return Rocks
