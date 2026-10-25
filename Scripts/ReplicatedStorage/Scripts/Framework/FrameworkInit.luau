-- 沿用 MiniStudio 的框架分层，公共层初始化后只加载当前端实现。
local RunService = game:GetService("RunService")
local FX = {}
_G.FX, _G.FC, _G.FS = FX, {}, {}
_G.Rbx = {
    Players = game:GetService("Players"),
    RunService = RunService,
    MainStorage = game:GetService("ReplicatedStorage"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Workspace = workspace,
}

-- 客户端 -> 服务端；以下参数不含网络层自动传入的已认证 UserId，返回值仅 InvokeServer 调用可读取。
FX.FrameworkClientMsgID = {
    "C2S_GMCommand", -- action: string，后续参数由项目约定；仅认证开发者可操作本人，框架管理器鉴权后交给 HandleGMCommand，返回 success/key。
    "C2S_ClientReady", -- 通知客户端已就绪；无参数，等待存档加载后创建玩家并下发初始数据，重复通知不重复创建。
    "C2S_ActivateTool", -- 原生 Tool 点击；参数为服务端创建的 Tool 实例，服务端核对后使用对应背包格。
    "C2S_BuyCheck", -- 购买前置校验；参数 productId 为 Developer Product ID；返回 boolean，仅检查购买资格，不发奖。
    "C2S_GetServerTime", -- 查询服务器时间；无参数，返回 GetServerTimeNow() 的秒数（number）。
    "C2S_RankingData", -- 查询排行榜；参数 scope（1 房间/2 全局）、kind（榜单配置索引）、first、last（1 <= first <= last <= 100）；返回 {itemData, myNo, myScore}，请求无效或榜单不存在时返回 nil。
    "C2S_GetFriendState", -- 查询自己的同服好友缓存；无参数，不触发平台查询；下发 S2C_FriendState，同时返回相同的状态表。
}

-- 服务端 -> 客户端；均为单向通知，无返回值。
FX.FrameworkServerMsgID = {
    "S2C_ShowLocalizedTips", -- definition: {Key, Source}、arguments: table?、duration: number?；通用 UI 翻译并显示，语言变化时刷新。
    "S2C_ServerReady", -- 通知玩家初始化与初始数据发送完成；无参数，客户端触发组件 OnReady 和就绪事件。
    "S2C_PlayerStateSync", -- 同步当前玩家字段；参数 data = {[字段 Key] = 值}，支持初始值及增量更新，仅包含允许同步的字段。
    "S2C_ServerSyncData", -- 同步全局共享字段；参数 data = {[字段 Key] = 值}，登录时发送当前全量数据，后续广播增量。
    "S2C_ShowTips", -- 显示限时提示；参数 message 为提示文本、duration 为可选显示秒数。
    "S2C_ShowDeveloperBuyUI", -- 请求打开开发者商品购买窗口；参数 productId 为 Developer Product ID，客户端再次通过购买预检后展示。
    "S2C_FriendState", -- 下发同服好友快照；参数 state = {ids = UserId 数组, status = "Loading"/"Ready"/"Unavailable", revision = 版本号}；失败时可保留旧快照。
}

require(script.Parent:WaitForChild("FShared"))
if RunService:IsClient() then
    require(script.Parent:WaitForChild("FClient"))
else
    require(script.Parent:WaitForChild("FServer"))
end
return FX
