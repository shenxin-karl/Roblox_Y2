-- 项目支付扩展入口；支付回执由 FS.ShopService 唯一接管。
local Service = {}

--- 需要购买统计时在此设置框架回调，不重复注册 ProcessReceipt。
function Service.Init()
end

return Service
