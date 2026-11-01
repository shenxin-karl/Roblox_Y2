-- 公共矿场界面：显示服务端刷新倒计时与最近交互，库存仍使用原生背包。
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local FX, FC = _G.FX, _G.FC
local Text = FX.Text
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Config = _G.GameConfig.CommonConfig
local UIRoot = FX.Loader:RequireShared("Scripts.Framework.Client.FCUIRoot")
local TranslationTexts = Text.Define("MiningInteraction", {
    Refresh = "Rocks refresh in {seconds:int}s",
    Preparing = "Preparing rocks...",
    Mine = "Mine ({hits:int} hits left)",
    Smelt = "Smelt sword ({count:int} ore)",
})
local Comp = FX.Class("CMiningCompClass", "FCUICompClass")

--- 返回矿场界面的组件名。
--- @return string 组件协作名。
function Comp:GetCompName()
    return "CMiningComp"
end

--- 只创建自身界面，不改 Generated；场景目标允许随流式加载出现或消失。
function Comp:OnReady()
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
        self._lastRequest = os.clock()
        if self._rock then
            FX.Network:SendMsgToServer("C2S_MineRock", self._rock)
        elseif self._nearFurnace then
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
        elapsed += deltaTime
        if elapsed >= 0.1 then
            elapsed = 0
            self:Refresh()
        end
    end))
    self:Refresh()
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
            if rock:IsA("BasePart") and hits and hits > 0 then
                local distance = (root.Position - rock.Position).Magnitude
                if distance <= nearestDistance then
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
    elseif self._nearFurnace then
        self._button.Text = Text.Tr(TranslationTexts.Smelt, {count = Config.FurnaceOreCost})
    end
    self:RefreshToolNames()
end

--- 只删除矿场自有节点，保留共享画布和背包 Tool。
function Comp:Dtor()
    Comp.Super.Dtor(self)
    if self._rootNode then
        self._rootNode:Destroy()
    end
end

return Comp
