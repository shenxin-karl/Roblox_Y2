# 脚本与审查记录

## 命令

从 `Scripts/` 运行，其他工程替换为实际路径。本工程当前审查记录为 `../GameKitWorkspace/Translation/translation-review.json`，与正式 CSV、索引同目录；续审先对这份记录运行 `report`，不按日期或修改时间选择历史快照。无记录时才在该路径建档，不另存正式输入 CSV 的副本。其他工程记录放输入旁或用户指定的可写工作目录，不写入 CSV 元数据或 `Docs/`；正式输入无写权限时请求权限，不用副本冒充交付。

```powershell
python -B -X utf8 .agents/skills/roblox-translate/scripts/translation_review.py init --csv ../GameKitWorkspace/Translation/translation-upload.csv --index ../GameKitWorkspace/Translation/translation-ai-context.json --review ../GameKitWorkspace/Translation/translation-review.json
python -B -X utf8 .agents/skills/roblox-translate/scripts/translation_review.py batch --review ../GameKitWorkspace/Translation/translation-review.json --start 1 --limit 10
python -B -X utf8 .agents/skills/roblox-translate/scripts/translation_review.py report --review ../GameKitWorkspace/Translation/translation-review.json
python -B -X utf8 .agents/skills/roblox-translate/scripts/translation_review.py compact --review ../GameKitWorkspace/Translation/translation-review.json
python -B -X utf8 .agents/skills/roblox-translate/scripts/translation_review.py apply --review ../GameKitWorkspace/Translation/translation-review.json
```

- `init` 不覆盖已有记录；`batch` 返回未完成条目。row/start 是从 1 起的数据记录序号，不是 CSV 物理行号，也不用于匹配来源。
- `report` 只读，输出全表问题、覆盖缺口和候选与实际 CSV 的差异。大报告可用 UTF-8 暂存到系统临时目录后查询，不截掉未处理问题；报告可从当前记录重建，不默认在仓库另存全量 JSON。
- 退出码：0 全部完成，2 未完成或待确认，1 输入/校验/保存失败；`batch` 成功固定返回 0。
- `compact` 只精简当前记录，不写 CSV 或索引；成功返回 0 及前后字节/行数，不代表翻译审查完成。迁移前验证记录，逐字段确认还原结果完全一致，保存时检查并发修改。

## 产物与清理

- **持久状态**：一份当前审查 JSON，包含脚本生成的基线与哈希，以及来源、用途、语言判断、术语、试玩与 pending。证据记录精确位置、实际所见值及相关条件，不倾倒完整工具响应，也不反复拼接每次续审的通用说明。有效历史只保留解释当前判断或未解决问题所需的部分。
- **临时处理**：优先在会话内处理批次查询；确需文件时在系统临时目录创建本次专用子目录，放原始响应、查询批次、一次性脚本和可重建的报告。中断续接所需事实及时写入当前审查记录，不依赖临时目录长期存在。Python 辅助调用使用 `-B`，避免在技能目录生成 `__pycache__`。
- **换输入**：新导出须保留旧记录直到新记录经校验可续接；过渡期间允许两份记录并存。将仍适用的证据、术语和未解决疑点转入新记录，重新核对身份、Source、译文及来源后才能承接，不整批复制完成标记或旧报告。完成承接后清理本次过渡文件，正常交付只留当前记录；用户要求保留历史时例外。
- **结束核对**：包括有待确认项的交付，均检查本次新增文件。清理本次临时文件前确认需要的结论已进入记录，持久证据链接有效，并重跑 `report` 核对基线、落盘结果和 pending。历史文件仅在用户授权清理且依赖已承接时删除，不借机清理其他任务的产物。
- **汇报**：分别给出相对本次基线的译文单元格数、涉及的 CSV 记录数及辅助文件增删；Git 文本行数不能当作文案条数。通常提供 CSV 和当前审查记录即可，只有用户要求独立报告时才额外保存。

## 身份与来源匹配

有 Key 按精确 Key 匹配；无 Key 按精确 Source＋Context 匹配。不 trim、改大小写、模糊匹配或依赖行号。重复 CSV/索引身份、缺失或过时索引逐项记录，不自动取首项。

索引为 JSON 数组，每项是 `{key, sources}` 或 `{source, context?, sources}`。来源格式：

- `code:路径:行号`
- `node:实例路径.属性`
- `config:工作簿路径:工作表!单元格`

