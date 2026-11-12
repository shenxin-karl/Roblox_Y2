--[[
世界传送接入契约

【Config：完整配置】
  worlds: {World}，必填连续数组；数组顺序即显示顺序，空数组显示空状态。
    World.id: string，必填，无默认值；全列表唯一稳定的世界业务 ID；
      重复 ID 会明确报错，不使用名称/列表位置作身份。
    World.name: string，必填，无默认值；显示名称原文，经 Text.TrSource 查询。
    World.requiredLevel: number，必填，无默认值；非负解锁等级，单位级。
    World.color: string，可选；#RRGGBB 底色，省略用 #8a4dc2。
    World.edgeColor: string，可选；#RRGGBB 底边色，省略用 #48246b。

【State：Render 的完整输入】
  level: number，必填，无默认值；玩家当前等级，单位级。
  currentWorldId: string，必填，无默认值；当前世界业务 ID，可不在本次列表内。
  pendingWorldId: string，可选，省略 nil；正在请求的目标 World.id，
    有请求时禁用全部传送按钮，不禁用关闭。
    清除请求必须设 nil，不用 ""；空字符串也会被当成正在请求。
  error: string，可选，省略 nil；失败提示原文，经 Text.TrSource 查询；
    nil 或 "" 均隐藏错误区域。
  没有独立 loading 字段；完整数据未就绪时延后 BindUIData/Show，
  或明确提供 worlds={} 的空列表，不能依赖框架补齐字段。

【最小完整数据（接入 Ctor 调用父构造之后）】
  self.Config = {
      worlds = { { id = "world_1", name = "World 1", requiredLevel = 0 } },
  }
  self.State = { level = 318, currentWorldId = "world_1" }

【初始化与刷新】
  游戏接入类继承 CWorldTeleportView。
  接入 Ctor(owner) 先调用自身类的 Super.Ctor(self, owner)，再准备下例数据。
  接入 OnReady() 先调用自身类的 Super.OnReady(self)，再依次
  self:BindUIData()、self:Show()；父 OnReady 负责绑定节点，OnShow 会刷新。
  GetUIConfig() 默认返回 self.Config；GetUIState() 默认返回 self.State。
  RefreshUI() 调用 Render(GetUIState())，输入是完整快照，不合并增量，
  不自动补齐业务字段。可修改已有表或替换整表，但每次刷新须满足完整契约。
  后续先更新 Config/State，再 self:RefreshUI()；异步未就绪按本页规则处理。
  无需覆写 Render 或手动重复调用 OnReady；业务类覆写生命周期时须保留父调用。

【动作与覆写】
  必需覆写 OnUIAction(action: string, payload: table)，无返回值；默认报错。
  Teleport -> { worldId: string }，对应目标 World.id，不含客户端等级或权限。
  Close -> {}；接入层调用 self:Hide()，没有 State.open。
  Config.allowLockedAction:boolean?，true 锁定按钮灰色但允许发 Teleport 提示原因。
  State.errorText:string? 最终译文，优先于 error 原文；无错误时两者均清除。
  继承 Render / CreateRow / EmitUIAction，不重复绑定或写入按钮。
  等级不足、已在该世界或任何传送请求未完成时，按钮禁用；
  点击处理也检查上述条件，但不替代服务器校验。
  请求前 pendingWorldId=目标ID、error=nil 并刷新；
  成功清空 pendingWorldId、更新 currentWorldId；
  失败清空 pendingWorldId、填写 error；均需 RefreshUI。
  游戏接入负责世界存在性、等级、权限、真实传送和过期请求隔离。

【列表与资源边界】
  隐藏 Templates.WorldRowTemplate 按 World.id 克隆、复用和清理，
  同 ID 配置变化会更新外观及点击时读取的配置；空列表清理全部副本。
  窗口由 Show/Hide 管理，Render 不改变整窗显隐。
  无额外动态图标，Stud 纹理沿用设计资源。
  Studio、设备及真实跨世界流程需另验。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts/Game/Shared/Text")
local CWorldTeleportView = FX.Class("CWorldTeleportView", "CUIView")

local TranslationTexts = Text.Define("WorldTeleportUI", {
    Go = "Go",
    Teleporting = "Teleporting",
    Here = "Here",
    RequiredLevel = "Level {level:int}",
})

-- 暴露只读文案定义，供接入子类通过 self.BaseViewTranslationTexts 复用。
CWorldTeleportView.BaseViewTranslationTexts = TranslationTexts

-- 绑定固定窗口与隐藏条目原型，关闭事件只连接一次。
function CWorldTeleportView:OnReady()
    local root = FXLoader:PlayerGui("WorldTeleportUI")
    self.ListBox = FXLoader:Here(root, "WindowBox.PopupPanelImg.WorldListBox")
    self.EmptyTxt = FXLoader:Here(root, "WindowBox.PopupPanelImg.EmptyTxt")
    self.ErrorTxt = FXLoader:Here(root, "WindowBox.ErrorTxt")
    self.RowTemplate = FXLoader:Here(root, "Templates.WorldRowTemplate")
    self._rows = {}
    local closeBtn = FXLoader:Here(root, "WindowBox.TitleBox.CloseSurfaceImg")
    -- 关闭动作由接入层处理，不销毁设计节点。
    self:TrackConnection(closeBtn.Activated:Connect(function()
        self:EmitUIAction("Close", {})
    end))
end

-- 每次打开读取最新配置和完整状态，不重复绑定事件。
function CWorldTeleportView:OnShow()
    self:RefreshUI()
end

-- 新业务 ID 才克隆完整原型，注册事件及独立释放函数。
-- @param worldId string 稳定世界业务 ID
-- @return table 条目节点、按钮及释放函数
function CWorldTeleportView:CreateRow(worldId)
    local row = self.RowTemplate:Clone()
    row.Name = "WorldRow_" .. worldId
    row.Parent = self.ListBox
    row.Visible = true
    local button = FXLoader:Here(row, "TravelBtn")
    local buttonTxt = FXLoader:Here(button, "ButtonTxt")
    -- 点击读取最新状态，传送动作只携带稳定世界 ID。
    local connection = self:TrackConnection(button.Activated:Connect(function()
        local state = self:GetUIState()
        local world = self._rows[worldId].world
        if state.pendingWorldId or state.currentWorldId == worldId then
            return
        end
        if state.level < world.requiredLevel and not self:GetUIConfig().allowLockedAction then
            return
        end
        self:EmitUIAction("Teleport", { worldId = worldId })
    end))
    -- 移除时只释放本条目拥有的连接与克隆节点。
    local release = self:TrackCleanup(function()
        connection:Disconnect()
        row:Destroy()
    end)
    return {
        row = row,
        button = button,
        nameTxt = FXLoader:Here(row, "WorldNameTxt"),
        buttonTxt = buttonTxt,
        rowEdge = FXLoader:Here(row, "BottomEdgeImg"),
        buttonEdge = FXLoader:Here(button, "BottomEdgeImg"),
        release = release,
    }
end

-- 按完整配置更新列表，按稳定 ID 复用、排序、清理条目。
-- @param state table 文件头定义的完整 State
function CWorldTeleportView:Render(state)
    local worlds = self:GetUIConfig().worlds
    local seen = {}
    for index, world in ipairs(worlds) do
        assert(not seen[world.id], "Duplicate world ID: " .. world.id)
        seen[world.id] = true
        local record = self._rows[world.id]
        if not record then
            record = self:CreateRow(world.id)
            self._rows[world.id] = record
        end
        record.world = world
        record.row.Position = UDim2.fromOffset(2, (index - 1) * 106 + 2)
        record.row.LayoutOrder = index
        record.row.BackgroundColor3 = Color3.fromHex(world.color or "#8a4dc2")
        record.rowEdge.BackgroundColor3 = Color3.fromHex(world.edgeColor or "#48246b")
        record.nameTxt.Text = Text.TrSource(world.name)
        local unlocked = state.level >= world.requiredLevel
        local current = state.currentWorldId == world.id
        local buttonText = Text.Tr(TranslationTexts.Go)
        if state.pendingWorldId == world.id then
            buttonText = Text.Tr(TranslationTexts.Teleporting)
        elseif current then
            buttonText = Text.Tr(TranslationTexts.Here)
        elseif not unlocked then
            buttonText = Text.Tr(TranslationTexts.RequiredLevel, {
                level = world.requiredLevel,
            })
        end
        record.buttonTxt.Text = buttonText
        local buttonColor = "#67ed14"
        local edgeColor = "#225a07"
        if not unlocked or state.pendingWorldId then
            buttonColor = "#638079"
            edgeColor = "#263e36"
        end
        record.button.BackgroundColor3 = Color3.fromHex(buttonColor)
        record.buttonEdge.BackgroundColor3 = Color3.fromHex(edgeColor)
        self:SetButtonEnabled(record.button, (unlocked or self:GetUIConfig().allowLockedAction == true)
            and not current and not state.pendingWorldId)
    end
    for worldId, record in pairs(self._rows) do
        if not seen[worldId] then
            record.release()
            self._rows[worldId] = nil
        end
    end
    self.ListBox.CanvasSize = UDim2.fromOffset(0, math.max(0, #worlds * 106 - 10))
    self.EmptyTxt.Visible = #worlds == 0
    self.ErrorTxt.Text = state.errorText or Text.TrSource(state.error or "")
    self.ErrorTxt.Visible = self.ErrorTxt.Text ~= ""
end

-- 由游戏接入实现动作，无静默空处理。
-- @param action string Teleport 或 Close
-- @param payload table Teleport 的 worldId 或 Close 的空表
function CWorldTeleportView:OnUIAction(action, payload)
    error("World teleport integration must implement OnUIAction: " .. action)
end

return CWorldTeleportView
