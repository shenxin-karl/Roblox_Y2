local FX = _G.FX
local LocalizationService = game:GetService("LocalizationService")
local RunService = game:GetService("RunService")
local Text = FX.Text
local Localization = {}
Localization.__index = Localization

--- 本地英文不依赖云端；云端加载在后台进行，不阻塞玩家组件初始化。
--- @param player Player 当前本地玩家。
--- @return table 当前玩家的翻译对象，Changed 为文案刷新信号。
function Localization.New(player)
    local self = setmetatable({}, Localization)
    self._changed = Instance.new("BindableEvent")
    self.Changed = self._changed.Event
    -- 未发布的本地场景没有云端翻译表，直接使用英文回退。
    if game.GameId == 0 then
        return self
    end
    --- 后台获取云端译文，失败不影响离线文案。
    self._loadTask = task.defer(function()
        -- 平台请求可能失败；有限重试后继续使用本地英文。
        for attempt = 1, 3 do
            --- Studio 跟随模拟语言，正式游戏跟随玩家当前体验语言。
            --- @return Translator 平台加载的翻译器。
            local success, translator = pcall(function()
                if RunService:IsStudio() then
                    return LocalizationService:GetTranslatorForLocaleAsync(LocalizationService.RobloxLocaleId)
                end
                return LocalizationService:GetTranslatorForPlayerAsync(player)
            end)
            if self._destroyed then
                return
            end
            if success then
                self._cloud = translator
                self._changed:Fire()
                --- Roblox 游戏内切换语言由 Translator 的 LocaleId 变化通知。
                self._cloudConnection = translator:GetPropertyChangedSignal("LocaleId"):Connect(function()
                    self._changed:Fire()
                end)
                self._loadTask = nil
                return
            end
            warn("Localization: cloud translator request " .. attempt .. " failed: " .. tostring(translator))
            if attempt < 3 then
                task.wait(5)
            end
        end
        self._loadTask = nil
        warn("Localization: cloud translator unavailable; using local English.")
    end)
    return self
end

--- 使用定义自带英文格式化，避免从同文旧 Key 查到其他场景译文。
--- @param source string 英文原文或原生参数模板。
--- @param arguments table? 原生模板参数。
--- @return string 格式化后的英文。
function Localization:FormatSource(source, arguments)
    if not arguments then
        return source
    end
    if not self._sourceFallback then
        self._sourceFallback = Instance.new("LocalizationTable")
        self._sourceFallback.SourceLocaleId = "en-us"
    end
    self._sourceFallback:SetEntryValue(source, source, "", "en-us", source)
    return self._sourceFallback:GetTranslator("en-us"):FormatByKey(source, arguments)
end

--- 只按定义 Key 查云端；失败使用该定义的英文，不接受字符串或旧 Key 映射。
--- @param definition table 含 Key、Source 的完整文案定义。
--- @param arguments table? 原生模板参数，itemDefinition 或 itemSource 在客户端翻译成 item。
--- @return string 当前玩家语言的文案，缺译时使用格式化后的英文。
function Localization:Tr(definition, arguments)
    Text.ValidateDefinition(definition)
    if arguments and (arguments.itemDefinition or arguments.itemSource) then
        arguments = table.clone(arguments)
        if arguments.itemDefinition then
            arguments.item = self:Tr(arguments.itemDefinition)
            arguments.itemDefinition = nil
        else
            arguments.item = self:TrSource(arguments.itemSource)
            arguments.itemSource = nil
        end
    end
    if self._cloud and string.match(string.lower(self._cloud.LocaleId), "^[^-]+") ~= "en" then
        --- 不要求语义 Key 已进入本地旧表，也不按英文匹配其他条目。
        --- @return string 按语义 Key 格式化的云端文案。
        local success, text = pcall(function()
            return self._cloud:FormatByKey(definition.Key, arguments)
        end)
        if success and text ~= "" then
            return text
        end
    end
    return self:FormatSource(definition.Source, arguments)
end

--- 原文查找使用 Roblox 原生 Translate，不将原文当 Key，也不遍历语义定义表。
--- @param source string 完整原文；不传模板参数，带参数的语义文案使用 Tr。
--- @return string 当前语言译文；缺译、未加载、查询报错或空译文时返回原文。
function Localization:TrSource(source)
    assert(type(source) == "string", "Localization.TrSource expects a source string")
    if self._cloud and source ~= "" then
        --- game 作为默认语境；同文不同义的场景使用按 Key 翻译入口区分。
        --- @return string 由当前翻译器按原文匹配的译文。
        local success, text = pcall(function()
            return self._cloud:Translate(game, source)
        end)
        if success and text ~= "" then
            return text
        end
    end
    return source
end

--- 释放本对象的后台请求任务、临时英文表和语言监听，避免销毁后更新界面。
function Localization:Destroy()
    self._destroyed = true
    if self._loadTask then
        task.cancel(self._loadTask)
        self._loadTask = nil
    end
    if self._cloudConnection then
        self._cloudConnection:Disconnect()
    end
    if self._sourceFallback then
        self._sourceFallback:Destroy()
    end
    self._changed:Destroy()
end

return Localization
