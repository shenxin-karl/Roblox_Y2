# 数据同步示例

当前 `PlayerDataConfig` 已声明 Coins。下列为字段结构示意；使用现有定义，不重复新增或改写存档 Key 与数据域：

```lua
Coins = {
    Type = "number",
    Key = "Coins",
    DefVal = 0,
    Sync = true,
    KVTable = PlayerKVEnum.ePlayerData,
},
```

取得当前配置并在已初始化的服务端玩家组件写入：

```lua
local PlayerDataConfig = _G.PlayerDataConfig -- 在 GameInit 完成后使用
self:AddNumber(PlayerDataConfig.Coins, amount)
```

客户端组件在 Ctor 中绑定已确认的 TextLabel。监听会先回放当前值，无需另外初始化同一文案：

```lua
local FX = _G.FX
local GameUtility = FX.Loader:RequireShared("Scripts.Game.Shared.GameUtility")
self:WatchDataChanged(PlayerDataConfig.Coins, function(value)
    coinsLabel.Text = GameUtility.NumberToText(value)
end)
```

amount 必须来自已通过服务端业务验证的计算；示例不新增“客户端指定发钱”的协议。
如用于通用 Money 奖励，还需设置 `GameConfig.RewardCurrencies.Money = "Coins"`。
