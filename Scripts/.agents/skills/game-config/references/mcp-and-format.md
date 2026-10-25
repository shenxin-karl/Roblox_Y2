# MCP 调用与配置格式

用于配置操作、Meta 和导出协议。业务选表见同目录 `game-configs.md`，仅需要时加载。

## 1. 工具与版本流程

逻辑名为 `sgtk.config.*`；Codex 中通常显示为 `mcp__studio_game_toolkit__sgtk_config_*`。以当前连接暴露的 schema 为准，不猜未提供的工具或参数。
工具只访问当前工程配置目录直属 XLSX，忽略 `~$` 临时文件，不接受任意磁盘路径。先 list 核对工程和文件。

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `list` | `offset?`, `limit?` | 文件名、`sourceRevision`；按 `nextOffset` 翻页 |
| `check`（磁盘） | `filename`, `expectedSourceRevision?` | 在私有临时副本中按需重算并实际试导表；不修改源表或创建草稿 |
| `open` | `filename`, `expectedSourceRevision?`, `includeApi?`, `discardDraft?` | 打开/复用草稿；干净旧会话自动刷新；`discardDraft:true` 显式放弃旧草稿重载；首次用 book API 时加 `includeApi:true` |
| `execute_script` | `contextId`, `expectedDraftRevision`, `apiVersion:"1"`, `code` | 在草稿执行同步 JavaScript 函数体，用 `print(...args)` 输出查询结果到 `logs` |
| `check`（草稿） | `contextId`, `expectedDraftRevision` | 在临时副本中完整试导表，不修改草稿及其版本；不能同时传 filename/sourceRevision |
| `close` | `contextId`, `expectedDraftRevision` | 完整检查，必要时 WPS 重算，备份后保存；成功才关闭；不会更新 Luau 导出文件 |
| `export` | `filename`, `expectedSavedRevision` | 导出精确的已保存版本；不隐式保存草稿，有脏草稿时拒绝 |

普通查询：list → 磁盘 check（诊断时）或 open → execute_script 读取。
编辑：list → open → 查询目标 → execute_script 修改 → 草稿 check → close → 按任务需要 export。

- `contextId`、`draftRevision` 和源版本均取真实返回值。每次执行后使用返回的新 `draftRevision`，不要自行加一；只有实际变更才递增。
- `execute_script` 返回 `execution`、`draftRevision`，可选 `logs`、`logsTruncated`、`check`、`error`；不再返回 `result` 或 `changes`。顶层 `return` 不作为 MCP 查询输出。
- `print(...args)` 支持字符串、有限数值、布尔值、null、普通 JSON 对象和数组；字符串原样输出，其他值序列化为紧凑 JSON，多参数以空格分隔，不支持 printf 占位符。`logs` 是字符串数组，单次只输出一个对象/数组时可将该条日志按 JSON 解析。
- 无输出时省略 `logs`；每次最多 100 条、合计 65536 个 UTF-16 码元，超限截断并返回 `logsTruncated:true`，不导致修改失败。遇截断需缩小范围或分页重新查询，不能把截断 JSON 当作完整数据。
- 执行后仍自动检查草稿，但 `execute_script.check` 只在有错误或警告时出现，仅包含非空 `errors`、`warnings`；正常摘要和待检查项从独立 `sgtk.config.check` 获取。
- close 后使用返回的 `savedRevision` 作为 export 的 `expectedSavedRevision`。导出现有磁盘版本时先重新获取并核对该版本。
- 独立 `sgtk.config.check` 在私有临时副本中按需调用 WPS 重算并执行完整解析和 Lua/Luau 序列化；不保存源表、不更新草稿缓存、不覆盖正式导出文件。成功时 `export` 为 passed，不再有 `full_export` 待检查项。通过试导表不等于原表可保真保存，仍须 close；脚本内 `book.check()` 和 execute_script 附带检查不替代独立试导表。旧服务仍可能返回 pending，以实际响应为准，不把它当作已完成。
- 根据 `isError`、`execution`、顶层 error、`closed`、`saved` 和检查位置报告实际结果，不依赖某个可选字段一定存在；不同服务版本可能省略空数组、重复字段或 `readyToClose`。
- open 读取磁盘版本，不因 WPS 占用或无法确认状态直接拒绝打开；不会接管 WPS 中尚未保存的内容。check/close/export 仍检查占用；不关闭用户文档、删除锁文件或终止 WPS。外部版本冲突不强制覆盖或自动合并。
- 执行异常回滚本次脚本；普通异常和引擎超时尽量保留已输出日志，但不能据此认为修改生效；进程终止或资源耗尽时日志可能丢失。正常执行但检查失败保留草稿。草稿仅在内存中，不承诺重启恢复；可显式丢弃重载，但没有强制保存或自动合并接口。

