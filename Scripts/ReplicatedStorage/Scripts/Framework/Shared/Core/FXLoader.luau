-- FXLoader:lua
-- 用于简化 Roblox 中频繁使用 WaitForChild 的问题
local FXLoader = {}
_G.FX.Loader = FXLoader

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MainStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local IsLocalModel = RunService:IsStudio() and RunService:IsClient() and RunService:IsServer()

-- 路径解析辅助函数，仅使用 . 分隔子节点
--- @param path string 从起始节点开始的点分路径。
--- @return {string} 按层级排列的子节点名称。
local function parsePath(path)
    local parts = {}
    for part in string.gmatch(path, "[^%.]+") do
        if part ~= "" then
            table.insert(parts, part)
        end
    end
    return parts
end

-- 从指定起始节点开始，按路径加载子节点
local function loadFromPath(startInstance, path, timeout)
    timeout = timeout or 10
    local parts = parsePath(path)
    local current = startInstance

    for _, part in ipairs(parts) do
        if IsLocalModel then
            current = current:FindFirstChild(part)
        else
            current = current:WaitForChild(part, timeout)
        end
        if not current then
            error("FXLoader: Failed to find child '" .. part .. "' in path: " .. path)
        end
    end
    return current
end

-- 从指定起始节点开始，按路径查找子节点
local function findFromPath(currentInstance, path, timeout)
    timeout = timeout or 10
    local parts = parsePath(path)
    local current = currentInstance
    for _, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then
            break
        end
    end
    return current
end

-- 1️⃣ 从当前脚本（或指定实例）加载子节点
-- FXLoader:Here(script, "ChildName") 或 FXLoader:Here(script, "Parent.Child")
function FXLoader:Here(instance, path, timeout)
    if not instance then
        error("FXLoader:Here: instance cannot be nil")
    end
    if type(path) == "string" then
        return loadFromPath(instance, path, timeout)
    else
        -- 如果 path 是单个名称，直接使用
        return instance:WaitForChild(path, timeout or 10)
    end
end

-- 2️⃣ 从 ReplicatedStorage 加载（客户端和服务器通用）
-- FXLoader:Shared("ModuleName") 或 FXLoader:Shared("Folder.Module")
function FXLoader:Shared(path, timeout)
    return loadFromPath(MainStorage, path, timeout)
end

-- 3️⃣ 从 ServerStorage 加载（仅服务器端）
-- FXLoader:ServerStorage("ModuleName")
function FXLoader:ServerStorage(path, timeout)
    return loadFromPath(ServerStorage, path, timeout)
end

if RunService:IsClient() then
    -- 4️⃣ 从当前玩家加载（仅客户端）
    function FXLoader:Player(path, timeout)
        local player = Players.LocalPlayer
        if not player then
            error("FXLoader:Player: LocalPlayer not found (must be called from client)")
        end
        if path and path ~= "" then
            return loadFromPath(player, path, timeout)
        end
        return nil
    end

    function FXLoader:PlayerGui(path, timeout)
        local player = Players.LocalPlayer
        local PlayerGui = player:WaitForChild("PlayerGui")
        if path and path ~= "" then
            return loadFromPath(PlayerGui, path, timeout)
        end
        return nil
    end
end

-- 5️⃣ 从 Workspace 加载
-- FXLoader:Workspace("ModelName") 或 FXLoader:Workspace("Folder.Model")
function FXLoader:Workspace(path, timeout)
    if path and path ~= "" then
        return loadFromPath(game.Workspace, path, timeout)
    end
    return nil
end

function FXLoader:RequireShared(path, timeout)
    local module = FXLoader:Shared(path, timeout)
    return require(module)
end

function FXLoader:RequireServerStorage(path, timeout)
    local module = FXLoader:ServerStorage(path, timeout)
    return require(module)
end

function FXLoader:Require(currentScript, path, timeout)
    local scriptParent = currentScript
    if not scriptParent then
        error("FXLoader:Require: currentScript is nil")
    end
    local instance = self:Here(scriptParent, path, timeout)
    return require(instance)
end

function FXLoader:RequireFromParent(currentScript, path, timeout)
    if not currentScript then
        error("FXLoader:RequireFromParent: currentScript is nil")
    end
    return self:Require(currentScript.Parent, path, timeout)
end

-- 从指定起始节点开始，按路径查找子节点
function FXLoader:Find(currentInstance, path)
    if not currentInstance then
        error("FXLoader:Find: currentInstance is nil")
    end
    return findFromPath(currentInstance, path)
end

-- 从指定起始节点开始，按路径查找子节点
function FXLoader:FindFromParent(currentScript, path)
    if not currentScript then
        error("FXLoader:FindFromParent: currentScript is nil")
    end
    return self:Find(currentScript.Parent, path)
end

-- 从 Workspace 开始，按路径查找子节点
function FXLoader:FindFromWorkspace(path)
    return self:Find(game.Workspace, path)
end

return true