**有 Key 的索引没有 Source 快照。** 必须检查实际定义、节点或配置，将所见原文填入各来源的 `observed_source`；仅 Key 相同不能证明索引新鲜，不能直接复制旧模板。

## 编辑审查 JSON

磁盘格式 v2 将重复的证据句段集中于 `evidence_pool`，各项 `evidence.parts` 使用稳定的内容标识引用；每条文案占一行，方便 Git 按条查看差异。旧版 v1 仍可读取，`init`、`apply`、`compact` 保存时自动使用 v2。不要手动展开整份 JSON 或用普通 `json.dump` 覆盖，否则会重新产生大量重复文本与行数。

`batch` 显示还原后的完整证据。批量维护时导入 `translation_review`，用 `read_json(path)` 取得下述展开结构，局部更新后用 `atomic_write(path, json_bytes(state), expected=original_bytes)` 保存；先保留原文件字节用于冲突检查。`read_json` 返回兼容的 v1 内存结构，`json_bytes` 自动去重并编码为 v2；不要手改版本、证据池或引用。相同片段复用只改变存储，不代表不同条目或语言已经完成语义判断。

只编辑下例中的审查字段及顶层 `glossary`。`baseline_b64`、`baseline_sha256`、`applied_sha256`、`index_sha256`、路径、version、rows 的顺序/row/identity、sources.location 不手改。

```json
{
  "row": 1,
  "identity": ["key", "Shop.Price"],
  "sources": [{
    "location": "code:../Scripts/Shop.luau:8",
    "checked": true,
    "observed_source": "{price}",
    "evidence": "定义与调用路径/行号；price 来自 FormatNumber，已包含币种。"
  }],
  "usage": "购买按钮的价格文本。",
  "evidence": "参数赋值及按钮显示条件的路径/行号。",
  "playtest_required": false,
  "playtests": [],
  "languages": {
    "ja": {
      "value": "{price}",
      "reviewed": true,
      "evidence": "价格组仅 Shop.Price；日语通读后确认纯参数保留。",
      "pending": ""
    }
  }
}
```

示例省略了其他来源和语言，实际保留初始化生成的全部项。字段要求：

| 字段 | 填写条件 |
| --- | --- |
| `sources[].checked` | 所见原文与 CSV 当前 Source 完全相同，且用途、调用、参数和显示条件已核实，才设 true。每个来源独立检查。 |
| 来源 `evidence` | 代码记录定义/调用位置；节点记录 MCP 模式、实例、属性及布局；配置记录工作簿、页签、字段、记录及消费路径。不能只复述索引。 |
| `usage` / 行级 `evidence` | 文案用途及支撑它的实际证据。全部来源核实后才允许该条语言审查完成。 |
| `languages[locale].value` | 最终译文；待确认时保持最初基线值，不填猜测或占位说明。 |
| `languages[locale].reviewed` | 来源、用途、逐条语义审查、按语言集中复审及必要核验均完成，才设 true。格式正确或旧值非空不代表完成。 |
| 语言 `evidence` | 保留/修改的依据、集中复审的功能、可定位的条目或批次范围及结论；旧译文也填写。 |
| `pending` | 未解决的疑点、已知证据、阻断原因和所缺信息；此时 reviewed 为 false。 |
| `glossary` | 自由结构，按概念、用途和语言记录首选术语、合理变体及依据，跨批续用。 |

允许批量读写和引用共享证据，但每个完成标记须有实际判断，不能按行号批量通过或用通用“已核对”代替依据。复审发现问题时修正并重查；无法确认则撤销对应完成标记，恢复基线值并写 pending。

## 必要试玩与显示证据

仅对静态证据无法解决的问题试玩。启动前在对应 `evidence` 写明条目、疑点、静态证据不足之处、目标界面/状态、已定位的入口/触发方式和预期观察；入口未找到则继续定位，不先启动。不得为观察文案修改存档、支付或进行无关操作。

| 疑点范围 | 记录方式 |
| --- | --- |
| 整条共有的用途、参数或显示条件 | 行级 `playtest_required: true`，在 `playtests` 记录共同核验目标；未通过时阻断该条全部语言。 |
| 仅某语言的语法、候选裁切或排版 | 只在该语言的 pending/evidence 保留疑点、候选及核验过程，不新增行级目标，不阻断其他语言。误记在行级的目标连同历史移入该语言，再按剩余共同目标确定行级标记。 |

