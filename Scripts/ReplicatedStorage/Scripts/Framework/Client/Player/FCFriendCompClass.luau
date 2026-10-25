local FX, FC = _G.FX, _G.FC
local Friend = FX.Class("FCFriendCompClass", "FCPlayerCompClass")
FC.FriendCompClass = Friend

function Friend:Ctor(owner)
    Friend.Super.Ctor(self, owner)
    self._state = { ids = {}, status = "Loading", revision = -1 }
    FX.Network:RegServerMsgCallback("S2C_FriendState", function(state)
        self:_Receive(state)
    end)
end

function Friend:GetCompName()
    return "FCFriendComp"
end

function Friend:_Receive(state)
    if not self._destroyed and state and state.revision > self._state.revision then
        self._state = FX.Table:DeepCopy(state)
        self:PublishEvent("FriendStateChanged", self:GetState())
    end
end

function Friend:OnReady()
    -- 使用同一个 S2C 通道补发初始快照，不阻塞其他组件的 OnReady。
    FX.Network:SendMsgToServer("C2S_GetFriendState")
end

function Friend:GetState()
    return FX.Table:DeepCopy(self._state)
end

function Friend:GetFriendCountInRoom()
    if self._state.status ~= "Ready" then
        return nil
    end
    return #self._state.ids
end

function Friend:Dtor()
    self._destroyed = true
    FX.Network:UnRegServerMsgCallback("S2C_FriendState")
    Friend.Super.Dtor(self)
end

return Friend
