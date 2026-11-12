# 项目编码规则

- 类和模块使用中文标签注释；新增或修改函数必须补充与实际签名一致的中文注释，解释业务原因或约束，形参逐一写 `@param`，实际返回值写 `@return`。例如 `--- @param owner table 所属玩家对象。`。
- 未使用参数保留可读名称并说明来源，不用 `_` 命名参数或遍历变量。
- 私有成员使用 `_` 前缀，方法名使用 PascalCase；禁止单行 `if ... then ... end`。
- 可信内部调用和必填配置不重复容错、不补静默默认值；协议、平台回调、旧存档与动态实例在实际边界校验，不用隐式 string/number 转换掩盖约定错误。
- 玩家存档必须遵守 [存档封装与取表接口](../roblox-framework-dev/reference-rules.md)：禁止访问 PlayerKV 内部映射、DB 或原始表；只读用 View，编辑用副本并通过公开接口提交，不能用标准浅拷贝泄露嵌套可写引用。

## FXLoader 节点与模块加载

- 实现依据是 `ReplicatedStorage/Scripts/Framework/Shared/Core/FXLoader.luau`。FShared 加载它后注册到 `_G.FX.Loader`；业务代码在框架初始化完成后使用，不为了使用加载器提前或重复初始化框架。
- 声明 `local FX = _G.FX`（已有 FX/FC/FS 声明则复用），再声明 `local FXLoader = FX.Loader`。FXLoader 模块返回 `true`，不能通过 `local FXLoader = require(...)` 获取加载器。
- 必需固定路径优先使用下表 API，替代连续 `WaitForChild` 和包裹等待链的 `require`；均使用冒号调用，路径仅使用 `.` 分隔，不支持 `/` 分隔。路径从指定根节点的子节点开始，不包含根节点名称；`Parent` 不表示父级跳转。

| 需求 | API |
| --- | --- |
| ReplicatedStorage 下的节点 / 模块 | `FXLoader:Shared(path, timeout)` / `FXLoader:RequireShared(path, timeout)` |
| ServerStorage 下的节点 / 模块（仅服务端） | `FXLoader:ServerStorage(path, timeout)` / `FXLoader:RequireServerStorage(path, timeout)` |
| 指定实例下的节点 / 模块 | `FXLoader:Here(instance, path, timeout)` / `FXLoader:Require(instance, path, timeout)` |
| 当前脚本父节点下的模块 | `FXLoader:RequireFromParent(script, path, timeout)` |
| Workspace 下的节点 | `FXLoader:Workspace(path, timeout)` |
| 当前玩家 / PlayerGui 下的节点（仅客户端） | `FXLoader:Player(path, timeout)` / `FXLoader:PlayerGui(path, timeout)` |
| 可选节点，不等待，缺失返回 nil | `FXLoader:Find(instance, path)` 或原生 `FindFirstChild` |

例如，框架已初始化的业务模块中：

```lua
local FX = _G.FX
local FXLoader = FX.Loader

-- 替代 require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Game"):WaitForChild("Shared"):WaitForChild("GameUtility"))
local GameUtility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
-- 已持有根节点时，用相对路径简化其子节点等待链。
local closeButton = FXLoader:Here(rootNode, "Panel.CloseBtn")
```

- FXLoader 是等待链的简化，不是取消复制等待或缓存节点。底层默认每层等待 10 秒，缺失时抛错；`PlayerGui` 方法对 PlayerGui 根节点仍使用原生无限等待。替换前确认原调用的超时和缺失处理语义；需要无限等待或超时返回 `nil` 时保留原生 `WaitForChild`，不要用 `pcall` 掩盖差异。
- 框架初始化前的引导加载保留原生 `WaitForChild`。可选或动态节点不使用会报错的必需路径加载 API；节点名称包含 `.` 时使用原生节点 API，避免被当作路径分隔符。
- 不为单个原生等待强行改写，不新增重复加载工具，不批量改动任务范围外的等待代码。节点实际路径按 [Studio 操作](../roblox-studio-operations/SKILL.md) 通过 Roblox MCP 核对。

## 数值文案显示

- 力量、货币、经验、价格、收益等数量文案统一调用 `ReplicatedStorage/Scripts/Game/Shared/GameUtility.luau` 的 `GameUtility.NumberToText`，不在 UI 中重复实现单位换算或小数格式化。
- 大数沿用该方法的 `K/M/B/T/Qa/...` 英文缩写，小数沿用两位小数规则，例如 `2/3` 显示 `0.67`；明确需要取整显示时使用 `NumberToTextFloor`。
- 等级、序号、背包件数/容量、时间和百分比按各自语义显示，不强制使用数量缩写。
- 格式化仅用于文案；计算、比较、存档和服务端发奖始终使用原始数值。均分收益先计算再格式化，不让格式化字符串参与计算。
- 文案含翻译或动态参数时，另按 [本地化](../roblox-localization/SKILL.md) 选择定义与接口。

## 验证

- 新增或修改 Luau 后，先确认本地可用的 Luau 编译器，默认只做编译/语法验证，以及通过 Roblox MCP 只读核对同步脚本，不自行运行脚本或启动游戏。
- 同步核对按 [Studio 操作](../roblox-studio-operations/SKILL.md) 检查脚本类型、RunContext 和内容；磁盘保存不代表同步成功。
- 编译器缺失时明确报告语法验证未完成；Script Sync 无法确认或存在冲突时报告具体待核对范围，不宣称通过。
- `git diff --check` 从仓库根执行。用户明确授权测试或试玩时按授权执行，并区分语法验证、同步核对和实际运行结果。
