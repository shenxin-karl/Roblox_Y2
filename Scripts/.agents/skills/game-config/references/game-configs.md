# 配置分类与组织

本文件说明采用本配置体系的游戏如何分类数据，不绑定某个游戏的玩法、代码路径或当前表内容。
以下文件名和常用子表名沿用这套配置约定；实际子表和字段须读取当前工程，不能当成所有游戏必须具有的完整 schema。
Meta、支持类型、Excel 布局和完整导出示例见同目录 `mcp-and-format.md`，需要时再加载。

## 1. 五类配置各负责什么

| 文件 | 职责 | 典型数据 |
| --- | --- | --- |
| `GoodsConfig.xlsx` 商品配置 | 定义买什么、花多少、怎么结算、发什么 | 商品 ID、价格、限购、购买处理器、奖励参数；可按付费渠道或货币拆子表 |
| `ShopConfig.xlsx` 商店配置 | 定义商品在哪个页面展示、按什么顺序或分组上架 | 页签、页面类、条目类、商品引用、名称/描述/图标展示覆盖 |
| `ItemConfig.xlsx` 道具配置 | 定义道具本身及其展示、使用行为和实例额外数据 | 道具 ID、类型、最大堆叠、使用/手持处理器、名称、品质、图标、额外数据默认值 |
| `GameConfig.xlsx` 游戏配置 | 承载具体玩法规则；通用小字段集中存放，有成组记录的数据单独开表 | CommonConfig 中的全局参数；独立的关卡、装备、技能、怪物、掉落等玩法表 |
| `ActivityConfig.xlsx` 一般活动配置 | 定义任务、登录、在线等活动的条件、目标和奖励 | 任务类型、目标次数、登录天数、在线时长、活动阶段、奖励 |

选择配置时按职责判断：卖一瓶药水的价格和发奖写商品；商店的展示位置写商店；药水堆叠和使用效果写道具；战斗伤害规则写游戏；登录送药水的条件和奖励写活动。
一个功能可以涉及多个配置文件，通过 ID 关联，不需要把所有数据塞入同一类。

## 2. 商品配置：交易定义

常用子表按交易渠道拆分，例如 GoodsData、GemGoodsData；也可有独立的商品奖励表。
每件商品通常使用 struct 记录，含自身主键、Price、BuyHandler、BuyLimit 及额外参数。

- 商品 ID 是交易定义的键，不能与道具 ID 或平台真实商品 ID 默认混用。
- 同一个道具可以被多件商品出售，例如不同数量或折扣档位。
- NumberArray、KVTable 等扩展数据的含义由购买处理器决定；导出器只解析类型，不会自动执行奖励。
- 若使用 GoodsItemData 一类奖励表，商品如何引用它由当前游戏代码约定，不假设所有商品都经过该表。
- 平台付费价格、云端商品 ID 的维护独立于普通配置导出；修改表格不等于已修改平台商品。

概念关联：`商店条目 → 商品定义 → 道具或其他奖励`。商品也可以提供货币、解锁、服务或升级，不必总对应一个道具。

## 3. 商店配置：上架与展示

常见结构：

| 子表角色 | 常用名字示例 | 主要内容 |
| --- | --- | --- |
| 页签定义 | TabData | PageName、Name、ClassName、PageItemClassName、ConfigName |
| 商品展示列表 | MiniCoinData、GemCoinData 或其他渠道列表 | 行主键、商品 ID、分组、展示名称、描述、图标 |

商店行引用商品配置的主键；展示列表中的 Index 常用于排序或定位，通常不是商品 ID。
Group 可以被业务用于分组或升级档位，具体语义需查代码；不能把所有游戏的 Group 都理解成同一种购买规则。
新增商店条目时同时确认商品定义存在、目标页面读取该列表、必要的页面/条目类已接入。

## 4. 道具配置：逻辑、展示与额外数据

道具配置通常由两张基础表组成：Data 定义道具逻辑，Display 定义道具展示，两者用同一个道具 ID 关联。需要运行时额外数据的道具类型，再通过 ExtraDataSchema 声明实例额外存储的字段及默认值。

| 子表 | 常见格式 | 职责 |
| --- | --- | --- |
| Data | struct，按道具 Id | 道具的静态逻辑配置：Type、MaxStack、UseHandler、HeldHandler 和逻辑参数 |
| Display | struct，按同一个道具 Id | 道具的静态展示配置：Name、Desc、Quality、IconId、DisplayModelId |
| ExtraDataSchema | table，按 Data.Type | 定义该道具类型的运行时额外数据字段及默认值，例如等级、经验、尺寸、变异进度 |

### ExtraDataSchema 的运行时语义

同一种道具的不同实例可以具有不同的运行时状态。例如两只相同道具 ID 的宠物，可以分别具有不同等级和经验；这些实例值保存在各自的 extraData 中。
ExtraDataSchema 按道具 Type 声明可用字段和默认值，实例通过 Data.Type 找到对应声明。读取实例额外数据时，将类型默认值与实例已有值合并，实例值覆盖默认值。
实例 extraData 随道具实例序列化与恢复；Schema 本身作为静态配置导出，不用来保存某个玩家或某件道具的当前状态。读取时补齐默认值不等于已经将默认值写回存档。

