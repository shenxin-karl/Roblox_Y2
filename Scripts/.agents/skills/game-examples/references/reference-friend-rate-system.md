# 好友基础与倍率需求

好友基础能力由服务端查询与客户端状态组件提供；倍率和邀请按钮按具体需求接入。

现有服务：
- `ReplicatedStorage/Scripts/Framework/Server/Modules/FSFriendService.luau`，
  服务实例 FS.FriendService：GetFriendIds(userId)/IsFriend(userId, otherId)/GetFriendCountInRoom(userId)/GetState(userId)。
- `ReplicatedStorage/Scripts/Framework/Client/Player/FCFriendCompClass.luau`，
  已挂载组件 FC.PlayerObject:RequireComponent("FCFriendComp")，GetState/GetFriendCountInRoom。
- C2S_GetFriendState 与 S2C_FriendState 只传服务器验证的同服快照。
- state 为 {ids, status, revision}，status 为 Loading/Ready/Unavailable。
  失败保留旧展示快照，不能当当前已验证关系；非 Ready 的人数返回 nil。
- 服务端分页读完平台好友列表才提交，当前每 120 秒刷新；异步结果检查玩家会话。
- FriendStateChanged 由玩家组件发布，晚订阅 UI 先 GetState 取当前快照。

如果明确要求好友倍率，先从需求确认适用收益、公式、上限与失败状态策略，
再把计算接到服务端真实收益入口。不信任客户端好友 ID 或倍率，不猜测加成参数。

邀请按钮按需求接入；邀请弹窗不作为好友加入或领奖依据。AI 实际发起邀请或发送通知需要用户明确授权。
