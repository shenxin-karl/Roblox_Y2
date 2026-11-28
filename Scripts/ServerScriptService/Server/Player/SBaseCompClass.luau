-- 玩家基地组件：进度来自玩家档案，解锁、楼层克隆及圆环传送均由服务端裁定。
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local GameConfig = _G.GameConfig
local Rules = GameConfig.CommonConfig
local GameUtility = FX.Loader:RequireShared("Scripts.Game.Shared.GameUtility")
local ForgeSettings = FX.Loader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local MiningSettings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local WorkshopRules = FX.Loader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")
local WorkshopVisuals = FX.Loader:RequireShared("Scripts.Game.Shared.WorkshopVisuals")
local TranslationTexts = FX.Text.Define("BaseInteraction", {
    HomeUnavailable = "Your base is not ready yet. Please try again shortly.",
    SlotUnlocked = "Weapon slot {slot:int} unlocked!",
    SlotNotEnoughCash = "Not enough cash to unlock this slot. You need ${value}.",
    SlotUnlockFailed = "Couldn't unlock the weapon slot. Please try again.",
})
local Comp = FX.Class("SBaseCompClass", "FSPlayerCompClass")

--- 复制工坊设施原件的碰撞形状，碰撞体随档位外观一起清理。
--- @param source Instance 正在换下的设施零件或模型。
--- @param originals Folder 保存原件的离场容器。
--- @param collisions Folder 当前档位外观内的碰撞容器。
local function StashWorkshopOriginal(source, originals, collisions)
    local parts = source:GetDescendants()
    table.insert(parts, source)
    for index, part in ipairs(parts) do
        if part:IsA("BasePart") and part.CanCollide then
            local collision = part:Clone()
            collision:ClearAllChildren()
            collision.Transparency = 1
            collision.CastShadow = false
            collision.CanTouch = false
            collision.Parent = collisions
        end
    end
    source.Parent = originals
end

--- 持有本次玩家会话的基地与冷却，离服后不把它们写入存档。
--- @param owner table 当前服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._manager = _G.SBaseManager
    self._slotPrompts = {}
    self._lastTeleport, self._lastUnlock = -math.huge, -math.huge
end

--- 返回玩家对象内部的稳定协作名。
--- @return string 组件名称。
function Comp:GetCompName()
    return "SBaseComp"
end

--- 提供当前会话的基地，仅供服务端业务协作使用。
--- @return table? 已分配的场景基地。
function Comp:GetBase()
    return self._base
end

--- 存档与客户端握手完成后分配基地，同时接管后续角色重生定位。
function Comp:OnPlayerLogin()
    self._active = true
    --- 每次重生都使用当前会话的基地，不保留旧角色引用。
    --- @param character Model 平台刚创建的角色。
    self:TrackConnection(self:GetPlayerNode().CharacterAdded:Connect(function(character)
        self:PositionCharacter(character)
    end))
    --- 存档进度变化后统一刷新场景，回调不自行扣费或发奖。
    self:WatchDataChanged(Fields.BaseData, function()
        self:Refresh()
    end)
    --- 锻造和熔炉各自按等级更新，收益升级不会切换外观。
    self:WatchDataChanged(Fields.UpgradeWorkshop, function()
        self:RefreshWorkshopAppearance()
    end)
    self:TryAllocate()
end

--- 满员时保留原出生点，通过框架既有秒更新等待空位，不创建第二套轮询任务。
--- @param serverTime number 框架提供的服务器时间，此处不参与冷却计算。
function Comp:OnUpdate(serverTime)
    if self._active and not self._base then
        self:TryAllocate()
    end
end

--- 分配成功后恢复所有已解锁楼层；重复调用不会重复克隆或重复占用基地。
function Comp:TryAllocate()
    if self._base then
        return
    end
    self._base = self._manager:Allocate(self:GetPlayerId())
    if not self._base then
        return
    end
    self:RefreshWorkshopAppearance()
    self:SetNumber(Fields.BaseId, self._base.Id)
    self:BindRing(self._base.Floors[1], 1)
    self:Refresh()
    local character = self:GetPlayerNode().Character
    if character then
        self:PositionCharacter(character)
    end
end

