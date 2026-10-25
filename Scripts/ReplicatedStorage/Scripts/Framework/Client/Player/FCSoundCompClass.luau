local FX, FC, MS = _G.FX, _G.FC, _G.Rbx

local LocalPlayer = MS.Players.LocalPlayer

---@class FCSoundCompClass: FCPlayerCompClass
local FCSoundCompClass = FX.Class("FCSoundCompClass", "FCPlayerCompClass")
FC.SoundCompClass = FCSoundCompClass

--- 构造客户端声音通用组件，统一初始化 BGM 声道和短音效声音池。
---@param owner FCPlayerObjectClass 玩家对象，供组件按玩家生命周期挂载声音节点。
---@param effectSoundPoolCount number 短音效声音池数量，由派生业务组件构造时明确指定。
---@return nil
function FCSoundCompClass:Ctor(owner, effectSoundPoolCount)
    FCSoundCompClass.Super.Ctor(self, owner)
    self._isSwitchingBGM = false
    self._currentBGMIndex = 1
    self._nextEffectSoundNodeIndex = 1
    self._characterNode = self:GetCharacterNode()
    self._soundBGM = self:EnsureSoundNode(self._characterNode, "SoundBGM")
    self._soundGroup2D = self:EnsureSoundGroupNode(self._characterNode, "SoundGroup2D")
    self._exclusiveEffectSoundNode = self:EnsureSoundNode(self._soundGroup2D, "SoundEffectExclusive")
    self._effectSoundNodeList = {}
    self._effectSoundPauseBGMMap = {}
    self._effectSoundDuckBGMMap = {}
    self:SetEffectSoundPoolCount(effectSoundPoolCount)
    self._soundBGM.Ended:Connect(function()
        if self._isSwitchingBGM then
            return
        end
        self:PlayNextBGM()
    end)
    self:PlayBGMByIndex(self._currentBGMIndex)
end

--- 返回组件名，基类仅用于继承，业务组件需要重写为稳定入口名。
---@param self FCSoundCompClass 声音组件实例。
---@return string
function FCSoundCompClass:GetCompName()
    return "FCSoundComp"
end

--- 获取本地角色节点，保证声音节点始终挂在玩家对象身上。
---@param self FCSoundCompClass 声音组件实例。
---@return SandboxNode
function FCSoundCompClass:GetCharacterNode()
    local folder = Instance.new("Folder")
    folder.Name = "FrameworkSounds"
    folder.Parent = game:GetService("SoundService")
    return folder
end

--- 返回 BGM 配置列表，派生类按业务场景提供每首 BGM 的资源与音量。
---@param self FCSoundCompClass 声音组件实例。
---@return table bgmSoundConfigList
function FCSoundCompClass:GetBGMSoundIdList()
    return {}
end

--- 复用已有声音节点或补建新节点，避免同名声道重复创建。
---@param self FCSoundCompClass 声音组件实例。
---@param parentNode SandboxNode 父节点。
---@param nodeName string 声音节点名。
---@return SandboxNode
function FCSoundCompClass:EnsureSoundNode(parentNode, nodeName)
    local soundNode = parentNode:FindFirstChild(nodeName)
    if soundNode ~= nil then
        return soundNode
    end

    soundNode = Instance.new("Sound", parentNode)
    soundNode.Name = nodeName
    return soundNode
end

--- 复用或创建音效分组节点，让短音效池统一挂在角色下的 SoundGroup2D。
---@param self FCSoundCompClass 声音组件实例。
---@param parentNode SandboxNode 玩家角色节点。
---@param nodeName string 分组节点名。
---@return SandboxNode
function FCSoundCompClass:EnsureSoundGroupNode(parentNode, nodeName)
    local group = Instance.new("Folder")
    group.Name = nodeName
    group.Parent = parentNode
    return group
end

