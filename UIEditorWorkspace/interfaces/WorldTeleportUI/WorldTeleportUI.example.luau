local FX = _G.FX
local CWorldTeleportPreview = FX.Class("CWorldTeleportPreview", "CWorldTeleportView")

-- 父构造完成后准备世界列表；门槛为演示值，不代表游戏业务配置。
-- @param owner table 编辑器组件宿主
function CWorldTeleportPreview:Ctor(owner)
    CWorldTeleportPreview.Super.Ctor(self, owner)
    self.Config = {
        worlds = {
            { id = "world_1", name = "World 1", requiredLevel = 0, color = "#45a85a", edgeColor = "#1d542a" },
            { id = "world_2", name = "World 2", requiredLevel = 190, color = "#d9ab27", edgeColor = "#7d5b0b" },
            { id = "world_3", name = "World 3", requiredLevel = 380, color = "#8a4dc2", edgeColor = "#48246b" },
            { id = "world_4", name = "World 4", requiredLevel = 570, color = "#249cb5", edgeColor = "#105464" },
            { id = "world_5", name = "World 5", requiredLevel = 760, color = "#397bc7", edgeColor = "#193e73" },
        },
    }
    self.State = {
        level = 318,
        currentWorldId = "world_2",
    }
end

-- 先绑定父界面，再提供数据并显示模拟列表。
function CWorldTeleportPreview:OnReady()
    CWorldTeleportPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 模拟传送只更新当前世界，不请求服务器或移动玩家。
-- @param action string Teleport 或 Close
-- @param payload table Teleport 携带 worldId，Close 为空表
function CWorldTeleportPreview:OnUIAction(action, payload)
    if action == "Close" then
        self:Hide()
        return
    end
    assert(action == "Teleport", "Unsupported action: " .. action)
    for index, world in ipairs(self.Config.worlds) do
        if world.id == payload.worldId then
            if self.State.pendingWorldId or self.State.currentWorldId == world.id then
                return
            end
            if self.State.level < world.requiredLevel then
                return
            end
            self.State.currentWorldId = world.id
            self.State.error = nil
            self:RefreshUI()
            return
        end
    end
    error("Unknown world ID: " .. tostring(payload.worldId))
end

return CWorldTeleportPreview
