-- 公共矿场界面：显示服务端刷新倒计时与最近交互，库存仍使用原生背包。
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local FX, FC = _G.FX, _G.FC
local Text = FX.Text
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Config = _G.GameConfig.CommonConfig
local MiningEffects = FX.Loader:RequireFromParent(script, "CMiningEffects")
local UIRoot = FX.Loader:RequireShared("Scripts.Framework.Client.FCUIRoot")
local TranslationTexts = Text.Define("MiningInteraction", {
    Refresh = "Rocks refresh in {seconds:int}s",
    Preparing = "Preparing rocks...",
    Mine = "Mine ({hits:int} hits left)",
    Smelt = "Smelt raw sword ({count:int} ore)",
    Received = "Received {count:int} {name}",
})
local Comp = FX.Class("CMiningCompClass", "FCUICompClass")

--- 返回矿场界面的组件名。
--- @return string 组件协作名。
function Comp:GetCompName()
    return "CMiningComp"
end

--- 只创建自身界面，不改 Generated；场景目标允许随流式加载出现或消失。
function Comp:OnReady()
    self._effects = MiningEffects.New(self)
    local root = Instance.new("Frame")
    root.Name = "MiningHUD"
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundTransparency = 1
    root.Parent = UIRoot.Get()
    self._rootNode = root
    local countdown = Instance.new("TextLabel")
    countdown.Name = "RefreshCountdown"
    countdown.AnchorPoint = Vector2.new(0.5, 0)
    countdown.Position = UDim2.new(0.5, 0, 0, 75)
    countdown.Size = UDim2.fromOffset(310, 36)
    countdown.BackgroundColor3 = Color3.fromRGB(42, 47, 53)
    countdown.BackgroundTransparency = 0.15
    countdown.TextColor3 = Color3.new(1, 1, 1)
    countdown.Font = Enum.Font.GothamBold
    countdown.TextSize = 18
    countdown.AutoLocalize = false
    countdown.Parent = root
    self._countdown = countdown
    local feedback = countdown:Clone()
    feedback.Name = "MiningReward"
    feedback.Position = UDim2.new(0.5, 0, 0, 115)
    feedback.Size = UDim2.fromOffset(460, 36)
    feedback.TextColor3 = Color3.fromRGB(120, 255, 80)
    feedback.Visible = false
    feedback.Parent = root
    self._rewardLabel = feedback
    FX.Network:RegServerMsgCallback("S2C_MiningReward", function(itemId, count)
        self._rewardItemId, self._rewardCount = itemId, count
        self._rewardUntil = os.clock() + 2
        self:RefreshReward()
    end)
    local button = Instance.new("TextButton")
    button.Name = "MiningInteraction"
    button.AnchorPoint = Vector2.new(0.5, 1)
    button.Position = UDim2.new(0.5, 0, 1, -195)
    button.Size = UDim2.fromOffset(280, 54)
    button.BackgroundColor3 = Color3.fromRGB(67, 99, 117)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 20
    button.AutoLocalize = false
    button.Visible = false
    button.Parent = root
    self._button = button
    self._lastRequest = -math.huge
    self:TrackConnection(button.Activated:Connect(function()
        if not button.Visible or os.clock() - self._lastRequest < Settings.RequestCooldown then
            return
        end
        if self._rock then
            self:MineRock()
        elseif self._nearFurnace then
            self._lastRequest = os.clock()
            FX.Network:SendMsgToServer("C2S_SmeltSword")
        end
    end))
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        self:Refresh()
    end))
    local elapsed = 0
    --- 限制附近目标扫描频率，倒计时仍以服务器绝对时间为准。
    --- @param deltaTime number 本帧经过秒数。
    self:TrackConnection(RunService.Heartbeat:Connect(function(deltaTime)
        self._effects:Update()
        elapsed += deltaTime
        if elapsed >= 0.1 then
            elapsed = 0
            self:Refresh()
        end
    end))
    self:Refresh()
end

--- 仅显示服务器已入包的矿石数量，语言切换沿用矿场刷新，不预测奖励。
function Comp:RefreshReward()
    local visible = self._rewardUntil ~= nil and os.clock() < self._rewardUntil
    self._rewardLabel.Visible = visible
    if visible then
        self._rewardLabel.Text = Text.Tr(TranslationTexts.Received, {
            count = self._rewardCount, name = Text.TrSource(_G.ItemConfig.Display[self._rewardItemId].Name),
        })
    end
end