--- 设置短音效声音池数量，重建固定声道以控制同屏音效节点上限。
---@param self FCSoundCompClass 声音组件实例。
---@param soundPoolCount number 声音池节点数量，最少保留 1 个声道保证播放入口可用。
---@return nil
function FCSoundCompClass:SetEffectSoundPoolCount(soundPoolCount)
    self:DestroyEffectSoundPool()
    self._effectSoundNodeList = {}
    self._nextEffectSoundNodeIndex = 1
    local nextSoundPoolCount = math.max(1, soundPoolCount)
    for nodeIndex = 1, nextSoundPoolCount do
        local soundNode = self:EnsureSoundNode(self._soundGroup2D, string.format("SoundEffect%d", nodeIndex))
        soundNode.Ended:Connect(function()
            self:OnEffectSoundPlayFinish(soundNode)
        end)
        self._effectSoundNodeList[nodeIndex] = soundNode
    end
end

--- 销毁当前短音效池节点，避免重建声音池时残留旧声道。
---@param self FCSoundCompClass 声音组件实例。
---@return nil
function FCSoundCompClass:DestroyEffectSoundPool()
    for nodeIndex = 1, #self._effectSoundNodeList do
        self:OnEffectSoundPlayFinish(self._effectSoundNodeList[nodeIndex])
        self._effectSoundNodeList[nodeIndex]:Destroy()
    end
end

--- 轮转获取下一个短音效节点，让高频音效复用固定声道池。
---@param self FCSoundCompClass 声音组件实例。
---@return SandboxNode
function FCSoundCompClass:GetNextEffectSoundNode()
    local soundNode = self._effectSoundNodeList[self._nextEffectSoundNodeIndex]
    self:OnEffectSoundPlayFinish(soundNode)
    self._nextEffectSoundNodeIndex = self._nextEffectSoundNodeIndex + 1
    if self._nextEffectSoundNodeIndex > #self._effectSoundNodeList then
        self._nextEffectSoundNodeIndex = 1
    end
    return soundNode
end

--- 按索引播放指定 BGM，播放完成后由 PlayFinish 自动切到下一首。
---@param self FCSoundCompClass 声音组件实例。
---@param bgmIndex number BGM 列表下标。
---@return nil
function FCSoundCompClass:PlayBGMByIndex(bgmIndex)
    local bgmSoundConfigList = self:GetBGMSoundIdList()
    if #bgmSoundConfigList <= 0 then
        return
    end
    local nextBGMIndex = bgmIndex
    if nextBGMIndex < 1 then
        nextBGMIndex = #bgmSoundConfigList
    end
    if nextBGMIndex > #bgmSoundConfigList then
        nextBGMIndex = 1
    end
    local bgmSoundConfig = bgmSoundConfigList[nextBGMIndex]
    self._currentBGMIndex = nextBGMIndex
    self._isSwitchingBGM = true
    self._soundBGM:Stop()
    self._soundBGM.SoundId = bgmSoundConfig.bgmId
    self._soundBGM.Volume = bgmSoundConfig.volume
    self._soundBGM.Looped = false
    self._isSwitchingBGM = false
    self:RefreshBGMVolumeForDuckEffects()
    self._soundBGM:Play()
end

--- 当前 BGM 播放完成后切换到下一首，列表末尾回到第一首。
---@param self FCSoundCompClass 声音组件实例。
---@return nil
function FCSoundCompClass:PlayNextBGM()
    local bgmSoundConfigList = self:GetBGMSoundIdList()
    if #bgmSoundConfigList <= 0 then
        return
    end
    local nextIndex = self._currentBGMIndex + 1
    if nextIndex > #bgmSoundConfigList then
        nextIndex = 1
    end
    self:PlayBGMByIndex(nextIndex)
end

--- 播放指定短音效，统一走声音池避免无限创建节点。
---@param self FCSoundCompClass 声音组件实例。
---@param soundId string 音效 sandboxId。
---@param volume number 音效音量。
---@return nil
function FCSoundCompClass:PlayEffectSound(soundId, volume)
    local soundNode = self:GetNextEffectSoundNode()
    soundNode:Stop()
    soundNode.SoundId = soundId
    soundNode.Volume = volume
    soundNode.Looped = false
    soundNode:Play()
end

