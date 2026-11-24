-- 玩家矿场入口：管理木棍和会话校验，公共矿石由矿场服务负责。
local FX = _G.FX
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
-- 棒球棍网格自带斜角；握点落在细柄靠尾钮的位置。
local StickGrip = CFrame.new(1.04, -1.28, 0) * CFrame.Angles(0, 0, math.rad(39))
local Comp = FX.Class("SMiningCompClass", "FSPlayerCompClass")

--- 建立各类请求的服务端冷却。
--- @param owner table 服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._lastRequest = -math.huge
    self._lastSwing = -math.huge
end

--- 返回协议转发使用的组件名。
--- @return string 组件协作名。
function Comp:GetCompName()
    return "SMiningComp"
end

--- 只克隆木质棒球棍网格作为手持外观；重生后重新发放。
function Comp:GiveStick()
    local backpack = self:GetPlayerNode():FindFirstChildOfClass("Backpack")
    if not backpack or (self._stick and self._stick.Parent) then
        return
    end
    local tool = Instance.new("Tool")
    tool.Name = Settings.StickName
    tool.CanBeDropped = false
    tool.Grip = StickGrip
    local template = FX.Loader:Shared("Assets.Decorations.MiningBaseballBat")
        :FindFirstChildWhichIsA("MeshPart", true)
    local handle = template:Clone()
    handle:ClearAllChildren()
    handle.Name = "Handle"
    handle.Size *= 4.5
    handle.Anchored, handle.CanCollide, handle.CanTouch, handle.CanQuery = false, false, false, false
    handle.Massless = true
    handle.Parent = tool
    self._stick = tool
    tool.Parent = backpack
end

--- 登录只发放木棍和接通角色生命周期，不改变公共刷新时间。
function Comp:OnPlayerLogin()
    self._active = true
    local player = self:GetPlayerNode()
    self:TrackConnection(player.ChildAdded:Connect(function(child)
        if self._active and child:IsA("Backpack") then
            self:GiveStick()
        end
    end))
    self:TrackConnection(player.CharacterAdded:Connect(function()
        if self._active then
            self:GiveStick()
        end
    end))
    self:TrackConnection(player.CharacterRemoving:Connect(function()
        _G.SMiningManager:ReleaseOre(self:GetPlayerObject(), true)
        if self._stick then
            self._stick:Destroy()
            self._stick = nil
        end
    end))
    self:GiveStick()
end

--- 沿用玩家更新，只有正在搬运的人需要检查是否已经进了自己的基地。
--- @param serverTime number 玩家框架提供的更新时刻；交付只判断当前角色位置。
function Comp:OnUpdate(serverTime)
    if self._active then
        _G.SMiningManager:TryDeposit(self:GetPlayerObject())
    end
end

--- 搬运期间禁用矿区快捷传送，避免跳过矿区。
function Comp:TeleportToMine()
    local manager = _G.SMiningManager
    if not self._active or manager:IsCarrying(self:GetPlayerObject())
        or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    local forge = self:RequireComponent("SForgeComp")
    local character, humanoid = forge:GetLivingCharacter()
    if not character or humanoid.PlatformStand then
        return
    end
    self._lastRequest = os.clock()
    forge:Teleport(character, humanoid, manager:GetArrival())
    forge:Release()
end

--- 拒绝未登录、倒地或死亡的角色，位置始终从服务端角色获取。
--- @param action string 由服务端协议固定为 PickUp 或 Smelt。
--- @param rock any 拾取时由客户端提交公共矿石编号。
function Comp:Request(action, rock)
    if not self._active or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    local character, humanoid = self:RequireComponent("SForgeComp"):GetLivingCharacter()
    if not character or humanoid.PlatformStand or self:GetNumber(_G.PlayerDataConfig.ForgeStation) > 0 then
        return
    end
    self._lastRequest = os.clock()
    if action == "PickUp" then
        _G.SMiningManager:PickUp(self:GetPlayerObject(), humanoid, rock)
    elseif action == "Smelt" then
        _G.SMiningManager:Smelt(self:GetPlayerObject(), humanoid)
    end
end

--- 已装备且没背矿时允许挥击；背矿只限制挥击，不限制快捷栏切换装备。
--- @param toggleEquip boolean? 快捷栏传 true 以切换装备；挥击和矿区按钮不传。
function Comp:SwingStick(toggleEquip)
    if not self._active or os.clock() - self._lastSwing < Settings.StickCooldown then
        return
    end
    local character, humanoid = self:RequireComponent("SForgeComp"):GetLivingCharacter()
    local manager = _G.SMiningManager
    local stick = self._stick
    if not character or not stick or humanoid.PlatformStand or self:GetNumber(_G.PlayerDataConfig.ForgeStation) > 0 then
        return
    end
    local equipped = stick.Parent == character
    if equipped and toggleEquip ~= true and manager:IsCarrying(self:GetPlayerObject()) then
        return
    end
    if not equipped and toggleEquip ~= true and not manager:IsInQuarry(humanoid.RootPart.Position) then
        return
    end
    local backpack = self:GetPlayerNode():FindFirstChildOfClass("Backpack")
    if not equipped and (not backpack or stick.Parent ~= backpack) then
        return
    end
    self._lastSwing = os.clock()
    if not equipped then
        humanoid:EquipTool(stick)
    elseif toggleEquip == true then
        humanoid:UnequipTools()
    else
        stick:SetAttribute(Settings.StickSwingAttribute, workspace:GetServerTimeNow())
        manager:Strike(self:GetPlayerObject(), humanoid)
    end
end

--- 离服即时释放矿石和木棍，其他玩家仍可拾取归还的矿。
function Comp:OnPlayerLogout()
    self._active = false
    _G.SMiningManager:ReleaseOre(self:GetPlayerObject(), true)
    if self._stick then
        self._stick:Destroy()
        self._stick = nil
    end
end

return Comp