--- 登录和升级时分别更新锻造台与熔炉的外观，地台跟随各自档位。
function Comp:RefreshWorkshopAppearance()
    if not self._active or not self._base then
        return
    end
    local workshop = ForgeSettings.FindPersonalWorkshop(self._base.Id)
    if not workshop then
        return
    end
    local upgrades = self:GetTableView(Fields.UpgradeWorkshop)
    local forgeTier = WorkshopVisuals.GetTier(WorkshopRules.GetLevel(upgrades.forge))
    local desktop = FX.Loader:Find(workshop, ForgeSettings.PersonalForgePart)
    if desktop and self._forgeTier ~= forgeTier then
        local station = desktop.Parent
        self:ClearForgeAppearance()
        self._forgeColors = WorkshopVisuals.ApplyColors(station, forgeTier, "Forge")
        local template = FX.Loader:Find(ReplicatedStorage, "Assets.Decorations.WorkshopTierVisuals.Forge." .. forgeTier)
        if template then
            local visual = template:Clone()
            visual:PivotTo(desktop.CFrame)
            local collisions = Instance.new("Folder")
            collisions.Name = "OriginalCollisions"
            collisions.Parent = visual
            self._forgeOriginal = Instance.new("Folder")
            for index, child in ipairs(station:GetChildren()) do
                if child ~= desktop and child.Name ~= "BlackHammer" and child.Name ~= "BlankDisplayBoard"
                    and child.Name ~= "ForgeTableCollision" then
                    StashWorkshopOriginal(child, self._forgeOriginal, collisions)
                end
            end
            self._forgeDesktopTransparency = desktop.Transparency
            desktop.Transparency = 1
            visual.Parent = station
            self._forgeDecoration = visual
        elseif forgeTier >= 5 then
            local template = FX.Loader:Find(ReplicatedStorage, "Assets.Decorations.ForgeDragonVisuals." .. forgeTier)
            if template then
                local decoration = template:Clone()
                decoration:PivotTo(desktop.CFrame)
                decoration.Parent = station
                self._forgeDecoration = decoration
            end
        end
        self._forgeStation, self._forgeTier = station, forgeTier
        station:SetAttribute("WorkshopVisualTier", forgeTier)
        local ground = desktop.CFrame.Rotation + station:GetPivot().Position
        local size = Vector2.new(desktop.Size.X + 1.6, desktop.Size.Z + 1.6)
        self._forgeFloor = WorkshopVisuals.CreateFloor(workshop, "ForgeVisualFloor", ground, size, forgeTier)
    end
    local furnaceTier = WorkshopVisuals.GetTier(WorkshopRules.GetLevel(upgrades.smelt))
    if self._furnaceTier ~= furnaceTier then
        self:RefreshFurnaceAppearance(workshop, furnaceTier)
    end
end

--- 归还互动桌面和原台架；升级、离线和基地转交复用同一套清理。
function Comp:ClearForgeAppearance()
    if self._forgeFloor then
        self._forgeFloor:Destroy()
        self._forgeFloor = nil
    end
    if self._forgeDecoration then
        self._forgeDecoration:Destroy()
        self._forgeDecoration = nil
    end
    local station = self._forgeStation
    if self._forgeOriginal then
        station.ThickSteelDesktop.Transparency = self._forgeDesktopTransparency
        for _, child in self._forgeOriginal:GetChildren() do
            child.Parent = station
        end
        self._forgeOriginal:Destroy()
        self._forgeOriginal, self._forgeDesktopTransparency = nil, nil
    end
    if self._forgeColors then
        WorkshopVisuals.RestoreColors(self._forgeColors)
        station:SetAttribute("WorkshopVisualTier", nil)
        self._forgeColors, self._forgeStation, self._forgeTier = nil, nil, nil
    end
end