### 重开、外部修改和丢弃草稿

- 磁盘内容未变时复用原 contextId 和草稿；磁盘已更新且没有未保存修改时自动重载。
- 有未保存修改且磁盘已变化时，默认报 REVISION_CONFLICT 并保留草稿。先判断旧草稿是否仍有需要保留的改动，不自动覆盖或丢弃。
- 确定以磁盘版本为准时，重新 list 获取最新 sourceRevision，再调用 open，传 filename、expectedSourceRevision 和 `discardDraft:true`。这会放弃该文件旧草稿的全部未保存修改，不写回旧内容。
- 只有加载成功后才替换旧草稿；返回新 contextId、draftRevision 为 0，旧上下文不可继续使用。加载失败、版本不匹配或超出配额时旧草稿仍保留。不要继续使用旧句柄或版本。
- 若当前服务 schema 未提供 discardDraft，不发送未知参数；报告需要加载新版服务，不用直接改文件、清后台状态或反复重启来绕过草稿保护。

## 2. book API 和查询示例

脚本是同步 JavaScript，不是 TypeScript/Node.js；无文件、网络、进程、import/require、异步能力。用 `print` 输出 JSON 数据，不输出 book/句柄本身、访问器、循环对象或自定义类型；不调用自定义序列化。
分页通常默认 50、最多 200；优先 print 目标字段或记录，避免整表输出。结构、键或类型改动后重新获取对象句柄。

```javascript
const rows = book.struct("GoodsData");
print({
  meta: rows.getMeta(),
  fields: rows.listFields(),
  records: rows.readRecords({ offset: 0, limit: 5 })
});
```

实际文件应先用 `book.listConfigs()` 找到子配置。`book.listSheets()` 可找未导出页签，`book.sheet(name).readRows({startRow:1,limit:5})` 可读取表头/说明。

| 对象 | 主要方法 |
| --- | --- |
| book | `listConfigs`, `config(key)`, `struct(key)`, `table(key)`, `listSheets`, `sheet(name)`, `addSheet`, `addConfig`, `removeConfig`, `check` |
| Config | `getMeta`, `setMeta(patch)`, `getSheet` |
| Struct | `listFields`, `field(name)`, `addField`, `removeField`, `readRecords`, `record(key)`, `addRecord`, `removeRecord` |
| Field | `getMeta`, `setMeta`, `setDescription` |
| Record | `read()`, `cell(fieldName)` |
| Table | `readEntries`, `entry(key)`, `addEntry`, `removeEntry` |
| Entry | `getMeta`, `setMeta`, `keyCell`, `valueCell` |
| Sheet | `getInfo`, `getUsedRange`, `getOccupiedRows`, `getOccupiedColumns`, `readRows`, `cell("A1")`, `insertRows`, `deleteRows`, `rename`, `remove` |
| Cell | `read`, `getValue`, `getFormula`, `getCachedResult`, `setValue`, `setFormula`, `clear`, `getHyperlink`, `setHyperlink({sheet,cell})`, `clearHyperlink` |

以实际 `includeApi:true` 返回的签名为准。CellValue 是 `string | number | boolean | null`；数组和 KV 在单元格中仍写协议字符串，不传 JS 数组/对象。

修改示例（仅在用户确实要求将对应价格改为 18 时）：

```javascript
const cell = book.struct("GoodsData").record(111).cell("Price");
const before = cell.read();
cell.setValue(18);
print({ before, after: cell.read() });
```

`setValue` 不覆盖公式；改公式用 `setFormula("=...")`，清空用 `clear()`。公式缓存有 `fresh/pending/unavailable` 状态，不能把旧缓存当新计算结果。
check/close/export 按需在独立 WPS 实例中重算导出字段及其递归公式依赖；无关辅助公式不执行。条件格式、数据验证和链接从临时计算副本移除，原表保持不变，不以 AI 手算或静默删除公式替代。
行列尺寸、冻结窗格、分页符本身不再阻断结构操作；实际公式、合并或尚不能维护的引用仍可能阻断移动、删除和重命名。只修改任务涉及的引用，不无差别移除保护。日期等非脚本标量可按文本及 sourceType 读取，源单元格保持原类型；需要修复时使用现有单元格操作。

### 当前工作簿内的超链接修复

失效导航链接本身不参与配置数据导出校验。仅在任务需要修复或移除链接时操作，先核对实际页签和锚点，不从显示文字猜跳转目标。

