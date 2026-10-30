-- 本服基地管理器：管理占用、场景楼层与共享快照，不另建存档或玩家同步流程。
local FX = _G.FX
local CollectionService = game:GetService("CollectionService")
local FXLoader = FX.Loader
local Rules = _G.GameConfig.CommonConfig
local Manager = FX.Class("SBaseManagerClass")

--- 运行时关闭整层投影，避免方块编辑器重新导出后恢复模板中的阴影设置。
--- @param model Model 场景底层或服务端刚克隆的上层，包含槽位和圆环。
local function DisableShadows(model)
    for index, node in ipairs(model:GetDescendants()) do
        if node:IsA("BasePart") then
            node.CastShadow = false
        end
    end
end

--- 缓存原始碰撞属性；透明预览只由客户端处理。
--- @param model Model 单层基地。
--- @param assetFloor number 模板使用的槽位名称前缀，底层为 1，上层模板为 2。
--- @param floorIndex number 实际场景楼层。
--- @param baseId number 所属基地编号，供客户端筛选本人基地。
--- @return table 按全局槽位编号索引的碰撞缓存。
local function CacheSlots(model, assetFloor, floorIndex, baseId)
    local layout = FXLoader:Here(model, "DisplayLayout")
    local slots = {}
    for sideIndex, side in ipairs({"Left", "Right"}) do
        for index = 1, 5 do
            local slotId = (floorIndex - 1) * Rules.BaseSlotsPerFloor + (sideIndex - 1) * 5 + index
            local slotModel = FXLoader:Here(layout, string.format("F%d%s%d", assetFloor, side, index))
            local nodes = {}
            for nodeIndex, node in ipairs(slotModel:GetDescendants()) do
                if node:IsA("BasePart") then
                    nodes[node] = {
                        CanCollide = node.CanCollide,
                        CanTouch = node.CanTouch, CanQuery = node.CanQuery,
                    }
                end
            end
            slotModel:SetAttribute("SlotId", slotId)
            slotModel:SetAttribute("BaseId", baseId)
            CollectionService:AddTag(slotModel, "BaseDisplaySlot")
            slots[slotId] = {Model = slotModel, Nodes = nodes}
        end
    end
    return slots
end

--- 初始化现有地图底层；所有新建楼层和交互实例只放入 Decorations。
function Manager:Ctor()
    assert(Rules.BaseSlotsPerFloor == 10, "基地模板每层必须配置 10 个槽位")
    self._bases, self._owners = {}, {}
    self._upperTemplate = FXLoader:Shared("Assets.BlockMeshs.BaseUpper.BaseUpper")
    self._upperFloor = FXLoader:Here(self._upperTemplate, "Architecture.UpperFloor")
    local templateLowerFloor = FXLoader:Shared("Assets.BlockMeshs.BaseLower.BaseLower.Architecture.LowerFloor")
    self._floorHeight = templateLowerFloor.CFrame:ToObjectSpace(self._upperFloor.CFrame).Position.Y
    assert(self._floorHeight > 0, "基地楼层模板的地板高度不正确")
    for slotId = 1, Rules.BaseSlotsPerFloor * Rules.BaseMaxFloors do
        local config = _G.GameConfig.BaseSlotData[slotId]
        assert(config and config.UnlockPrice >= 0 and config.UnlockPrice < math.huge, "缺少有效基地槽位价格")
    end
    self._runtime = Instance.new("Folder")
    self._runtime.Name = "PlayerBases"
    self._runtime.Parent = FXLoader:Workspace("Decorations")
    local models = FXLoader:Workspace("BlockMeshs.bases"):GetChildren()
    --- 固定初始化顺序，不依赖场景返回子节点的顺序。
    --- @param left Model 左侧待比较基地。
    --- @param right Model 右侧待比较基地。
    --- @return boolean 左侧基地名称是否排在前面。
    table.sort(models, function(left, right)
        return left.Name < right.Name
    end)
    for index, model in ipairs(models) do
        local id = tonumber(string.match(model.Name, "^base(%d+)$"))
        assert(id and not self._bases[id], "地图基地编号必须唯一")
        local lower = FXLoader:Here(model, "BaseLower")
        DisableShadows(lower)
        local floor = {
            Model = lower, Part = FXLoader:Here(lower, "Architecture.LowerFloor"),
            Ring = FXLoader:Here(lower, "TeleportRing"), Slots = CacheSlots(lower, 1, 1, id),
        }
        self._bases[id] = {Id = id, OwnerUserId = 0, UnlockedSlotCount = 0, FloorCount = 1, Floors = {[1] = floor}}
        self:SetUnlockedSlots(floor, {})
    end
    self:Publish()
end

