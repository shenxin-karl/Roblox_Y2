-- 项目音效：到账提示及锻造锤击、结果的分层播放。
local ContentProvider = game:GetService("ContentProvider")
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local MONEY_RECEIVED_SOUND_ID = "rbxassetid://99533862853751"
local ForgeHits = {
    "rbxassetid://87978634320654", -- ForgeStrike_0
    "rbxassetid://98535355239875", -- ForgeStrike_1
    "rbxassetid://116302063903792", -- ForgeStrike_2
    "rbxassetid://88502074039433", -- ForgeStrike_3
    "rbxassetid://126730497785496", -- ForgeStrike_4
    "rbxassetid://84592739121548", -- ForgeStrike_5
}
local ForgeReward = "rbxassetid://92471176398673"
local ForgeBreak = "rbxassetid://121796441231976"
local ForgeContactIds = {
    Set = "rbxassetid://77579522005024",
    Lift = "rbxassetid://73848786835328",
    Lift2 = "rbxassetid://80907945527365",
}
local MiningClawSounds = {
    CastClick = {Id = "rbxassetid://78842333035198", Volume = 0.4},
    Cast = {Id = "rbxassetid://78365050160673", Volume = 0.65},
    CatchStone = {Id = "rbxassetid://137485529581452", Volume = 0.6},
    Catch = {Id = "rbxassetid://106460386709000", Volume = 0.6},
    CatchRare = {Id = "rbxassetid://84466225714300", Volume = 0.65},
    Reel = {Id = "rbxassetid://75271414645021", Volume = 0.4},
    Keep = {Id = "rbxassetid://78842333035198", Volume = 0.45},
    Discard = {Id = "rbxassetid://137485529581452", Volume = 0.35},
}

---@class CSoundCompClass: FCSoundCompClass
local CSoundCompClass = FX.Class("CSoundCompClass", "FCSoundCompClass")

--- 预先绑定锤声和钩爪声，播放时不切换资源。
--- @param owner CPlayerObjectClass 当前客户端玩家对象。
function CSoundCompClass:Ctor(owner)
    CSoundCompClass.Super.Ctor(self, owner, 4)
    self._forgeHitSounds = {}
    for index, soundId in ipairs(ForgeHits) do
        local sound = self:EnsureSoundNode(self._soundGroup2D, "ForgeStrike_" .. (index - 1))
        sound.SoundId = soundId
        self._forgeHitSounds[index] = sound
    end
    self._forgeHitIndex = 1
    self._forgeDamageSound = self:EnsureSoundNode(self._soundGroup2D, "SwordDamage")
    self._forgeDamageSound.SoundId = "rbxassetid://81873812444168"
    self._forgeDamageSound.Volume = 0.48
    self._forgeContacts = {}
    for cue, id in pairs(ForgeContactIds) do
        local sound = self:EnsureSoundNode(self._soundGroup2D, "Sword" .. cue)
        sound.SoundId, sound.Volume = id, 0.48
        self._forgeContacts[cue] = sound
    end
    self._forgeStreak = 0
    self._miningClawSounds = {}
    for name, config in pairs(MiningClawSounds) do
        local sound = self:EnsureSoundNode(self._soundGroup2D, "MiningClaw" .. name)
        sound.SoundId = config.Id
        sound.Volume = config.Volume
        self._miningClawSounds[name] = sound
    end
end

--- 提供项目声音组件的稳定协作名称。
--- @return string 组件协作名称。
function CSoundCompClass:GetCompName()
    return "CSoundComp"
end

--- 就绪后监听服务端同步的现金和钻石余额，覆盖各个发奖入口。
function CSoundCompClass:OnReady()
    task.defer(function()
        local sounds = table.clone(self._forgeHitSounds)
        table.insert(sounds, self._forgeDamageSound)
        for _, sound in pairs(self._forgeContacts) do
            table.insert(sounds, sound)
        end
        for _, soundId in ipairs({ForgeReward, ForgeBreak}) do
            local sound = Instance.new("Sound")
            sound.SoundId = soundId
            table.insert(sounds, sound)
        end
        for name, sound in pairs(self._miningClawSounds) do
            table.insert(sounds, sound)
        end
        ContentProvider:PreloadAsync(sounds)
    end)
    self:WatchDataChanged(Fields.Money, self.OnCurrencyChanged, self)
    self:WatchDataChanged(Fields.Diamonds, self.OnCurrencyChanged, self)