用 Roblox MCP 打开界面或触发状态，在 Client.PlayerGui 确认目标及祖先可见、条件成立并观察文字、参数与布局。仅启动游戏、读取隐藏节点、查询坐标或调用打开方法不算成功。MCP 不可用、状态无法触发或缺权限时写明阻断。

行级 `playtests` 每个目标保留一项当前结论：

```json
{"state": "界面/状态及实际操作", "observed": true, "evidence": "语言、条目、译文版本；可见性和状态证据；显示结果及疑点结论"}
```

未观察到时 observed 为 false，写具体原因；重试成功则更新原项，在 evidence 保留失败历史，不追加一个已失效的 false。全部共同目标通过后该行才就绪，不清除必要标记绕过阻断。单语言核验在该语言 evidence 更新，疑点解决后才清 pending、恢复候选值并完成复审。共享操作可引用同一证据，但须分别说明解决的问题。

候选、语言或条件改变后重查证据适用性：失效的单语言证据撤销该语言 reviewed 并更新 pending/evidence；失效的共同目标改回 observed 为 false。保留历史，不用旧版本的观察证明新版本已显示。

显示证据须区分：

| 类型 | 能证明的范围 |
| --- | --- |
| 原界面/已有云端译文 | 仅所见状态及该版本译文，不证明本地候选已显示。 |
| 候选文字尺寸测量 | 记录候选、语言、字体、字号、可用空间，仅为尺寸估计，不能证明实际无裁切或遮挡。 |
| 候选译文实际显示 | 记录候选值/版本、语言、界面/状态及可见结果，仅覆盖实际观察范围。 |

没有授权预览方式时报告未验证，不自动上传或改 UI/翻译接入。仍需候选实际显示才能解决的疑点保持待确认；静态证据足够的条目不要求试玩。

## 校验与保存

- **CSV**：脚本用 `csv.reader/writer` 处理 UTF-8、BOM、引号、逗号和多行，不按文本拆单元格；保留未改记录字节及改动记录原行尾。从最初基线生成候选，重新解析后核对表头、行数、顺序及所有列值。
- **应用条件**：修改单元格须身份唯一、全部来源核实、用途明确、必要核验及该语言审查完成。其他未改条目的缺译、身份或覆盖问题允许部分保存，但不算全部完成；任何模板/富文本错误（包括旧译文）或无证据修改都阻止替换。
- **冲突与保存**：脚本核对最近 init/apply 内容，临时文件写好后再次检查，校验通过才同目录原子替换。冲突时不强制覆盖：保留记录和基线，协调差异后针对新输入建新记录，只转移重新核实仍适用的证据，不手改哈希。
- **checkpoint 失败**：若报 `CSV saved, review checkpoint not saved`，CSV 已保存；检查后重试同一 apply 恢复记录，不重新 init。其他失败按实际文件状态报告，候选未落盘时明确未应用。

### 模板与富文本边界

本工程 `Text.Tr` → `Localization:Tr` 直接调用 `Translator:FormatByKey`，无自定义解析。脚本按出现次数比较命名/数字参数及完整格式，支持 `int/fixed/num/HEX/hex/datetime/iso8601/shorttime/shortdatetime/shortdate/translate`；纯参数条目须原样相等。

残留、双重或反斜杠花括号及未知格式会报错，不能套用 Python/C# 转义规则。遇到时先查可核验平台依据或做已授权的最小 Studio 验证，再按证据扩展解析与测试，不仅删除警告。CSV 已是 Lua 转义解码后的显示值，不再次 unescape。平台参考：[动态文案](https://create.roblox.com/docs/production/localization/translate-dynamic-content)、[Translator](https://create.roblox.com/docs/reference/engine/classes/Translator)。

富文本按 XML 式嵌套、配对、重复/允许属性及常见属性值检查。支持 font、stroke、mark、b/i/u/s、uppercase/uc、smallcaps/sc、br 和 XML 注释；按次数保护标签及属性值，可移动包裹位置，br 数量可随布局调整。`&lt;` 等实体不是标签；未知/损坏语法报错，不删标签绕过。平台参考：[支持标签](https://create.roblox.com/docs/ui/rich-text)。

脚本不能判断语言质量、集中复审是否发生、参数运行值、字体可用性、换行/长度、包裹语义或证据真实性。`report.complete` 只证明记录声明与机械条件齐全。

## 验证辅助脚本

```powershell
python -B -X utf8 -m unittest discover -s .agents/skills/roblox-translate/scripts -p 'test_*.py' -v
```

测试只操作临时样例，无 Roblox 运行、整表翻译或云端上传。