- `getHyperlink()` 返回原始 `{location,target}` 或 null；`read().hyperlink` 也可查看链接，失效链接仍可读取。
- `setHyperlink({sheet,cell})` 的 sheet 必须是当前工作簿已有页签，cell 必须是有效大写单格 A1 地址；不接受 URL、其他 XLSX 文件、范围或任意跳转字符串。
- 修正目标保留已有单元格文字、公式及链接提示；空白单元格以规范化内部地址作显示文字。`clearHyperlink()` 只移除链接；`clear()` 只清值或公式，不移除链接。
- 仅链接修改也会产生草稿版本；按返回版本继续 check、close、export，不把链接修好当作已保存或已导出。移除最后一个链接后，可继续其他允许的结构操作；其他实际引用限制仍有效。

示例仅用于已核实 Rule!E4 应指向本文件 ToolConfig 页签且任务要求修复的情况；实际名称以查询为准：

```javascript
const cell = book.sheet("Rule").cell("E4");
print({ before: cell.getHyperlink(), text: cell.getValue() });
cell.setHyperlink({ sheet: "ToolConfig", cell: "A1" });
print({ after: cell.read() });
```

## 3. 工作簿布局与三种 Meta

### 子配置 ConfigMeta

首个物理页签是索引，名称常为 `Rule`，名称本身不决定索引身份。第 1 行标题，第 2 行起：

| 列 | API 字段 | 含义/允许值 |
| --- | --- | --- |
| A | `key` | 导出模块的一级子配置键，string 或 number |
| B | `keyType` | 一级子配置键类型，只支持 `string`、`number` |
| C | `format` | `struct` 或 `table` |
| D | `keyField` | struct 的记录主键字段名；table 按每行 MetaInfo 读键，此列不指定其键类型 |
| E | `sheet` | 数据页签名称，必须存在 |
| F | `description` | 配置说明，CellValue，不参与前五列导出协议 |

例如 `GoodsData | string | struct | DevGoodsId | GoodsData`。
**B 列不决定 struct 行主键的类型**；行主键按 D 指向的字段及该字段类型解析。
`setMeta(patch)` 只改给出的属性，不自动创建页签、切换数据布局或迁移数据。
新增页签不会自动被导出；需 `addConfig` 声明。`removeConfig` 保留物理页签；仍被引用的页签不可删除。

### Struct 字段 FieldMeta

第 1 行字段说明，第 2 行字段名，第 3 行字段类型，第 4 行起记录。
`getMeta()` 返回 `{name,type,description,column}`；column 是只读列号。
`setMeta` 可改 name/type/description；类型变化不自动转换旧值。
仅有说明、没有完整字段名和类型的备注列不作为导出字段。字段名、类型和标量字符串解析时去首尾空白。
主键必须非空且唯一，不能只清空主键来删除记录；用 `removeRecord(key)`。

### Table 条目 EntryMeta / MetaInfo

第 1 行标题；第 2 行起 A/B/C 为 `MetaInfo | Key | Value`，每行独立声明类型。
`MetaInfo` 是 `keyType,valueType`，如 `string,number`、`string,kv_string`。
API 返回 `{keyType,valueType}`，键类型只允许 string/number，值类型见下一节。
三列必须齐全；即使 valueType 带 `_option`，table 的空 Value 也会先被三列完整性检查拒绝。
允许页签其他列存备注，但不将其作为配置值导出。重复条目键报错。

## 4. 支持的字段类型和单元格写法

完整基础类型共 13 种，下面每一种都支持追加 `_option`；没有 `bool_array`、JSON、原生 Color3/Vector3 或任意 Luau 表类型。

| 类型 | Excel 单元格例子 | 导出值 |
| --- | --- | --- |
| `string` | `Hello` | 字符串，去首尾空白 |
| `bool` | Excel TRUE/FALSE 或文本 `true`/`false` | boolean；数值 0/1 不作为 bool |
| `number` | `12`、`1.5`、`1e6` | 有限数值，不接受 NaN/Infinity |
| `string_array` | `A,B,C` | 字符串数组，逗号分隔，不支持 CSV 引号转义 |
| `number_array` | `1,2.5,3` | 数值数组；单个数值也可用 |
| `vec2` | `1,2` 或 `{1,2}` | `{x=1,y=2}` 普通表 |
| `vec3` | `{1,2,3}` | `{x=1,y=2,z=3}` 普通表 |
| `vec4` | `{1,2,3,4}` | `{x=1,y=2,z=3,w=4}` 普通表 |
| `vec2_array` | `{1,35},{2,30}` | vec2 表数组，可有尾逗号 |
| `vec3_array` | `{1,2,3},{4,5,6}` | vec3 表数组 |
| `vec4_array` | `{1,2,3,4},{5,6,7,8}` | vec4 表数组 |
| `kv_string` | `Type=Item,ItemId=104,Count=1` | KV 表；值依次识别 bool、有限 number，否则为字符串 |
| `kv_string_array` | `{Type=Gem,Count=3},{Type=Item,Id=105,Count=1}` | KV 表数组；键和值是否被业务接受另查消费代码 |

