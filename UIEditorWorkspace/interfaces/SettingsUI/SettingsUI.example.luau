local FX = _G.FX
local CSettingsPreview = FX.Class("CSettingsPreview", "CSettingsView")

-- 父构造之后准备完整的编辑器模拟设置。
-- @param owner table 编辑器组件宿主
function CSettingsPreview:Ctor(owner)
    CSettingsPreview.Super.Ctor(self, owner)
    self.Config = {}
    self.State = {
        musicVolume = 70,
        soundEffectsVolume = 85,
        showAura = true,
        giantPickaxe = false,
        renderDistance = "Medium",
    }
end

-- 先绑定父类节点，再绑定数据并显示界面。
function CSettingsPreview:OnReady()
    CSettingsPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 在 Preview 中更新本地状态，不触发真实游戏设置。
-- @param action string ChangeSetting 或 Close
-- @param payload table 设置键与新值，或 Close 的空表
function CSettingsPreview:OnUIAction(action, payload)
    if action == "Close" then
        self:Hide()
        return
    elseif action == "SliderDragEnded" then
        print("模拟：保存音量偏好")
        return
    end

    assert(action == "ChangeSetting", "Unsupported settings action: " .. tostring(action))
    local setting = payload.setting
    if setting == "musicVolume" or setting == "soundEffectsVolume" then
        assert(type(payload.value) == "number", "Volume value must be a number")
        self.State[setting] = math.clamp(math.floor(payload.value + 0.5), 0, 100)
    elseif setting == "renderDistance" then
        assert(payload.value == "Low" or payload.value == "Medium" or payload.value == "High", "Unknown distance")
        self.State[setting] = payload.value
    elseif setting == "showAura" or setting == "giantPickaxe" then
        assert(type(payload.value) == "boolean", "Toggle value must be a boolean")
        self.State[setting] = payload.value
    else
        error("Unknown setting: " .. tostring(setting))
    end

    self:RefreshUI()
end

return CSettingsPreview