end

--- 砧面放剑只响一次；从砧面取走成品时交替使用两种金属摩擦声。
--- @param cue string Set 或 Lift，由已确认的台上状态变化触发。
function CSoundCompClass:PlayForgeContact(cue)
    if cue == "Lift" then
        cue = self._nextForgeLift or "Lift"
        self._nextForgeLift = if cue == "Lift" then "Lift2" else "Lift"
    end
    self._forgeContacts[cue]:Play()
end

--- 播放一个本地钩爪音，不抢占锻造和到账音的共享声池。
--- @param cue string 钩爪音效名。
function CSoundCompClass:PlayMiningClawSound(cue)
    local sound = self._miningClawSounds[cue]
    sound:Stop()
    sound:Play()
end

--- 原版 18 FPS 的收绳循环在第 2、9 帧发声，第 20 帧跳回第 1 帧。
--- @param now number 当前服务端时间。
--- @param returnAt number 这次回收开始的服务端时间。
function CSoundCompClass:UpdateMiningClawReel(now, returnAt)
    if not self._miningClawReelAt then
        self._miningClawReelAt = returnAt + 1 / 18
        self._miningClawReelShortGap = true
    end
    if now >= self._miningClawReelAt then
        self:PlayMiningClawSound("Reel")
        local gap = (if self._miningClawReelShortGap then 7 else 12) / 18
        local nextAt = self._miningClawReelAt + gap
        self._miningClawReelAt = if nextAt > now then nextAt else now + gap
        self._miningClawReelShortGap = not self._miningClawReelShortGap
    end
end

--- 到站、取消或离座时停止收绳并清除这次循环的节拍。
function CSoundCompClass:StopMiningClawReel()
    if self._miningClawReelAt then
        self._miningClawReelAt = nil
        local sound = self._miningClawSounds.Reel
        if sound.Parent then
            sound:Stop()
        end
    end
end

--- 奖励音与到账音共享声池，复用前恢复默认速度。
function CSoundCompClass:GetNextEffectSoundNode()
    local sound = CSoundCompClass.Super.GetNextEffectSoundNode(self)
    sound:Stop()
    sound.PlaybackSpeed = 1
    return sound
end

--- 落锤时轮播金属撞击。结果还没到时保持基础音色。
--- @param outcome string? 服务端已确认的本锤结果。
function CSoundCompClass:PlayForgeHit(outcome)
    local speed, volume = 1, 0.8
    if outcome == "Success" then
        speed, volume = 1.02, 0.9
    elseif outcome == "Unchanged" then
        speed, volume = 0.96, 0.7
    elseif outcome == "Broken" then
        speed, volume = 0.98, 0.68
    elseif outcome == "Destroyed" then
        speed, volume = 0.68, 0.3
    end
    local sound = self._forgeHitSounds[self._forgeHitIndex]
    self._forgeHitIndex = self._forgeHitIndex % #self._forgeHitSounds + 1
    sound.Volume = volume
    sound.PlaybackSpeed = speed
    sound:Play()
end

--- 结果音和锤声使用不同声道；不变和停锻均不播放碎剑声。
--- @param outcome string 本锤结果。
--- @param firstHammer boolean? 是否为新剑第一锤。
function CSoundCompClass:PlayForgeResult(outcome, firstHammer)
    if firstHammer or outcome ~= "Success" then
        self._forgeStreak = 0
    end
    if outcome == "Success" then
        self._forgeStreak += 1
        local sound = self:GetNextEffectSoundNode()
        sound.SoundId = ForgeReward
        sound.Volume = 0.32 * 0.35
        sound.PlaybackSpeed = 1 + math.min(self._forgeStreak - 1, 5) * 0.06
        sound:Play()
    elseif outcome == "Broken" then
        self._forgeDamageSound:Play()
    elseif outcome == "Destroyed" then
        self:PlayEffectSound(ForgeBreak, 0.65)
    end
end

--- 只在余额实际增加时播放，首次同步和消费不播放。
--- @param balance number 当前余额。
--- @param previousBalance number? 同步前的余额，首次同步时为空。
function CSoundCompClass:OnCurrencyChanged(balance, previousBalance)
    if previousBalance ~= nil and balance > previousBalance then
        self:PlayEffectSoundWithBGMDuck(MONEY_RECEIVED_SOUND_ID, 2, 0.2)
    end
end

return CSoundCompClass
