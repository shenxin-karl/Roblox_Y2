-- 初始槽位剑：在线积累、靠近领钱与升级由服务端裁定，持久化沿用 BaseData。
local CollectionService = game:GetService("CollectionService")
local FX = _G.FX
local FXLoader = FX.Loader
local Fields = _G.PlayerDataConfig
local Rules = FXLoader:RequireShared("Scripts.Game.Shared.SwordRules")
local SwordHandle = FXLoader:Shared("Assets.Decorations.Sword.ClassicSword.Handle")
local Comp = FX.Class("SSlotSwordCompClass", "FSPlayerCompClass")

--- 持有本次会话的显示与节流，不保存实例或离线计时戳。
--- @param owner table 当前服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._lastUpgrade = -math.huge
end

--- 返回玩家组件协作名称。
--- @return string 槽位剑组件名。
function Comp:GetCompName()
    return "SSlotSwordComp"
end

--- 首次赠剑由奖励框架提交；角色重生不走赠送入口。
function Comp:OnPlayerLogin()
    self._active = true
    self:RequireComponent("FSRewardComp"):AddRewards({{Type = "StarterSlotSword"}})
    self:WatchDataChanged(Fields.BaseId, function()
        self:EnsureDisplay()
    end)
    self:WatchDataChanged(Fields.BaseData, function()
        self:Publish()
    end)
end

--- 为现有牌子和绿区创建透明展示锚点，不修改地图编辑器管理的实例。
--- @param source BasePart 已核对的地图显示面。
--- @param name string 运行时锚点名称。
--- @return Part 本组件拥有的透明锚点。
function Comp:CreateAnchor(source, name)
    local part = Instance.new("Part")
    part.Name, part.Size, part.CFrame = name, source.Size, source.CFrame
    part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
    part.Transparency = 1
    part.Parent = self._display
    return part
end

--- 等待基地分配后展示第一槽的剑，只克隆外观 Handle，不克隆资源附带脚本或 Tool。
function Comp:EnsureDisplay()
    local base = self:RequireComponent("SBaseComp"):GetBase()
    if not self._active or not base or self._display or not self:GetSword() then
        return
    end
    local slot = base.Floors[1].Slots[1]
    local standard = FXLoader:Here(slot.Model, "StandardDisplay")
    local top = FXLoader:Here(standard, "DisplayTop")
    self._display = Instance.new("Model")
    self._display.Name = "SlotSword1"
    self._display.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
    self._display:SetAttribute("OwnerUserId", self:GetPlayerId())
    local sword = SwordHandle:Clone()
    sword.Name = "Sword"
    sword.Anchored, sword.CanCollide, sword.CanTouch, sword.CanQuery = true, false, false, false
    sword.CFrame = top.CFrame * CFrame.new(0, top.Size.Y / 2 + sword.Size.Z / 2 + 0.5, 0)
        * CFrame.Angles(math.pi / 2, 0, 0)
    sword.Parent = self._display
    self._sign = self:CreateAnchor(FXLoader:Here(standard, "InformationSign.WritingFace"), "UpgradeSign")
    -- SurfaceGui 按钮依赖可查询面；略微前移，避免原牌子挡住点击射线。
    self._sign.CanQuery = true
    self._sign.CFrame *= CFrame.new(0, 0, -0.03)
    self._collect = self:CreateAnchor(FXLoader:Here(standard, "GreenButton"), "CollectArea")
    self._display.Parent = base.Runtime
    self._lastIncome = os.clock()
    self:Publish()
    CollectionService:AddTag(self._display, "SlotSwordDisplay")
end

--- 只处理本功能拥有的剑数据，保留槽位未来可能存放的其他物品。
--- @return table? 第一槽当前剑的存档副本。
function Comp:GetSword()
    local sword = self:GetTable(Fields.BaseData).SlotData["1"]
    if sword and sword.WeaponId == "StarterSword" then
        return sword
    end
    return nil