--- 在独占声道重播短音效，先暂停上一次播放，再从头播放本次音效。
---@param self FCSoundCompClass 声音组件实例。
---@param soundId string 音效 sandboxId。
---@param volume number 音效音量。
---@return nil
function FCSoundCompClass:PlayExclusiveEffectSound(soundId, volume)
    self._exclusiveEffectSoundNode:Stop()
    self._exclusiveEffectSoundNode.SoundId = soundId
    self._exclusiveEffectSoundNode.Volume = volume
    self._exclusiveEffectSoundNode.Looped = false
    self._exclusiveEffectSoundNode:Play()
end

--- 按当前播放中的压低请求刷新 BGM 音量，多音效重叠时采用最低倍率。
---@param self FCSoundCompClass 声音组件实例。
---@return nil
function FCSoundCompClass:RefreshBGMVolumeForDuckEffects()
    if next(self._effectSoundPauseBGMMap) ~= nil then
        return
    end

    local bgmSoundConfigList = self:GetBGMSoundIdList()
    if #bgmSoundConfigList <= 0 then
        return
    end

    local volumeScale = 1
    for soundNode, duckVolumeScale in pairs(self._effectSoundDuckBGMMap) do
        volumeScale = math.min(volumeScale, duckVolumeScale)
    end
    self._soundBGM.Volume = bgmSoundConfigList[self._currentBGMIndex].volume * volumeScale
end

--- 处理短音效播放结束，恢复暂停或压低的背景音乐状态。
---@param self FCSoundCompClass 声音组件实例。
---@param soundNode SandboxNode 已播放结束的短音效节点。
---@return nil
function FCSoundCompClass:OnEffectSoundPlayFinish(soundNode)
    local wasPausingBGM = self._effectSoundPauseBGMMap[soundNode] == true
    local wasDuckingBGM = self._effectSoundDuckBGMMap[soundNode] ~= nil
    if not wasPausingBGM and not wasDuckingBGM then
        return
    end

    self._effectSoundPauseBGMMap[soundNode] = nil
    self._effectSoundDuckBGMMap[soundNode] = nil
    if next(self._effectSoundPauseBGMMap) ~= nil then
        return
    end
    if wasPausingBGM then
        self._soundBGM:Resume()
    end
    self:RefreshBGMVolumeForDuckEffects()
end

--- 播放需要突出表现的短音效，播放期间只压低 BGM 音量而不中断进度。
---@param self FCSoundCompClass 声音组件实例。
---@param soundId string 音效 sandboxId。
---@param volume number 音效音量。
---@param bgmVolumeScale number BGM 相对当前曲目配置音量的倍率。
---@return nil
function FCSoundCompClass:PlayEffectSoundWithBGMDuck(soundId, volume, bgmVolumeScale)
    local soundNode = self:GetNextEffectSoundNode()
    self._effectSoundPauseBGMMap[soundNode] = nil
    self._effectSoundDuckBGMMap[soundNode] = nil
    soundNode:Stop()
    self._effectSoundDuckBGMMap[soundNode] = bgmVolumeScale
    self:RefreshBGMVolumeForDuckEffects()
    soundNode.SoundId = soundId
    soundNode.Volume = volume
    soundNode.Looped = false
    soundNode:Play()
end

--- 播放需要突出表现的短音效，并在播放期间暂停背景音乐。
---@param self FCSoundCompClass 声音组件实例。
---@param soundId string 音效 sandboxId。
---@param volume number 音效音量。
---@return nil
function FCSoundCompClass:PlayEffectSoundWithBGMPause(soundId, volume)
    local soundNode = self:GetNextEffectSoundNode()
    self._effectSoundPauseBGMMap[soundNode] = nil
    self._effectSoundDuckBGMMap[soundNode] = nil
    soundNode:Stop()
    self._isSwitchingBGM = true
    self._soundBGM:Pause()
    self._isSwitchingBGM = false
    self._effectSoundPauseBGMMap[soundNode] = true
    soundNode.SoundId = soundId
    soundNode.Volume = volume
    soundNode.Looped = false
    soundNode:Play()
end

--- 析构自有声音树，结束事件随节点一并释放。
function FCSoundCompClass:Dtor()
    self._characterNode:Destroy()
    FCSoundCompClass.Super.Dtor(self)
end
return FCSoundCompClass