--- 切换当前档位的炉体和地台，各档用相同的交互锚点。
--- @param workshop Model 基地的私人小工坊。
--- @param tier number 熔炉外观档位。
function Comp:RefreshFurnaceAppearance(workshop, tier)
    local hearth = FX.Loader:Find(workshop, ForgeSettings.PersonalFurnacePart)
    if not hearth then
        return
    end
    local tierTemplate = FX.Loader:Find(ReplicatedStorage, "Assets.Decorations.WorkshopTierVisuals.Furnace." .. tier)
    local template = tierTemplate
    local name = not template and WorkshopVisuals.GetFurnaceTemplateName(tier)
    if name then
        template = FX.Loader:Find(ReplicatedStorage, "Assets.Decorations.FurnaceVisuals." .. name)
        if not template or not template:IsA("Model") then
            return
        end
    end
    self:ClearFurnaceAppearance()
    local furnace = hearth.Parent
    local foundation = FX.Loader:Find(furnace, "SingleHearthFoundation")
    local groundY = hearth.Position.Y - hearth.Size.Y / 2
    if foundation then
        local ground = foundation.CFrame * CFrame.new(0, -foundation.Size.Y / 2, 0)
        groundY = ground.Position.Y
        local size = Vector2.new(foundation.Size.X + 2.1, foundation.Size.Z + 2.1)
        self._furnaceFloor = WorkshopVisuals.CreateFloor(workshop, "FurnaceVisualFloor", ground, size, tier)
    end
    local visual = furnace
    if template then
        visual = template:Clone()
        local pivot = hearth.CFrame
        if tierTemplate then
            pivot += Vector3.new(0, groundY - hearth.Position.Y, 0)
            self._furnaceHearth = hearth
            self._furnaceHearthTransparency = hearth.Transparency
            hearth.Transparency = 1
        end
        visual:PivotTo(pivot)
        local collisions = Instance.new("Folder")
        collisions.Name = "OriginalCollisions"
        collisions.Parent = visual
        self._furnaceOriginal = Instance.new("Folder")
        for _, child in furnace:GetChildren() do
            if child ~= hearth then
                StashWorkshopOriginal(child, self._furnaceOriginal, collisions)
            end
        end
        visual.Parent = furnace
        self._furnaceAppearance = visual
    end
    if not tierTemplate then
        self._furnaceColors = WorkshopVisuals.ApplyColors(visual, tier, "Furnace")
    end
    local source = FX.Loader:Find(visual, template and "FlameSource2" or "FlameSource_2") or hearth
    local origin = Instance.new("Attachment")
    origin.Name = "SmeltBurstOrigin"
    origin.Parent = source
    self._smeltHiss = Instance.new("Sound")
    self._smeltHiss.Name = "SteelHeating"
    self._smeltHiss.SoundId = "rbxassetid://122412603733067"
    self._smeltHiss.PlaybackSpeed = 1 / 0.65
    self._smeltHiss.Volume = 0.48
    self._smeltHiss.RollOffMaxDistance = 32
    self._smeltHiss.Parent = origin
    self._smeltBurst = WorkshopVisuals.CreateBurst(origin)
    self._smeltBurstCount = WorkshopVisuals.SetBurstStyle(self._smeltBurst, tier)
    self._furnaceTier = tier
end

--- 只有矿石交易成功后才在当前炉口播放出胚反馈。
function Comp:PlaySmeltEffect()
    if self._smeltBurst then
        self._smeltBurst:Emit(self._smeltBurstCount)
        self._smeltHiss:Play()
    end
end

--- 切换档位或释放地块时移除地台、归还原炉体，避免外观残留。
function Comp:ClearFurnaceAppearance()
    if self._furnaceFloor then
        self._furnaceFloor:Destroy()
        self._furnaceFloor = nil
    end
    if self._smeltBurst then
        self._smeltBurst.Parent:Destroy()
        self._smeltBurst = nil
        self._smeltHiss = nil
    end
    if self._furnaceColors then
        WorkshopVisuals.RestoreColors(self._furnaceColors)
        self._furnaceColors = nil
    end
    self._furnaceTier = nil
    if self._furnaceHearth then
        self._furnaceHearth.Transparency = self._furnaceHearthTransparency
        self._furnaceHearth, self._furnaceHearthTransparency = nil, nil
    end
    if not self._furnaceAppearance then
        return
    end
    local furnace = self._furnaceAppearance.Parent
    self._furnaceAppearance:Destroy()
    for _, child in self._furnaceOriginal:GetChildren() do
        child.Parent = furnace
    end
    self._furnaceOriginal:Destroy()
    self._furnaceAppearance, self._furnaceOriginal = nil, nil
end

--- 等待角色根节点后重新检查本次会话，防止旧角色或离服任务被传送。
--- @param character Model 平台创建的玩家角色。
function Comp:PositionCharacter(character)
    FX.Task:Cancel(self._spawnTask)
    local base = self._base
    if not base then
        return
    end
    --- 节点等待允许让出，返回后必须再次核对会话和角色。
    self._spawnTask = FX.Task:Spawn(function()
        local root = character:WaitForChild("HumanoidRootPart", 10)
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local player = self:GetPlayerNode()
        if not self._active or self._base ~= base or not player or player.Character ~= character
            or not root or not humanoid or humanoid.Health <= 0 then
            return
        end
        character:PivotTo(base.Floors[1].Part.CFrame * CFrame.new(0, 3.5, 0))
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    end)
end

