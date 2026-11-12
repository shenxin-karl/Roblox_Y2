# XLSX 游戏配置

本参考属于 [外部工具协作](../SKILL.md)，维护配置分类与游戏接入约束；工具公共技能和 API 从 StudioGameToolkit MCP 按需获取。具体游戏有哪些子表、字段和业务处理器，以当前工程工作簿与消费代码为准。

本参考仅负责源头为 XLSX 的配置。Roblox_Y2 的 `NumericalConfig.luau` 由模拟器 `Data/config.json` 生成，使用 [模拟器参考](simulator.md)，不通过 XLSX 修改。

按任务读取，不默认加载全部参考：

| 当前任务 | 按需读取 |
| --- | --- |
| 调用配置 MCP；操作 XLSX；理解 Meta、字段类型及导出结构 | 本页的 MCP 说明与配置格式，再按需读取服务返回的配置 skill 与参考 |
| 判断配置归属、组织五类配置、选择通用字段或独立子表 | [配置分类与组织](config-categories.md) |

同时涉及业务分类与编辑时，先明确分类，再读取 MCP 文档操作。

## 安全与接入约束

- 修改前通过当前工程 MCP 读取配置声明、Meta、字段、主键和记录，不依赖固定路径或预设子表。参考文档中的名称和数值只是示例，不自动要求新增。
- 本工具从 XLSX 生成的 Lua/Luau 配置（含自定义目录）仅可只读；必须通过 MCP 修改源 XLSX，独立 check、close 保存成功后，以返回的 savedRevision 调用 export，不直接修补 XLSX 或生成文件。
- 能安全读取的文件可先打开修复，配置错误或保存限制不等于不能打开。检查或保存失败时保留草稿，能用现有 API 修复则继续修改并重检；实际无法修复时报告阻断。
- 干净旧会话可重开刷新；脏草稿默认保留。仅确定放弃旧修改时使用 `discardDraft:true`，并使用返回的新 contextId 和版本；不能因冲突就丢弃仍需保留的修改。
- 查询用 `print(...args)` 输出到 `logs`，不从 `result` 取数据；下一次调用使用实际返回的 draftRevision。执行或日志成功不等于检查、保存或导出成功。
- 工作簿导航链接通过 Cell 的 getHyperlink/setHyperlink/clearHyperlink 处理；先查实际页签和单格地址，不把失效导航链接当作导表错误而无差别删除。
- 分类决定数据职责；Meta 决定导出结构；消费代码决定业务字段含义。新增业务字段或处理器时，核对游戏侧接入。
- 只读说明无需保存或导出。修改后区分草稿、已保存、已导出和游戏验证状态；遇占用、版本冲突或不支持格式时报告实际阻断。

## MCP 说明与配置格式

先按 [外部工具协作](../SKILL.md) 和 [GameKit 参考](gamekit.md) 发现当前 StudioGameToolkit 文档接口；首次使用显式调用该服务 `sgtk.docs.read`，传入 `file: "AGENTS.md"`，已有同修订说明时复用。

从返回的技能摘要选择 XLSX 配置相关 skill，按任务读取工作流、查询、字段、记录、单元格或导出参考。包内路径取实际返回值，不维护旧 API 包的固定路径表。已知路径直接读取，不知道细节在哪时先用该服务文档搜索定位，不把服务包路径当本地路径。

`documentRevision` 变化时重读入口及任务依赖。接口返回未知工具或 schema 不匹配时，按实际错误报告接入阻断，不仅因工具可发现就继续业务写入，不自动猜用旧 `sgtk.api.read` 或 `open(includeApi:true)`。以下是项目接入约束，具体参数及返回结构仍以当前服务说明和 schema 为准。

### 版本和结果

- 工具只操作当前工程授权配置目录中的 XLSX；先 list 核对工程、文件与 sourceRevision，不使用任意磁盘路径。
- 查询：list → open → execute_script。脚本是受限同步 JavaScript，无 Node、文件、网络或异步能力；用 `print` 输出目标字段或小范围记录到 logs，不输出 book/句柄本身。
- 编辑：list → open → 查询目标 → execute_script 修改 → 独立草稿 check → close → export。check 不保存，close 不导出；export 的 expectedSavedRevision 取 close 返回的 savedRevision。
- contextId、draftRevision 和源版本取真实返回值，不自行加一。日志截断时缩小范围重查，不能把截断 JSON 当完整结果。
- execute_script 成功只代表本次草稿执行；附带检查或 book.check() 不代替独立试导表。依据实际 execution/error、检查、saved/closed 和 export 结果分别汇报。
- 检查或保存失败保留草稿；异常回滚本次脚本。外部冲突不强制覆盖、不自动合并，不能用手工修改 XLSX 或生成文件绕过保护。
- open 不接管 WPS 未保存内容；当前服务 close 会按其文档保存并关闭目标工作簿后校验、备份保存。不要另行关闭用户文档、删锁文件或终止 WPS；占用及失败处理以当前 workflow 文档为准。

### 格式核对

- 分类决定业务职责，Meta 决定导出结构，消费代码决定字段含义。先查实际 listConfigs、Meta、主键及记录，再编辑；不将示例当作当前工作簿 schema。
- Struct 导出为 `模块[子配置键][记录主键].字段`；Table 为 `模块[子配置键][条目键]`。索引的一级键类型不决定 Struct 行主键类型，行主键按声明字段的类型解析。
- 数组、向量和 KV 按字段类型写协议字符串，不向单元格传 JS 数组、对象或 JSON。optional 的空值语义因类型而异，修改前查 field-types，不靠类型名推断。
- 公式用 setFormula，普通值用 setValue；旧缓存不当作新计算结果。不能用 AI 手算、清公式或删除无关引用替代重算。
- 内部超链接修复先核对已有页签和单格 A1 地址，只改任务相关链接；链接修改也须检查、保存，不能把链接修好当作已保存。
- RobloxStudio 默认生成返回表的 `.luau` 模块，MiniStudio 的包装和后缀不同；实际输出目录取工程设置和 export 返回值，不用临时目录绕过正式导出。
- 生成成功不证明 Script Sync、Studio require 或实际玩法已经验证。