--- 换装、死亡或组件销毁时中断挥镐，取消尚未落下的攻击并恢复关节。
function Comp:StopSwing()
    if self._swingTrail then
        self._swingTrail.Enabled = false
        self._swingTrail:Clear()
    end
    if self._swingTask then
        task.cancel(self._swingTask)
        self._swingTask = nil
    end
    if self._swingTrack then
        self._swingTrack:Destroy()
        self._swingTrack = nil
    end
    for joint, pose in pairs(self._swingJoints or {}) do
        if pose.Tween then
            pose.Tween:Cancel()
        end
        if joint.Parent then
            joint[pose.Property or "C0"] = pose.Base
        end
    end
    self._swingJoints = nil
end

--- 沿用 Money 的关节补间，R15 只驱动腰部，手臂由原动画驱动。
--- @param duration number 阶段持续秒数。
--- @param armAngle number R6 持镐手臂俯仰角。
--- @param bodyAngle number 躯干俯仰角。
--- @param direction Enum.EasingDirection 当前阶段缓动方向。
function Comp:PoseSwing(duration, armAngle, bodyAngle, direction)
    for joint, pose in pairs(self._swingJoints) do
        local angle = pose.Body and bodyAngle or armAngle
        local base = pose.Base
        local target = CFrame.new(base.Position) * CFrame.Angles(math.rad(angle), 0, 0) * base.Rotation
        pose.Tween = TweenService:Create(joint, TweenInfo.new(duration, Enum.EasingStyle.Quad, direction), {
            [pose.Property or "C0"] = target,
        })
        pose.Tween:Play()
    end
end

--- 自动攻击或点击按钮时使用 Money 的挥镐节奏，落点仍由服务端校验。
function Comp:MineRock()
    if not self._rock or not self._swingTrail or self._swingTask or os.clock() - self._lastRequest < 0.8 then
        return
    end
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local tool = self._pickaxe
    if not humanoid or humanoid.Health <= 0 or not tool or not tool.Parent then
        return
    end
    if tool.Parent ~= character then
        humanoid:EquipTool(tool)
    end
    if tool.Parent ~= character then
        return
    end
    self:StopSwing()
    self._lastRequest = os.clock()
    local rock = self._rock
    local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
    if r15 then
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            return
        end
        local animation = tool:FindFirstChild("RockUpperBodySwing")
        if not animation then
            return
        end
        self._swingTrack = animator:LoadAnimation(animation)
        self._swingTrack.Priority = Enum.AnimationPriority.Action
        self._swingTrack.Looped = false
        self._swingTrack:Play(0.08, 1, 0.25 / 0.26)
    end
    self._swingJoints = {}
    if r15 then
        local torso = character:FindFirstChild("UpperTorso")
        local waist = torso and torso:FindFirstChild("Waist")
        if waist and waist:IsA("Motor6D") then
            self._swingJoints[waist] = {Base = waist.C0, Body = true}
        elseif waist and waist:IsA("AnimationConstraint") and waist.Attachment0 then
            local attachment = waist.Attachment0
            self._swingJoints[attachment] = {Base = attachment.CFrame, Body = true, Property = "CFrame"}
        end
    else
        for index, joint in ipairs(character:GetDescendants()) do
            if joint:IsA("Motor6D") and joint.Part1 and joint.Part1.Name == "Right Arm" then
                self._swingJoints[joint] = {Base = joint.C0, Body = false}
            end
        end
    end
    local windup = r15 and 0.26 or 0.22
    local strike = r15 and 0.14 or 0.1
    local recovery = r15 and 0.26 or 0.28
    self._swingTask = task.spawn(function()
        self:PoseSwing(windup, 85, 10, Enum.EasingDirection.Out)
        task.wait(windup)
        if self._swingTrack then
            self._swingTrack:AdjustSpeed(0.25 / strike)
        end
        self._swingTrail.Enabled = true
        self:PoseSwing(strike, -40, -38, Enum.EasingDirection.In)
        task.wait(strike)
        local root = humanoid.RootPart
        if humanoid.Health > 0 and tool.Parent == character and rock.Parent and root
            and (root.Position - rock:GetPivot().Position).Magnitude <= Settings.InteractDistance then
            FX.Network:SendMsgToServer("C2S_MineRock", rock)
        end
        if self._swingTrack then
            self._swingTrack:AdjustSpeed(1.25)
        end
        task.wait(0.06)
        self._swingTrail.Enabled = false
        self:PoseSwing(recovery, 0, 0, Enum.EasingDirection.Out)
        task.wait(recovery)
        self._swingTask = nil
        self:StopSwing()
    end)
end

