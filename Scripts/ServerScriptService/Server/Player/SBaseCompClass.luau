-- 玩家基地组件：进度来自玩家档案，解锁、楼层克隆及圆环传送均由服务端裁定。
local CollectionService = game:GetService("CollectionService")
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local GameConfig = _G.GameConfig
local Rules = GameConfig.CommonConfig
local Comp = FX.Class("SBaseCompClass", "FSPlayerCompClass")

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
    self:SetNumber(Fields.BaseId, self._base.Id)
    self:BindRing(self._base.Floors[1], 1)
    self:Refresh()
    local character = self:GetPlayerNode().Character
    if character then
        self:PositionCharacter(character)
    end
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

--- 回家与楼层圆环共享节流，仅允许存活角色返回本人已分配的基地。
function Comp:ReturnHome()
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not self._active or not self._base or not humanoid or humanoid.Health <= 0
        or not humanoid.RootPart or os.clock() - self._lastTeleport < 1.5 then
        return
    end
    self._lastTeleport = os.clock()
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

--- 服务端重新校验本人角色、距离与节流，金币和解锁进度由奖励框架一起提交。
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
    if config.UnlockPrice > 0 then
        costs = {{Type = "Money", Currency = "Money", Count = config.UnlockPrice}}
    end
    return self:RequireComponent("FSRewardComp"):ExchangeRewards(costs, {{Type = "BaseSlotUnlock", SlotId = slotId}})
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

--- 取消出生等待任务并释放场景占用，玩家解锁进度仍由框架保存。
function Comp:OnPlayerLogout()
    self._active = false
    FX.Task:Cancel(self._spawnTask)
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