end

--- 每次按完整在线秒结算，保留不足一秒的余量，不补发离线时间。
function Comp:Accrue()
    if not self._active or not self._display then
        return
    end
    local now = os.clock()
    local seconds = math.floor(now - self._lastIncome)
    if seconds < 1 then
        return
    end
    self._lastIncome += seconds
    local data = self:GetTable(Fields.BaseData)
    local sword = data.SlotData["1"]
    if sword and sword.WeaponId == "StarterSword" then
        sword.StoredMoney += Rules.GetIncome(sword.Level) * seconds
        self:SetTable(Fields.BaseData, data)
    end
end

--- 按实际根节点距离判定，不能靠客户端提交位置或替其他玩家触发。
--- @param part BasePart 服务端持有的交互锚点。
--- @param horizontalMargin number 交互面的水平扩展距离。
--- @return boolean 本人存活角色是否靠近该面。
function Comp:IsNear(part, horizontalMargin)
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    if not self._active or not part or not root or humanoid.Health <= 0 then
        return false
    end
    local offset = part.CFrame:PointToObjectSpace(root.Position)
    return math.abs(offset.X) <= part.Size.X / 2 + horizontalMargin
        and math.abs(offset.Z) <= part.Size.Z / 2 + horizontalMargin
        and math.abs(offset.Y) <= 5
end

--- 钱包入账与累计额清零在同一奖励计划中预检提交，失败保留原累计额。
function Comp:Collect()
    local sword = self:GetSword()
    if not sword or sword.StoredMoney <= 0 or not self:IsNear(self._collect, 2) then
        return
    end
    self:RequireComponent("FSRewardComp"):AddRewards({
        {Type = "SlotSwordCollect", Amount = sword.StoredMoney},
        {Type = "Money", Currency = "Money", Count = sword.StoredMoney},
    })
end

--- 只升级当前第一槽的剑；金币不足时框架拒绝整批交易，不扣款不升级。
function Comp:Upgrade()
    if not self._display or not self:IsNear(self._sign, 6) or os.clock() - self._lastUpgrade < 0.4 then
        return
    end
    self._lastUpgrade = os.clock()
    self:Accrue()
    local sword = self:GetSword()
    if sword then
        self:RequireComponent("FSRewardComp"):ExchangeRewards(
            {{Type = "Money", Currency = "Money", Count = Rules.GetUpgradePrice(sword.Level)}},
            {{Type = "SlotSwordUpgrade", ExpectedLevel = sword.Level}})
    end
end

--- 向所有客户端发布公开展示值，不把领钱或升级资格交给客户端。
function Comp:Publish()
    if not self._display then
        return
    end
    local sword = self:GetSword()
    self._display:SetAttribute("HasSword", sword ~= nil)
    if sword then
        self._display:SetAttribute("Level", sword.Level)
        self._display:SetAttribute("Income", Rules.GetIncome(sword.Level))
        self._display:SetAttribute("UpgradePrice", Rules.GetUpgradePrice(sword.Level))
        self._display:SetAttribute("StoredMoney", sword.StoredMoney)
    end
end

--- 复用框架每秒更新，积累后自动领取；不用客户端领钱协议或独立保存循环。
--- @param serverTime number 框架秒更新时戳，在线间隔使用单调时钟计算。
function Comp:OnUpdate(serverTime)
    if self._active then
        self:EnsureDisplay()
        self:Accrue()
        self:Collect()
    end
end

--- 离服结算最后完整在线秒并清理本组件的展示，未领金额仍由框架保存。
function Comp:OnPlayerLogout()
    self:Accrue()
    self._active = false
    if self._display then
        self._display:Destroy()
        self._display, self._sign, self._collect = nil, nil, nil
    end
end

--- 覆盖非正常销毁路径，基类负责释放数据订阅。
function Comp:Dtor()
    self:OnPlayerLogout()
    Comp.Super.Dtor(self)
end

return Comp
