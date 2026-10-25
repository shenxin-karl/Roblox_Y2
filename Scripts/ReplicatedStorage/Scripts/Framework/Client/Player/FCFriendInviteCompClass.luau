local FX, FC = _G.FX, _G.FC
local Text = FX.Text
local TranslationTexts = Text.Define("FriendInvite", {
    Title = "Play with friends",
    Online = "{name} is online. Invite them to play!",
    Invite = "Invite",
    Close = "Close",
})
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

--- 进服一分钟后，仅提醒一次邀请当前在线且不在本服的好友。
local Component = FX.Class("FCFriendInviteCompClass", "FCPlayerCompClass")

--- 独立于角色重生计时，组件销毁时取消尚未完成的平台查询。
--- @param owner FCPlayerObjectClass 选择挂载邀请提醒的客户端玩家对象。
function Component:Ctor(owner)
    Component.Super.Ctor(self, owner)
    self._checkTask = task.delay(60, function()
        self:CheckOnlineFriends()
        self._checkTask = nil
    end)
end

--- 取消计时与查询，并释放组件创建的提示界面。
function Component:Dtor()
    self._destroyed = true
    if self._checkTask then
        task.cancel(self._checkTask)
    end
    self:CloseInviteNotification()
    Component.Super.Dtor(self)
end

--- 提供框架邀请提醒的组件协作名称，与同服好友状态组件区分。
--- @return string 好友邀请组件名称。
function Component:GetCompName()
    return "FCFriendInviteComp"
end

