# 声音组件

基类：`ReplicatedStorage/Scripts/Framework/Client/Player/FCSoundCompClass.luau`，
基类由 FClient require；项目 `StarterPlayerScripts/Client/Player/CSoundCompClass.luau` 已继承它，并在 CPlayerObjectClass 中挂载。

需要声音时先复用现有 CSoundCompClass，按需求调整 GetBGMSoundIdList 或调用已有方法，不重复新增或挂载声音组件。
当前 Ctor(owner, effectSoundPoolCount) 创建 SoundService 下的独立音频池。
常用方法：
- PlayBGMByIndex(index)/PlayNextBGM()
- PlayEffectSound(soundId, volume)
- PlayExclusiveEffectSound(soundId, volume)
- PlayEffectSoundWithBGMDuck(soundId, volume, bgmVolumeScale)
- PlayEffectSoundWithBGMPause(soundId, volume)

soundId 必须是体验可使用的 Roblox 音频资源 URI。没有授权 ID 时明确缺少资源，
不捏造资源 ID。
默认音量和池大小以当前代码为准；没有需求不创建额外配置层。
覆盖 Dtor 调 Super，释放池和连接；世界定位音效按需求另用真实 Sound/Attachment，
不要假设当前池已经有三维定位支持。
