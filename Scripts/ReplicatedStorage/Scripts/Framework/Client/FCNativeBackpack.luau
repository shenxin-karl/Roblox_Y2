local StarterGui = game:GetService("StarterGui")
local NativeBackpack = {}

--- 快捷栏关闭时不接入手持输入，背包面板显示与服务端道具数据分离。
--- @param player Player 本地玩家，负责监听背包替换与角色重生。
--- @param network table 已初始化的框架网络模块。
--- @param config table 快捷栏布尔开关与背包容量，背包容量为 0 时关闭面板。
function NativeBackpack.Start(player, network, config)
    local shortcutEnabled = config.ShortcutEnabled
    local inventoryEnabled = config.InventoryCapacity > 0
    if shortcutEnabled and not inventoryEnabled then
        warn("[Framework] Roblox 原生背包面板与快捷栏共用显示接口；关闭背包面板也会隐藏快捷栏。")
    end
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, shortcutEnabled and inventoryEnabled)
    if not shortcutEnabled then
        return
    end

    local bound = {}
    local backpackConnection
    local characterConnection

    --- 避免道具在背包与角色之间移动时重复绑定使用事件。
    --- @param tool Instance 容器中已有或新增的节点，仅绑定 Tool。
    local function bindTool(tool)
        if not tool:IsA("Tool") or bound[tool] then
            return
        end
        bound[tool] = true
        tool.Activated:Connect(function()
            if tool:GetAttribute("FrameworkGridIndex") ~= nil then
                network:SendMsgToServer("C2S_ActivateTool", tool)
            end
        end)
        tool.Destroying:Connect(function()
            bound[tool] = nil
        end)
    end

    --- 同时接入已有和后续复制到达的道具。
    --- @param container Instance 本地玩家的背包或角色。
    --- @return RBXScriptConnection 后续新增节点的监听连接。
    local function bindContainer(container)
        for _, child in ipairs(container:GetChildren()) do
            bindTool(child)
        end
        return container.ChildAdded:Connect(bindTool)
    end

    --- 玩家背包替换后释放旧容器监听。
    --- @param backpack Backpack 当前玩家背包。
    local function bindBackpack(backpack)
        if backpackConnection then
            backpackConnection:Disconnect()
        end
        backpackConnection = bindContainer(backpack)
    end

    --- 角色重生后释放旧角色监听并绑定新角色中的道具。
    --- @param character Model 当前玩家角色。
    local function bindCharacter(character)
        if characterConnection then
            characterConnection:Disconnect()
        end
        characterConnection = bindContainer(character)
    end

    player.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            bindBackpack(child)
        end
    end)
    player.CharacterAdded:Connect(bindCharacter)
    if player.Character then
        bindCharacter(player.Character)
    end
    bindBackpack(player:WaitForChild("Backpack"))
end

return NativeBackpack
