# 商店 UI 与支付

商店 UI 基类位于 `ReplicatedStorage/Scripts/Framework/Client/Shop/`：
FCShopUICompClass、ShopPageBaseClass、ShopItemBaseClass。接入前先检查 `StarterPlayerScripts/Client/UI/` 中对应商品的业务组件；UIEditor 界面按 roblox-ui-components 继承生成展示类，不为套用下列框架示例重写已有界面。

容器子类：
- Ctor 调 Super，先准备 _rootNode 和模板，再 CreatePages/CreateTabs/SwitchDefaultPage。
- 覆盖 GetCompName/GetTabConfigList/CreateTabButton/RefreshTabButton。
- 页签配置含 PageName、ClassName、PageItemClassName、Name；对应类先 require 注册。

页签子类覆盖 CreateListNode/GetItemConfigList；
条目子类覆盖 CreateRootNode/BindEvent/Refresh。
页签基类负责创建条目、刷新、切页与延迟任务取消。
条目不是 FXCompBaseClass，不能直接 TrackConnection；自持连接并在 Destroy 中释放后调用 Super.Destroy。

Developer Product：
- `GoodsConfig.GoodsData[productId]` 配置 BuyHandler。
- handler 在服务端 `_G.Provider.BuyHandlers` 注册，使用 CanBuy(context)/Buy(context)。
- 客户端通过 FCCommonUIComp:ShowDeveloperBuyUI(productId) 执行预检后显示购买窗口。
- `ReplicatedStorage/Scripts/Framework/Server/Modules/FSShopService.luau` 唯一持有 ProcessReceipt；
  在凭证阶段重新 CanBuy/Buy，PurchaseId 与奖励写入同一档案，保存成功才确认。
- 每次购买数量为 1。
- CanBuy 是纯判断，Buy 必须无 yield、返回 true 才成功，只改当前玩家档案；
  不调用外部服务、其他 DataStore 或跨玩家发奖。
- 客户端购买完成事件不能发奖；Game Pass 也不能当 Developer Product 接入。

依据：[Developer Products](https://create.roblox.com/docs/production/monetization/developer-products)。