--- 回家传送与楼层圆环共用节流，离开时释放占用的锻造台。
function Comp:ReturnHome()
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not self._active or not humanoid or humanoid.Health <= 0 or character:GetAttribute(MiningSettings.CarryAttribute)
        or not humanoid.RootPart or os.clock() - self._lastTeleport < 1.5 then
        return
    end
    self._lastTeleport = os.clock()
    if not self._base then
        self:GetPlayerObject():ShowLocalizedTips(TranslationTexts.HomeUnavailable)
        return
    end
    local forge = self:GetPlayerObject():GetComponent("SForgeComp")
    if forge then
        forge:Release()
    end
    humanoid.Sit = false
    self:PositionCharacter(character)
end

--- 在展示台中心创建原生交互点，实例归运行时容器，不改地图编辑器管理的模型。
--- @param slotId number 本交互点对应的全局槽位编号。
--- @param slot table 管理器缓存的展示台。
function Comp:CreateSlotPrompt(slotId, slot)
    local anchor = Instance.new("Part")
    anchor.Name = "UnlockPoint" .. slotId
    anchor.Size = Vector3.one
    anchor.Anchored, anchor.CanCollide, anchor.CanTouch, anchor.CanQuery = true, false, false, false
    anchor.Transparency = 1
    local bounds = slot.Model:GetBoundingBox()
    anchor.CFrame = CFrame.new(bounds.Position)
    anchor.Parent = self._base.Runtime
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "UnlockSlot"
    prompt.ActionText, prompt.ObjectText = "", ""
    prompt.AutoLocalize = false
    prompt.MaxActivationDistance, prompt.HoldDuration = 10, 0.35
    prompt.RequiresLineOfSight = false
    prompt:SetAttribute("OwnerUserId", self:GetPlayerId())
    prompt:SetAttribute("SlotId", slotId)
    prompt.Parent = anchor
    CollectionService:AddTag(prompt, "BaseUpgradePrompt")
    self._slotPrompts[slotId] = prompt
    --- 原生交互身份由引擎提供，业务资格仍在解锁入口复核。
    --- @param player Player 实际触发提示的玩家。
    self:TrackConnection(prompt.Triggered:Connect(function(player)
        if self._active and player == self:GetPlayerNode() then
            self:UnlockSlot(slotId)
        end
    end))
end

--- 服务端校验解锁资格，按余额或实际扣费结果反馈。
--- @param slotId number 由展示台交互回调固定的全局槽位编号。
--- @return boolean 是否成功解锁所选展示台。
function Comp:UnlockSlot(slotId)
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    if not self._active or not self._base or not root or humanoid.Health <= 0
        or os.clock() - self._lastUnlock < 0.5 then
        return false
    end
    local prompt = self._slotPrompts[slotId]
    if not prompt or not prompt.Enabled
        or (root.Position - prompt.Parent.Position).Magnitude > prompt.MaxActivationDistance then
        return false
    end
    self._lastUnlock = os.clock()
    local config = GameConfig.BaseSlotData[slotId]
    if not config or self:GetTable(Fields.BaseData).UnlockedSlots[tostring(slotId)] then
        return false
    end
    local costs = {}
    local playerObject = self:GetPlayerObject()
    if config.UnlockPrice > 0 then
        if self:GetNumber(Fields.Money) < config.UnlockPrice then
            playerObject:ShowLocalizedTips(TranslationTexts.SlotNotEnoughCash,
                {value = GameUtility.NumberToText(config.UnlockPrice)})
            return false
        end
        costs = {{Type = "Money", Currency = "Money", Count = config.UnlockPrice}}
    end
    local success = self:RequireComponent("FSRewardComp"):ExchangeRewards(costs,
        {{Type = "BaseSlotUnlock", SlotId = slotId}})
    playerObject:ShowLocalizedTips(success and TranslationTexts.SlotUnlocked or TranslationTexts.SlotUnlockFailed,
        success and {slot = slotId} or nil)
    return success
end