KV 键使用英文字母/下划线开头的标识符；值不能包含逗号或空白，也不支持嵌套对象。不要使用 JSON 语法或加引号期待转义；引号可能被当作字符串本身。
`kv_string` 是历史类型名，内部值不局限于字符串。

optional 空单元格语义：

- `string_array_option`、`kv_string_array_option` → `{}`。
- 其余 `_option`（含 number_array、vec 数组）→ `nil`。
- 非空但格式错误依然报错；`_option` 不跳过类型检查。必填类型提供合法值，不利用旧解析器的空值偶然行为。

## 5. Luau 导出结构

所有分类的工作簿共用以下结构。以一个示例 GameConfig.xlsx 为例，首个索引页声明：

| 子配置键 | 键类型 | 格式 | 主键字段 | 数据页签 |
| --- | --- | --- | --- | --- |
| CommonConfig | string | table | Key | CommonConfig |
| LevelData | string | struct | Id | LevelData |

CommonConfig 页签（第 1 行标题，第 2 行起数据）：

| MetaInfo | Key | Value |
| --- | --- | --- |
| string,number | MaxPlayerCount | 8 |
| string,kv_string | OfflineReward | MaxSeconds=14400,Rate=0.25 |

LevelData 页签（前 3 行是说明、字段名、类型，第 4 行起数据）：

| A | B | C | D |
| --- | --- | --- | --- |
| 关卡 ID | 名称 | 血量 | 奖励 |
| Id | Name | HP | Rewards |
| number | string | number | kv_string_array |
| 1 | First Level | 100 | {Type=Coin,Count=10},{Type=Item,Id=101,Count=1} |

在 RobloxStudio 工程中输出 GameConfig.luau ModuleScript：

```lua
return {
    CommonConfig = {
        MaxPlayerCount = 8,
        OfflineReward = {
            MaxSeconds = 14400,
            Rate = 0.25
        }
    },
    LevelData = {
        [1] = {
            Id = 1,
            Name = [[First Level]],
            HP = 100,
            Rewards = {
                [1] = {
                    Type = [[Coin]],
                    Count = 10
                },
                [2] = {
                    Type = [[Item]],
                    Id = 101,
                    Count = 1
                },
            }
        }
    }
}
```

因此游戏代码取得模块后，可读取 `GameConfig.CommonConfig.MaxPlayerCount`、`GameConfig.LevelData[1].HP`、`GameConfig.LevelData[1].Rewards[2].Id`。
示例里的 Type=Coin/Item 是业务数据，导出器只转换表结构，不实现发奖。
struct 为 `模块[子配置键][记录主键].字段`，table 为 `模块[子配置键][条目键]`。记录键来自声明的主键字段，主键字段本身也保留在记录中；页签名可以与子配置键不同，导出使用子配置键。
数组使用从 1 开始的显式索引；向量是普通轴字段表；空值序列化为 nil（Luau 表中等价于该键不存在）。
字符串用 `[[...]]`，遇闭合冲突升级 `[=[...]=]` 等；保留字符串内容，不执行其中代码。
绝对值达到 `10^6` 的数值用科学计数法；非合法标识符/保留字的字符串键用中括号引号语法。

RobloxStudio 工程默认输出到 `../Scripts/ReplicatedStorage/Scripts/Game/Configs`；MiniStudio 默认输出到 `../Code/ServiceNodes/MainStorage/Scripts/Game/Configs`。相对路径按 MCP 当前工程工作区解析；实际目标以本地 `configExportDirectory` 设置及 export 返回路径为准，不传临时输出目录。
MiniStudio 输出同名 `.lua`，上述示例文件内容改为 `_G.GameConfig = {...}`，内部 table/struct 结构保持相同。RobloxStudio 使用 `return {...}`，游戏通过 require 取得模块；是否再赋给 `_G` 由加载代码决定。后缀和模块包装由工程类型决定，不由输出目录名称决定。
export 完成解析、检查、序列化后才替换目标；失败不应当作已更新。生成模块成功不证明 Script Sync、Studio require 或游戏行为已验证。
