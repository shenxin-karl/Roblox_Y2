# MCP 调用与配置格式

本页维护项目接入要点；具体 API、字段类型及导出语法以当前 StudioGameToolkit 服务的 config 文档包为准，不复制整套易过期的工具手册。业务选表见 [配置分类与组织](game-configs.md)。

## 按需读取服务文档

先调用 `sgtk.api.read {"id":"config"}` 读取入口，再读取本次操作所需文件；Codex 中工具通常显示为 `mcp__studio_game_toolkit__sgtk_api_read`。

| 任务 | config 包内 file |
| --- | --- |
| 首次使用、隔离、版本及失败语义 | `references/runtime.md` |
| list/open/execute_script/check/close/export、WPS 和备份 | `references/workflow.md` |
| 查询、分页、配置声明及页签 | `references/query.md` |
| Struct/Table、字段、记录及元信息 | `references/records.md` |
| 单元格、公式、缓存与内部超链接 | `references/cells.md` |
| 索引页、Struct/Table 布局及三种 Meta | `references/layout.md` |
| 13 种基础类型、optional 空值、数组及 KV 编码 | `references/field-types.md` |
| Lua/Luau 包装、表结构、字符串及输出目录 | `references/export-format.md` |

通过 `sgtk.api.read {"id":"config","file":"references/workflow.md"}` 读取对应文件，不把服务包路径当本地路径。documentRevision 变化时重读入口及任务相关文件。旧服务若无文档工具，按实际 schema 使用兼容的 `open(includeApi:true)`，不猜未提供的参数。

## 版本和结果

- 工具只操作当前工程授权配置目录中的 XLSX；先 list 核对工程、文件与 sourceRevision，不使用任意磁盘路径。
- 查询：list → open → execute_script。脚本是受限同步 JavaScript，无 Node、文件、网络或异步能力；用 `print` 输出目标字段或小范围记录到 logs，不输出 book/句柄本身。
- 编辑：list → open → 查询目标 → execute_script 修改 → 独立草稿 check → close → export。check 不保存，close 不导出；export 的 expectedSavedRevision 取 close 返回的 savedRevision。
- contextId、draftRevision 和源版本取真实返回值，不自行加一。日志截断时缩小范围重查，不能把截断 JSON 当完整结果。
- execute_script 成功只代表本次草稿执行；附带检查或 book.check() 不代替独立试导表。依据实际 execution/error、检查、saved/closed 和 export 结果分别汇报。
- 检查或保存失败保留草稿；异常回滚本次脚本。外部冲突不强制覆盖、不自动合并，不能用手工修改 XLSX 或生成文件绕过保护。
- open 不接管 WPS 未保存内容；当前服务 close 会按其文档保存并关闭目标工作簿后校验、备份保存。不要另行关闭用户文档、删锁文件或终止 WPS；占用及失败处理以当前 workflow 文档为准。

## 格式核对

- 分类决定业务职责，Meta 决定导出结构，消费代码决定字段含义。先查实际 listConfigs、Meta、主键及记录，再编辑；不将示例当作当前工作簿 schema。
- Struct 导出为 `模块[子配置键][记录主键].字段`；Table 为 `模块[子配置键][条目键]`。索引的一级键类型不决定 Struct 行主键类型，行主键按声明字段的类型解析。
- 数组、向量和 KV 按字段类型写协议字符串，不向单元格传 JS 数组、对象或 JSON。optional 的空值语义因类型而异，修改前查 field-types，不靠类型名推断。
- 公式用 setFormula，普通值用 setValue；旧缓存不当作新计算结果。不能用 AI 手算、清公式或删除无关引用替代重算。
- 内部超链接修复先核对已有页签和单格 A1 地址，只改任务相关链接；链接修改也须检查、保存，不能把链接修好当作已保存。
- RobloxStudio 默认生成返回表的 `.luau` 模块，MiniStudio 的包装和后缀不同；实际输出目录取工程设置和 export 返回值，不用临时目录绕过正式导出。
- 生成成功不证明 Script Sync、Studio require 或实际玩法已经验证。