--- 在圆环中央生成服务端触碰区，落点远离圆环，避免到达后立即来回传送。
--- @param floor table 场景单层缓存。
--- @param floorIndex number 当前圆环所属楼层。
function Comp:BindRing(floor, floorIndex)
    local bounds = floor.Ring:GetBoundingBox()
    local trigger = Instance.new("Part")
    trigger.Name = "TeleportTrigger" .. floorIndex
    trigger.Size = Vector3.new(5, 4, 5)
    trigger.CFrame = CFrame.new(bounds.Position) * floor.Part.CFrame.Rotation * CFrame.new(0, 2, 0)
    trigger.Anchored, trigger.CanCollide, trigger.CanTouch, trigger.CanQuery = true, false, true, false
    trigger.Transparency = 1
    trigger:SetAttribute("FloorIndex", floorIndex)
    trigger.Parent = self._base.Runtime
    floor.Trigger = trigger
    floor.Arrival = trigger.CFrame * CFrame.new(0, 1, -6)
    --- 将源楼层固定在服务端闭包中，不接收客户端目标位置。
    --- @param hit BasePart 引擎报告的接触部件。
    self:TrackConnection(trigger.Touched:Connect(function(hit)
        self:TryTeleport(hit, floorIndex)
    end))
end

--- 只接受基地主人的真实角色触碰，在已生成的楼层之间按顺序循环传送。
--- @param hit BasePart 引擎报告的触碰部件，不信任客户端提供的目标楼层。
--- @param floorIndex number 服务端绑定的源楼层。
function Comp:TryTeleport(hit, floorIndex)
    local base = self._base
    local player = self:GetPlayerNode()
    local character = player and player.Character
    if not self._active or not base or base.FloorCount < 2 or not character or not hit:IsDescendantOf(character)
        or os.clock() - self._lastTeleport < 1.5 then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    local floor = base.Floors[floorIndex]
    if not root or humanoid.Health <= 0 or not floor then
        return
    end
    local position = floor.Trigger.CFrame:PointToObjectSpace(root.Position)
    if math.abs(position.X) > 3.5 or math.abs(position.Y) > 5 or math.abs(position.Z) > 3.5 then
        return
    end
    local target = base.Floors[floorIndex % base.FloorCount + 1]
    self._lastTeleport = os.clock()
    character:PivotTo(target.Arrival)
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
end

--- 本层买满后生成下一层预览；登录恢复与进度重置共用此入口。
function Comp:Refresh()
    local base = self._base
    if not base then
        return
    end
    local data = self:GetTable(Fields.BaseData)
    local count = data.UnlockedSlotCount
    assert(count % 1 == 0 and count >= 1 and count <= Rules.BaseSlotsPerFloor * Rules.BaseMaxFloors, "基地存档槽位数量越界")
    local floorCount = math.min(math.floor(count / Rules.BaseSlotsPerFloor) + 1, Rules.BaseMaxFloors)
    if floorCount < base.FloorCount then
        local character = self:GetPlayerNode().Character
        if character then
            self:PositionCharacter(character)
        end
    end
    for floorIndex = Rules.BaseMaxFloors, floorCount + 1, -1 do
        local floor = base.Floors[floorIndex]
        if floor then
            for slotId in pairs(floor.Slots) do
                self._slotPrompts[slotId].Parent:Destroy()
                self._slotPrompts[slotId] = nil
            end
            floor.Trigger:Destroy()
            floor.Model:Destroy()
            base.Floors[floorIndex] = nil
        end
    end
    for floorIndex = 1, floorCount do
        local floor = base.Floors[floorIndex]
        if not floor then
            floor = self._manager:CreateUpperFloor(base, floorIndex)
            self:BindRing(floor, floorIndex)
        end
        self._manager:SetUnlockedSlots(floor, data.UnlockedSlots)
        for slotId, slot in pairs(floor.Slots) do
            if not self._slotPrompts[slotId] then
                self:CreateSlotPrompt(slotId, slot)
            end
            self._slotPrompts[slotId].Enabled = not slot.Unlocked
        end
    end
    base.UnlockedSlotCount, base.FloorCount = count, floorCount
    base.Runtime:SetAttribute("UnlockedSlotCount", count)
    base.Runtime:SetAttribute("FloorCount", floorCount)
    self._manager:Publish()
end

--- 清理工坊外观与出生等待任务后释放场景，解锁进度由框架保存。
function Comp:OnPlayerLogout()
    self._active = false
    FX.Task:Cancel(self._spawnTask)
    self:ClearFurnaceAppearance()
    self:ClearForgeAppearance()
    self._manager:Release(self:GetPlayerId())
    self._slotPrompts = {}
    self._base = nil
end

--- 同时覆盖非正常销毁路径，清理连接并保证基地释放可重复调用。
function Comp:Dtor()
    self:OnPlayerLogout()
    Comp.Super.Dtor(self)
end

return Comp
