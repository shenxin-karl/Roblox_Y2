# 排行榜组件

基类：`ReplicatedStorage/Scripts/Framework/Client/Player/FCRankingUICompClass.luau`。
服务端校验：`ServerScriptService/Server/Service/SRankingServiceClass.luau`。
`ReplicatedStorage/Scripts/Game/Shared/RankingDataConfig.luau` 已配置 Playtime 榜。先核对现有榜单配置、服务端写入和 UI 接入，再按需求扩展；本地配置存在不等于本次已完成运行验收。

先确定榜单规则和配置，再提供真实 UI：
- Ctor 在 Super.Ctor 之前准备基类会调用的节点映射与配置；基类构造会绑定按钮。
- 覆盖 GetRankingNodeMap，返回 rankListNode/rankingTypeListNode。
- 覆盖 GetRankingTabConfigList，当前项使用 tabType/buttonName/tabTitle。
- 覆盖 GetRankRowTemplate、RefreshHeaderText、RefreshRankRowNode、RefreshMyRankData。
- 提供 _rootNode 或 GetRootNode。基类 OnShow 会切默认榜并刷新。
- 默认 RequestRankingData 通过 C2S_RankingData 请求全局榜；
  参数为 scope（1 房间/2 全局）、kind、first、last，范围在 1..100。
- 返回 {itemData, myNo, myScore}；规范行含 rankNo/playerName/playerId/rankScore。
- 基类维护动态行节点，销毁旧行时保留布局器。
- 不允许客户端上传最终分数；服务端通过 UpdateRankingScore/AddRankingScore 更新权威值。

空榜与查询失败是有效状态，UI 不伪造排名；OrderedDataStore 的真实验收需独立环境和权限，
本地构建与内存档案不证明云榜可用。