例如 ExtraDataSchema 页签中的一行（示例类型名需替换为当前游戏实际类型）：

| MetaInfo | Key | Value |
| --- | --- | --- |
| string,kv_string | Pet | level=1,exp=0,size=1 |

导出后的类型声明片段：

```lua
ExtraDataSchema = {
    Pet = { level = 1, exp = 0, size = 1 }
}
```

对于 Data.Type 为 Pet 的某个实例，若其保存的 extraData 为 `{level=5,exp=20}`，读取合并结果就是 `{level=5,exp=20,size=1}`；其他实例仍可使用各自的等级和经验。
修改 Schema 默认值会影响读取时尚未保存对应字段的实例；已有实例值仍覆盖默认值，不自动迁移全部历史存档。
新增额外字段时，在相应类型的 Schema 中声明，并核对实例创建、读写及存储逻辑。运行时是否检查字段或值类型，以使用的框架为准，不把 Schema 默认值当成完整类型校验器。

Data 中的 NumberArray/KVTable 属于同一道具定义共享的静态参数；实例 extraData 承载每件道具可变化的状态。ExtraDataSchema 描述的是后者的字段与默认值，Excel 第 3 行 Meta 描述的则是单元格导出类型。

UseHandler、HeldHandler 只是接入代码的名称；配置中新增名称不会自动实现使用或手持效果。
游戏也可能有场景采集物、临时掉落物等独立玩法表。它们是否关联道具表，以游戏代码为准，不把同名 ItemData 自动视为 ItemConfig.Data。

## 5. 游戏配置：通用小字段 + 独立玩法表

### CommonConfig 存通用小字段

只有一个值或少量相关参数、无需大量同构记录的配置，放 CommonConfig，采用 table 格式：

| MetaInfo | Key | Value |
| --- | --- | --- |
| string,number | MaxPlayerCount | 8 |
| string,bool | EnableTrading | true |
| string,kv_string | OfflineReward | MaxSeconds=14400,Rate=0.25 |

导出后直接按条目键读取：`GameConfig.CommonConfig.MaxPlayerCount`、`GameConfig.CommonConfig.OfflineReward.Rate`。
每行可有自己的值类型；“通用小字段”也可以是少量参数组成的 KV，并不要求都为标量。

### 成组数据独立开表

当同一类数据有多条记录、相同字段、需要按 ID 查找或持续扩展时，在 GameConfig.xlsx 内独立开数据页签，通常采用 struct：

- 关卡表：每关一行，主键可为数字 ID 或字符串关卡键。
- 装备表：每件装备一行，字段包含价格、属性、模型等。
- 怪物/技能/掉落规则表：每种对象或规则一行，按业务定义字段。

这些是组织示例，不要求所有游戏创建这些表。优先沿用当前游戏已有的子表和主键。
新增物理页签后，要在首个索引页声明子配置键、键类型、struct/table、主键字段和页签名，才会进入导出。
不把大量同构关卡写成 CommonConfig 的 Level1HP、Level2HP 等零散键；也无需为一个普通开关单独开 struct 表。

## 6. 活动配置：条件与奖励

一般活动数据按活动类型或规则单独开 struct 子表，例如：

| 子表示例 | 大概内容 |
| --- | --- |
| DailyTaskConfig | 任务类型、描述、目标次数/时长、奖励列表 |
| LoginMilestoneData | 累计登录天数或签到档位、奖励 |
| OnlineRewardData | 在线时长门槛、奖励 |

门槛字段要按业务命名和解释单位；TargetMinutes 与秒数不能混用。
单个奖励可用 kv_string，多项奖励可用 kv_string_array。例如单项 `Type=Item,Id=101,Count=1`，列表 `{Type=Item,Id=101,Count=1},{Type=Gem,Count=5}`。
这只是单元格格式示例；Type、Id/ItemId、Count 的具体契约由游戏奖励入口决定。通用导出器不会校验某个道具存在，也不负责把活动奖励转换成底层发奖接口。

## 7. 分类与导出结构的关系

五类工作簿共用同一种索引、struct/table 和字段类型协议，不是五套导出格式。

- 文件决定顶层模块名：`GameConfig.xlsx` → GameConfig 配置模块。
- 索引行的子配置键决定模块的一级字段：CommonConfig、LevelData 等。
- table 导出 `配置模块[子配置键][条目键] = 值`。
- struct 导出 `配置模块[子配置键][记录主键] = {字段=值,...}`，记录中保留主键字段。
- 数值主键 `1` 与字符串主键 `"1"` 不同；物理 Excel 行号不会自动成为记录键。

例如 GameConfig 中同时使用 CommonConfig 和 LevelData，导出后的访问分别是 `GameConfig.CommonConfig.MaxPlayerCount` 与 `GameConfig.LevelData[1].HP`。
具体输入表与 Lua/Luau 输出的一一对应，见 `mcp-and-format.md` 第 5 节；生成配置成功后，仍要由游戏代码加载并按字段约定使用。