--- 按最小空闲编号分配；重复申请返回原基地，满员时由玩家组件等待后重试。
--- @param userId number 已完成玩家握手的 UserId。
--- @return table? 当前分配到的基地，无空位时返回 nil。
function Manager:Allocate(userId)
    if self._owners[userId] then
        return self._owners[userId]
    end
    local available
    for id, base in pairs(self._bases) do
        if base.OwnerUserId == 0 and (not available or id < available.Id) then
            available = base
        end
    end
    if not available then
        return nil
    end
    available.OwnerUserId = userId
    available.Runtime = Instance.new("Folder")
    available.Runtime.Name = "Base" .. available.Id
    available.Runtime:SetAttribute("BaseId", available.Id)
    available.Runtime:SetAttribute("OwnerUserId", userId)
    available.Runtime.Parent = self._runtime
    self._owners[userId] = available
    return available
end

--- 服务端按底层地板坐标克隆上层，保留基地朝向和模板内已有的单层高度。
--- @param base table 已分配的场景基地。
--- @param floorIndex number 需要生成的实际楼层，范围为 2 到配置上限。
--- @return table 新建楼层的场景与槽位缓存。
function Manager:CreateUpperFloor(base, floorIndex)
    local lower = base.Floors[1]
    local target = lower.Part.CFrame * CFrame.new(0, self._floorHeight * (floorIndex - 1), 0)
    local model = self._upperTemplate:Clone()
    model.Name = "Floor" .. floorIndex
    model:PivotTo(target * self._upperFloor.CFrame:ToObjectSpace(self._upperTemplate:GetPivot()))
    local ring = lower.Ring:Clone()
    ring:PivotTo(target * lower.Part.CFrame:ToObjectSpace(lower.Ring:GetPivot()))
    ring.Parent = model
    DisableShadows(model)
    local floor = {
        Model = model, Part = FXLoader:Here(model, "Architecture.UpperFloor"), Ring = ring,
        Slots = CacheSlots(model, 2, floorIndex, base.Id),
    }
    self:SetUnlockedSlots(floor, {})
    model:SetAttribute("FloorIndex", floorIndex)
    model.Parent = base.Runtime
    base.Floors[floorIndex] = floor
    return floor
end

--- 未解锁槽位不阻挡通行；服务端保持模板透明度，不向其他玩家同步透明预览。
--- @param floor table 已缓存的单层场景。
--- @param unlockedSlots table 以字符串槽位编号索引的已解锁集合。
function Manager:SetUnlockedSlots(floor, unlockedSlots)
    for slotId, slot in pairs(floor.Slots) do
        local unlocked = unlockedSlots[tostring(slotId)] == true
        if slot.Unlocked ~= unlocked then
            slot.Unlocked = unlocked
            slot.Model:SetAttribute("Unlocked", unlocked)
            for node, properties in pairs(slot.Nodes) do
                for property, original in pairs(properties) do
                    if unlocked then
                        node[property] = original
                    else
                        node[property] = false
                    end
                end
            end
        end
    end
end

--- 只同步可序列化的公开状态，不广播实例、连接、存档槽位内容或传送冷却。
function Manager:Publish()
    local states = {}
    for id, base in pairs(self._bases) do
        states[tostring(id)] = {
            OwnerUserId = base.OwnerUserId, UnlockedSlotCount = base.UnlockedSlotCount,
            FloorCount = base.FloorCount,
        }
    end
    FX.SyncManager:SetTable(_G.ServerDataConfig.Bases, states)
end

--- 玩家退出时仅删除本管理器创建的实例，地图底层保留供下一位玩家使用。
--- @param userId number 正在释放基地的 UserId。
function Manager:Release(userId)
    local base = self._owners[userId]
    if not base then
        return
    end
    base.Runtime:Destroy()
    base.Runtime = nil
    base.Floors = {[1] = base.Floors[1]}
    base.Floors[1].Trigger = nil
    self:SetUnlockedSlots(base.Floors[1], {})
    base.OwnerUserId, base.UnlockedSlotCount, base.FloorCount = 0, 0, 1
    self._owners[userId] = nil
    self:Publish()
end

--- 释放管理器自建场景，并恢复地图槽位原始碰撞属性。
function Manager:Dtor()
    local owners = table.clone(self._owners)
    for userId in pairs(owners) do
        self:Release(userId)
    end
    for id, base in pairs(self._bases) do
        local unlockedSlots = {}
        for slotId in pairs(base.Floors[1].Slots) do
            unlockedSlots[tostring(slotId)] = true
        end
        self:SetUnlockedSlots(base.Floors[1], unlockedSlots)
    end
    self._runtime:Destroy()
end

return Manager