--- 只查一次在线状态；无好友、平台不允许邀请或查询失败时不显示提示。
function Component:CheckOnlineFriends()
    local player = self:GetPlayerNode()
    local success, friends = pcall(function()
        return player:GetFriendsOnlineAsync(200)
    end)
    if self._destroyed or not success then
        return
    end

    local candidates = {}
    for index, friend in ipairs(friends) do
        if friend.IsOnline and not Players:GetPlayerByUserId(friend.VisitorId) then
            table.insert(candidates, friend)
        end
    end
    if #candidates == 0 then
        return
    end

    local friend = candidates[math.random(1, #candidates)]
    local canCheck, canInvite = pcall(function()
        return SocialService:CanSendGameInviteAsync(player, friend.VisitorId)
    end)
    if self._destroyed or not canCheck or not canInvite
        or Players:GetPlayerByUserId(friend.VisitorId) then
        return
    end
    self:ShowInviteNotification(friend)
end

--- 创建类似原生通知的右下角提示，小屏幕等比缩小，邀请仍由官方窗口确认。
--- @param friend table 平台返回的在线好友信息。
function Component:ShowInviteNotification(friend)
    self:CloseInviteNotification()
    local screen = Instance.new("ScreenGui")
    screen.Name = "FriendInviteUI"
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 30
    screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    self._notificationScreen = screen

    local panel = Instance.new("Frame")
    panel.Name = "Notification"
    panel.AnchorPoint = Vector2.new(1, 1)
    panel.Size = UDim2.fromOffset(300, 144)
    panel.BackgroundColor3 = Color3.fromRGB(35, 37, 39)
    panel.BackgroundTransparency = 0.2
    panel.BorderSizePixel = 0
    panel.Parent = screen
    local scale = Instance.new("UIScale")
    scale.Parent = panel

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Position = UDim2.fromOffset(12, 14)
    avatar.Size = UDim2.fromOffset(52, 64)
    avatar.BackgroundTransparency = 1
    avatar.ScaleType = Enum.ScaleType.Fit
    avatar.Image = "rbxthumb://type=Avatar&id=" .. friend.VisitorId .. "&w=150&h=150"
    avatar.Parent = panel

    --- 统一提示文本样式，仅关闭由本脚本翻译的文本节点的自动翻译。
    --- @param className string 文本标签或按钮的实例类型。
    --- @param name string 节点名称。
    --- @param position UDim2 面板内的位置。
    --- @param size UDim2 节点大小。
    --- @return TextLabel | TextButton 新建的文本节点。
    local function createText(className, name, position, size)
        local node = Instance.new(className)
        node.Name = name
        node.Position = position
        node.Size = size
        node.BackgroundTransparency = 1
        node.BorderSizePixel = 0
        node.Font = Enum.Font.Gotham
        node.TextSize = 14
        node.TextColor3 = Color3.new(1, 1, 1)
        node.AutoLocalize = false
        node.Text = ""
        node.Parent = panel
        return node
    end

    local title = createText("TextLabel", "Title", UDim2.fromOffset(76, 12), UDim2.fromOffset(212, 24))
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    local message = createText("TextLabel", "Message", UDim2.fromOffset(76, 38), UDim2.fromOffset(212, 56))
    message.TextSize = 13
    message.TextWrapped = true
    message.TextXAlignment = Enum.TextXAlignment.Left
    message.TextYAlignment = Enum.TextYAlignment.Top
    local invite = createText("TextButton", "Invite", UDim2.fromOffset(0, 104), UDim2.fromOffset(150, 40))
    local close = createText("TextButton", "Close", UDim2.fromOffset(150, 104), UDim2.fromOffset(150, 40))
    for index, button in ipairs({invite, close}) do
        button.BackgroundColor3 = Color3.new(1, 1, 1)
        button.BackgroundTransparency = 0.94
    end
    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.Position = UDim2.fromOffset(0, 103)
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.BorderSizePixel = 0
    divider.BackgroundColor3 = Color3.new(1, 1, 1)
    divider.BackgroundTransparency = 0.65
    divider.Parent = panel
    local buttonDivider = divider:Clone()
    buttonDivider.Name = "ButtonDivider"
    buttonDivider.Position = UDim2.fromOffset(149, 104)
    buttonDivider.Size = UDim2.fromOffset(1, 40)
    buttonDivider.Parent = panel

    --- 跟随屏幕尺寸缩放，底部留出操作区的空间。
    local function updateScale()
        local size = screen.AbsoluteSize
        scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.65, 1)
        panel.Position = UDim2.new(1, -12 * scale.Scale, 1, -120 * scale.Scale)
    end
    --- 语言变化时同步刷新已显示的提示及按钮。
    local function refreshText()
        title.Text = Text.Tr(TranslationTexts.Title)
        message.Text = Text.Tr(TranslationTexts.Online, {name = friend.DisplayName or friend.UserName})
        invite.Text = Text.Tr(TranslationTexts.Invite)
        close.Text = Text.Tr(TranslationTexts.Close)
    end
    local localization = FC.Localization
    self._notificationConnections = {
        screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale),
        localization.Changed:Connect(refreshText),
        invite.Activated:Connect(function()
            if self._destroyed or self._inviteHandled then
                return
            end
            self._inviteHandled = true
            self:CloseInviteNotification()
            self:PromptInvite(friend.VisitorId)
        end),
        close.Activated:Connect(function()
            self:CloseInviteNotification()
        end),
    }
    screen.Parent = self:GetPlayerNode():WaitForChild("PlayerGui")
    updateScale()
    refreshText()
    self._notificationTask = task.delay(12, function()
        self._notificationTask = nil
        self:CloseInviteNotification()
    end)
end

--- 关闭提示并解除其连接，避免过期计时或语言刷新访问已销毁节点。
function Component:CloseInviteNotification()
    if self._notificationTask then
        task.cancel(self._notificationTask)
        self._notificationTask = nil
    end
    if self._notificationConnections then
        for index, connection in ipairs(self._notificationConnections) do
            connection:Disconnect()
        end
        self._notificationConnections = nil
    end
    if self._notificationScreen then
        self._notificationScreen:Destroy()
        self._notificationScreen = nil
    end
end

--- 点击时再次检查邀请资格与同服状态，再交由玩家确认官方邀请。
--- @param friendId number 本次通知对应好友的 Roblox UserId。
function Component:PromptInvite(friendId)
    local success, message = pcall(function()
        local player = self:GetPlayerNode()
        if SocialService:CanSendGameInviteAsync(player, friendId)
            and not self._destroyed and not Players:GetPlayerByUserId(friendId) then
            local options = Instance.new("ExperienceInviteOptions")
            options.InviteUser = friendId
            SocialService:PromptGameInvite(player, options)
            options:Destroy()
        end
    end)
    if not success then
        warn("Unable to open friend invite:", message)
    end
end

return Component
