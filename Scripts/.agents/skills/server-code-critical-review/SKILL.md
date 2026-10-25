---
name: server-code-critical-review
description: 审查 Roblox_Y1 服务端的身份与权限漏洞、严重逻辑缺陷、存档损坏、重复奖励和支付风险。请求服务端安全审查或高危 Bug 复查时使用，当前 agent 直接完成。
---

# 服务端高风险审查

由当前 agent 直接审查，不创建 subagent。只报告可证实的安全、严重逻辑或高影响遗漏，
不混入普通风格问题。按任务定位入口 -> 校验边界 -> 追踪状态/存档/同步 -> 检查失败与重入路径。
输出规范读 [reference-review.md](reference-review.md)。

## 实际入口

以下本地路径以 Scripts 工作区为根：
- 项目协议白名单：ReplicatedStorage/Scripts/Game/Shared/NetworkProtocol.luau 的 ClientMsgID/ServerMsgID。
- 框架协议：ReplicatedStorage/Scripts/Framework/FrameworkInit.luau。
- 网络身份与限速：ReplicatedStorage/Scripts/Framework/Shared/Core/FXNetwork.luau。
- 管理器：ServerScriptService/Server/Player/SPlayerObjectManagerClass.luau；
  服务协议搜索 ServerScriptService/Server/Service 与 ReplicatedStorage/Scripts/Framework/Server/Modules 的 RegClientMsgCallback。
- 非协议功能直接从平台回调、任务、玩家生命周期或调用方追踪，不以缺少协议为由停止。

## 身份与状态

- 网络回调 userId 来自引擎 Player.UserId，客户端指定的目标、格号、数量、实例和结果仍要验证。
- 检查有限数值、整数范围、所有权、已加载/已离服状态、冷却、限购与重复领取。
- 全局限速不能代替业务幂等；连接实例或对象引用不能独自证明拥有权。
- 异步结果检查当前会话，避免离服重进、切服、任务取消后写错对象。
- 失败路径不能留下扣费未发奖、部分奖励、状态已成功而存档失败等不一致。
- 检查 PlayerData 的 Type/Key/DefVal/Sync/KVTable 与版本迁移；GetTable 修改后须 SetTable。
- Sync=false 是隐私边界，不因 UI 读取困难就改成公开字段。
- 公共配置可被客户端读取，不把处理器、密钥或仅服务器数据放入 ReplicatedStorage。

## Developer Product（涉及购买时）

查 FSShopService.luau、FXBuyProcessor.luau、GoodsConfig.GoodsData，
及服务端注册的 _G.Provider.BuyHandlers。
客户端 FCCommonUIComp:ShowDeveloperBuyUI(productId) 预检后展示购买窗口，
发奖只由 FSShopService.ProcessReceipt 接收平台凭证。

- 预检不是支付确认。审查凭证阶段的 CanBuy/Buy 与状态变化。
- PurchaseId 幂等标记与奖励保存于同一档案，保存完成才 PurchaseGranted，失败保持可重试。
- CanBuy 不写状态，Buy 无 yield 且明确返回 true；只改当前玩家档案。
- 不在处理器内跨玩家发奖、调用其他 DataStore 或外部服务；这些不在现有回滚范围。
- 框架已有唯一 ProcessReceipt 所有者，新系统不得覆盖它。
- UI 关闭、PromptProductPurchaseFinished 或客户端协议不能发付费奖励。
- 一次性与限购商品需确认已支付凭证重试时的正确结算策略，不能用预检通过替代最终判断。

## 奖励（涉及发放或消耗时）

查 ReplicatedStorage/Scripts/Framework/Server/Player/FSRewardCompClass.luau。
协作名 FSRewardComp，方法 CanAddRewards/AddRewards/CanConsumeRewards/ConsumeRewards。

- 当前支持 Type=Item/Money；Money 依赖 GameConfig.RewardCurrencies 到 PlayerData 的映射。
- 使用 Type/Count/ItemId/Currency 等实际字段，奖励类型与处理器以当前注册内容为准。
- 核对数量、有限整数、道具存在、容量、合并重复币种和余额范围，调用方处理 false 返回。
- 权威结算和领奖标记在服务端；客户端“完成”或弹窗确认不是奖励依据。
- 检查与背包、Tool 同步、存档与业务状态的边界，区分内存逻辑和云端持久化证据。
- 只做静态审查时说明未运行的外部条件；没有证据的风险不写成已确认 Bug。

依据：[Developer Products](https://create.roblox.com/docs/production/monetization/developer-products)、
[Remote events](https://create.roblox.com/docs/scripting/events/remote)。
