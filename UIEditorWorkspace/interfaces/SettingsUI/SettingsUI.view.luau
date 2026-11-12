--[[
设置界面接入契约

【Config / State】
  Config：不读取配置字段，可设置 self.Config = {}。
  State：必填完整快照，以下字段全部必填、无默认值。
    musicVolume: number；音乐音量，0..100 百分比整数，不是 0..1 音频倍率。
    soundEffectsVolume: number；音效音量，0..100 百分比整数。
    showAura: boolean；是否显示光环。
    giantPickaxe: boolean；是否启用镐子尺寸巨大化。
    renderDistance: string；必填 Low / Medium / High，游戏默认 Medium。
  View 按状态显示，不替业务层保存设置或改变声音/模型。
  无 open、pending、error、列表或独立加载态；异步读取完成前不显示。
  音量图形宽度截断到 0..1、文字取整，但不替业务修正超范围的原始状态。

【最小完整数据（接入 Ctor 调用父构造之后）】
  self.Config = {}
  self.State = {
      musicVolume = 70, soundEffectsVolume = 85,
      showAura = true, giantPickaxe = false,
      renderDistance = "Medium",
  }

【初始化与刷新】
  游戏接入类继承 CSettingsView。
  接入 Ctor(owner) 先调用自身类的 Super.Ctor(self, owner)，再准备下例数据。
  接入 OnReady() 先调用自身类的 Super.OnReady(self)，再依次
  self:BindUIData()、self:Show()；父 OnReady 负责绑定节点，OnShow 会刷新。
  GetUIConfig() 默认返回 self.Config；GetUIState() 默认返回 self.State。
  RefreshUI() 调用 Render(GetUIState())，输入是完整快照，不合并增量，
  不自动补齐业务字段。可修改已有表或替换整表，但每次刷新须满足完整契约。
  后续先更新 Config/State，再 self:RefreshUI()；异步未就绪按本页规则处理。
  无需覆写 Render 或手动重复调用 OnReady；业务类覆写生命周期时须保留父调用。

【动作与覆写】
  必需覆写 OnUIAction(action: string, payload: table)，无返回值；默认报错。
  ChangeSetting -> { setting: string, value: number | boolean | string }。
    setting="musicVolume" / "soundEffectsVolume"：value 为 0..100 整数百分比。
    setting="showAura" / "giantPickaxe"：value 为 boolean，取当前 State 的反值。
    setting="renderDistance"：value 为 Low / Medium / High；选中亮绿，其余灰绿，均可点击。
    不支持其他设置键；setting 为稳定字段名，不是翻译后的标签。
  Close -> {}；由接入层调用 self:Hide()，没有 State.open。
  SliderDragEnded -> {}；鼠标/触摸释放或窗口失焦时提交最后设置。
  IsSliderDragging()->boolean 为只读查询，不覆写；业务同步可据此避免覆盖本地拖动。
  OnHide 取消拖动；项目覆写 OnHide 时必须先调用父方法。
  继承 EmitUIAction、Render 与输入绑定，不重复连接滑杆。
  拖动滑杆会连续发送 ChangeSetting，不只在释放时发送；接入层收到后
  更新对应 State 字段并 RefreshUI，否则滑杆/开关不会得到状态确认。
  实际音频映射、光环显隐、镐子放大及关闭设置后恢复原尺寸由游戏处理。
  若异步保存，接入层自行处理合并请求、过期响应和失败回滚；
  View 没有等待锁或错误提示，不能将每次滑动事件等同于一次存档成功。

【显隐边界】
  窗口由 Show/Hide 管理，Render 不控制根 Enabled 或整个窗口 Visible。
  滑杆支持鼠标和触屏，移动时读取当前真实轨道尺寸，拖出后仍可释放。
  编辑器模拟仅验证鼠标；触屏与失焦需要 Studio/设备另行验证。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts/Game/Shared/Text")
local CSettingsView = FX.Class("CSettingsView", "CUIView")

local TranslationTexts = Text.Define("SettingsUI", {
    Volume = "{value:int}%",
    On = "ON",
    Off = "OFF",
})

-- 暴露只读文案定义，供接入子类通过 self.BaseViewTranslationTexts 复用。
CSettingsView.BaseViewTranslationTexts = TranslationTexts

-- 把鼠标位置换算成百分比，并把音量变化交给接入层。
-- @param self CSettingsView 实例
-- @param setting string 稳定的音量设置字段
-- @param track Frame 音量轨道
-- @param inputButton TextButton 透明拖动命中区
local function bindSlider(self, setting, track, inputButton)
    -- 轨道由 UpdateSlider 每次读取，此参数与节点契约保持一致。
    self:TrackConnection(inputButton.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        self._activeSlider = {setting = setting, input = input}
        self:UpdateSlider(input)
    end))
end

-- 拖动状态仅供业务层判断是否可应用远端偏好。
-- @return boolean 当前是否正在拖动音量。
function CSettingsView:IsSliderDragging()
    return self._activeSlider ~= nil
end

-- 读取缩放后的轨道，保证布局变化时仍按实际坐标换算。
-- @param input InputObject 当前鼠标或触摸输入。
function CSettingsView:UpdateSlider(input)
    local drag = self._activeSlider
    if not drag then
        return
    end
    local track = self.Sliders[drag.setting].track
    -- App 不提供 AbsolutePosition/AbsoluteSize，模拟使用固定设计轨道；Roblox 始终读取原生实时布局。
    local size = track.AbsoluteSize or Vector2.new(190, 0)
    local position = track.AbsolutePosition or Vector2.new(711, 0)
    if size.X <= 0 then
        return
    end
    local value = math.floor(math.clamp((input.Position.X - position.X) / size.X, 0, 1) * 100 + 0.5)
    self:EmitUIAction("ChangeSetting", {setting = drag.setting, value = value})
end

-- 结束拖动后通知业务保存；重复释放不重复发送。
function CSettingsView:EndSliderDrag()
    if self._activeSlider then
        self._activeSlider = nil
        self:EmitUIAction("SliderDragEnded", {})
    end
end

-- 隐藏窗口立即停止输入，不在隐藏后继续修改音量。
function CSettingsView:OnHide()
    self._activeSlider = nil
end

-- 绑定音量与开关节点；事件只连接一次。
function CSettingsView:OnReady()
    local root = FXLoader:PlayerGui("SettingsUI")

    self.Sliders = {
        musicVolume = {
            value = FXLoader:Here(root, "SettingsPanel.ContentBox.MusicRowImg.ValueTxt"),
            track = FXLoader:Here(root, "SettingsPanel.ContentBox.MusicRowImg.MusicTrackImg"),
            fill = FXLoader:Here(root, "SettingsPanel.ContentBox.MusicRowImg.MusicTrackImg.MusicFillImg"),
            knob = FXLoader:Here(root, "SettingsPanel.ContentBox.MusicRowImg.MusicTrackImg.MusicKnobImg"),
            input = FXLoader:Here(root, "SettingsPanel.ContentBox.MusicRowImg.MusicTrackImg.MusicInputBtn"),
        },
        soundEffectsVolume = {
            value = FXLoader:Here(root, "SettingsPanel.ContentBox.SoundEffectsRowImg.ValueTxt"),
            track = FXLoader:Here(root, "SettingsPanel.ContentBox.SoundEffectsRowImg.SoundEffectsTrackImg"),
            fill = FXLoader:Here(root, "SettingsPanel.ContentBox.SoundEffectsRowImg.SoundEffectsTrackImg.SoundEffectsFillImg"),
            knob = FXLoader:Here(root, "SettingsPanel.ContentBox.SoundEffectsRowImg.SoundEffectsTrackImg.SoundEffectsKnobImg"),
            input = FXLoader:Here(root, "SettingsPanel.ContentBox.SoundEffectsRowImg.SoundEffectsTrackImg.SoundEffectsInputBtn"),
        },
    }

    for setting, slider in pairs(self.Sliders) do
        bindSlider(self, setting, slider.track, slider.input)
    end

    -- Roblox 使用全局输入；编辑器的有限模拟通过命中区事件验证同一计算路径。
    local inputService = game and game:GetService("UserInputService")
    if inputService then
        self:TrackConnection(inputService.InputChanged:Connect(function(input)
            local drag = self._activeSlider
            if drag and (input == drag.input or (drag.input.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseMovement)) then
                self:UpdateSlider(input)
            end
        end))
        self:TrackConnection(inputService.InputEnded:Connect(function(input)
            if self._activeSlider and input == self._activeSlider.input then
                self:EndSliderDrag()
            end
        end))
        self:TrackConnection(inputService.WindowFocusReleased:Connect(function()
            self:EndSliderDrag()
        end))
    else
        for setting, slider in pairs(self.Sliders) do
            self:TrackConnection(slider.input.InputChanged:Connect(function(input)
                if self._activeSlider and self._activeSlider.setting == setting then
                    self:UpdateSlider(input)
                end
            end))
            self:TrackConnection(slider.input.InputEnded:Connect(function(input)
                self:EndSliderDrag()
            end))
        end
    end

    self.Toggles = {
        giantPickaxe = {
            button = FXLoader:Here(root, "SettingsPanel.ContentBox.GiantPickaxeRowImg.GiantPickaxeBtn"),
            edge = FXLoader:Here(root, "SettingsPanel.ContentBox.GiantPickaxeRowImg.GiantPickaxeBtn.BottomEdgeImg"),
            text = FXLoader:Here(root, "SettingsPanel.ContentBox.GiantPickaxeRowImg.GiantPickaxeBtn.ButtonTxt"),
        },
        showAura = {
            button = FXLoader:Here(root, "SettingsPanel.ContentBox.ShowAuraRowImg.ShowAuraBtn"),
            edge = FXLoader:Here(root, "SettingsPanel.ContentBox.ShowAuraRowImg.ShowAuraBtn.BottomEdgeImg"),
            text = FXLoader:Here(root, "SettingsPanel.ContentBox.ShowAuraRowImg.ShowAuraBtn.ButtonTxt"),
        },
    }

    for setting, toggle in pairs(self.Toggles) do
        local settingName = setting
        local button = toggle.button
        -- 点击只传设置键和新值，具体保存由接入层负责。
        self:TrackConnection(button.Activated:Connect(function()
            local state = self:GetUIState()
            self:EmitUIAction("ChangeSetting", {
                setting = settingName,
                value = not state[settingName],
            })
        end))
    end

    self.DistanceButtons = {}
    for index, value in ipairs({"Low", "Medium", "High"}) do
        local button = FXLoader:Here(root, "SettingsPanel.ContentBox.RenderDistanceRowImg." .. value .. "Btn")
        self.DistanceButtons[value] = {
            button = button,
            edge = FXLoader:Here(button, "BottomEdgeImg"),
        }
        -- 发送稳定档位，重复点击由业务层忽略。
        self:TrackConnection(button.Activated:Connect(function()
            self:EmitUIAction("ChangeSetting", {setting = "renderDistance", value = value})
        end))
    end

    local closeButton = FXLoader:Here(root, "TitleBox.CloseSurfaceImg")
    -- Close 由接入层转换为窗口 Hide。
    self:TrackConnection(closeButton.Activated:Connect(function()
        self:EmitUIAction("Close", {})
    end))
end

-- 窗口重新显示时读取完整的最新状态。
function CSettingsView:OnShow()
    self:RefreshUI()
end

-- 按完整 State 更新音量与开关显示。
-- @param state table 本文件头定义的完整设置快照
function CSettingsView:Render(state)
    for setting, slider in pairs(self.Sliders) do
        local value = state[setting]
        local ratio = math.clamp(value / 100, 0, 1)
        slider.value.Text = Text.Tr(TranslationTexts.Volume, {
            value = math.floor(value + 0.5),
        })
        slider.fill.Size = UDim2.new(ratio, 0, 1, 0)
        slider.knob.Position = UDim2.new(ratio, 0, 0.5, 0)
    end

    for value, option in pairs(self.DistanceButtons) do
        local selected = state.renderDistance == value
        option.button.BackgroundColor3 = Color3.fromHex(selected and "#67ED14" or "#638079")
        option.edge.BackgroundColor3 = Color3.fromHex(selected and "#225A07" or "#263E36")
    end

    for setting, toggle in pairs(self.Toggles) do
        local enabled = state[setting]
        toggle.button.BackgroundColor3 = Color3.fromHex(
            enabled and "#45A85A" or "#638079"
        )
        toggle.edge.BackgroundColor3 = Color3.fromHex(
            enabled and "#1D542A" or "#263E36"
        )
        if enabled then
            toggle.text.Text = Text.Tr(TranslationTexts.On)
        else
            toggle.text.Text = Text.Tr(TranslationTexts.Off)
        end
    end
end

-- 游戏接入必须处理本界面的动作。
-- @param action string ChangeSetting 或 Close
-- @param payload table 设置键与新值，或 Close 的空表
function CSettingsView:OnUIAction(action, payload)
    error("Settings integration must implement OnUIAction: " .. tostring(action))
end

return CSettingsView