--- 跟踪服务端复制的自制木镐，重生或换装时释放旧连接与镐头拖尾。
function Comp:RefreshPickaxe()
    local player = self:GetPlayerNode()
    local character = self:GetPlayerCharacter()
    local backpack = player:FindFirstChildOfClass("Backpack")
    local tool = character and character:FindFirstChild("MiningPickaxe")
        or backpack and backpack:FindFirstChild("MiningPickaxe")
    local handle = tool and tool:FindFirstChild("Handle")
    local trail = handle and handle:FindFirstChild("PickaxeSwingTrail")
    if tool == self._pickaxe then
        self._swingTrail = trail
        return
    end
    self:StopSwing()
    if self._toolActivated then
        self._toolActivated:Disconnect()
        self._toolUnequipped:Disconnect()
        self._toolActivated = nil
        self._toolUnequipped = nil
    end
    self._pickaxe = tool
    self._swingTrail = trail
    if tool then
        self._toolActivated = tool.Activated:Connect(function()
            self:MineRock()
        end)
        self._toolUnequipped = tool.Unequipped:Connect(function()
            self:StopSwing()
        end)
    end
end

--- 原生 Tool 名称来自配置翻译，堆叠数仅显示整数，不复制私有背包数据。
function Comp:RefreshToolNames()
    local player = self:GetPlayerNode()
    local containers = {player:FindFirstChildOfClass("Backpack"), player.Character}
    for index = 1, 2 do
        local container = containers[index]
        if container then
            for childIndex, tool in ipairs(container:GetChildren()) do
                local itemId = tool:GetAttribute("FrameworkItemId")
                local display = itemId and _G.ItemConfig.Display[itemId]
                if tool:IsA("Tool") and display then
                    local name = Text.TrSource(display.Name)
                    local count = tool:GetAttribute("FrameworkStackCount") or 1
                    if count > 1 then
                        name ..= " ×" .. count
                    end
                    if tool.Name ~= name then
                        tool.Name = name
                    end
                    local description = Text.TrSource(display.Desc)
                    if tool.ToolTip ~= description then
                        tool.ToolTip = description
                    end
                end
            end
        end
    end
end

--- 只选择已复制到本客户端的最近公共石头；最终有效性仍由服务端重验。
function Comp:Refresh()
    self:RefreshReward()
    self:RefreshPickaxe()
    local deadline = FX.SyncManager:GetNumber(_G.ServerDataConfig.MiningNextRefresh)
    local seconds = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
    self._countdown.Text = deadline > 0
        and Text.Tr(TranslationTexts.Refresh, {seconds = seconds})
        or Text.Tr(TranslationTexts.Preparing)
    self._rock = nil
    self._nearFurnace = false
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    if root and humanoid.Health > 0 then
        local nearestDistance = Settings.InteractDistance
        for index, rock in ipairs(CollectionService:GetTagged(Settings.RockTag)) do
            local hits = rock:GetAttribute("RemainingHits")
            if rock:IsA("Model") and rock.PrimaryPart and hits and hits > 0 then
                local offset = rock:GetPivot().Position - root.Position
                local distance = offset.Magnitude
                if distance <= nearestDistance and (distance < 0.01 or root.CFrame.LookVector:Dot(offset.Unit) > 0) then
                    self._rock = rock
                    nearestDistance = distance
                end
            end
        end
        local furnace = FX.Loader:Find(workspace, Settings.FurnacePath)
        self._nearFurnace = furnace ~= nil
            and Settings.DistanceToPart(furnace, root.Position) <= Settings.InteractDistance
    end
    self._button.Visible = self._rock ~= nil or self._nearFurnace
    if self._rock then
        self._button.Text = Text.Tr(TranslationTexts.Mine, {hits = self._rock:GetAttribute("RemainingHits")})
        -- 与 Money 相同，靠近且面向矿石时自动挥镐；持有其他道具时不抢占装备。
        local heldTool = character:FindFirstChildOfClass("Tool")
        local offset = self._rock:GetPivot().Position - root.Position
        if (not heldTool or heldTool == self._pickaxe)
            and (offset.Magnitude < 0.01 or root.CFrame.LookVector:Dot(offset.Unit) > 0) then
            self:MineRock()
        end
    elseif self._nearFurnace then
        self._button.Text = Text.Tr(TranslationTexts.Smelt, {count = Config.FurnaceOreCost})
    end
    self:RefreshToolNames()
end

--- 只删除矿场自有节点，保留共享画布和背包 Tool。
function Comp:Dtor()
    FX.Network:UnRegServerMsgCallback("S2C_MiningReward")
    self:StopSwing()
    if self._effects then
        self._effects:Destroy()
    end
    if self._toolActivated then
        self._toolActivated:Disconnect()
        self._toolUnequipped:Disconnect()
    end
    Comp.Super.Dtor(self)
    if self._rootNode then
        self._rootNode:Destroy()
    end
end

return Comp
