local FX, FC = _G.FX, _G.FC

FC.Events = {
    -- 准备就绪: function()
    OnReady = Instance.new("BindableEvent"),
    OnPlayerDataChanged = Instance.new("BindableEvent"),
}
return true
