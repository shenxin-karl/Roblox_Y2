-- 新变异的剑身材质，以及矿石与武器共用的彩虹轮色。
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Visual = {}
local RainbowTag = "RainbowMutationPart"
local RainbowColors = {
    Color3.fromRGB(255, 38, 88),
    Color3.fromRGB(255, 142, 34),
    Color3.fromRGB(255, 218, 58),
    Color3.fromRGB(54, 238, 84),
    Color3.fromRGB(37, 218, 244),
    Color3.fromRGB(43, 90, 255),
    Color3.fromRGB(150, 51, 255),
    Color3.fromRGB(248, 51, 190),
}
local Finishes = {
    Silver = {Color3.fromRGB(224, 232, 241), Enum.Material.Metal, 0.14},
    Gold = {Color3.fromRGB(255, 205, 36), Enum.Material.Metal, 0.12},
    Diamond = {Color3.fromRGB(155, 238, 255), Enum.Material.Glass, 0.1},
    Rainbow = {RainbowColors[1], Enum.Material.SmoothPlastic, 0.04},
}

--- 只给武器副本换材质，所有可见部件一起变成对应的变异外观。
--- @param model Model 尚未放入场景的武器副本。
--- @param mutationId string? 当前武器的变异 ID。
function Visual.ApplyWeapon(model, mutationId)
    local finish = mutationId and Finishes[mutationId]
    if not finish then
        return
    end
    local visiblePart
    for index, node in ipairs(model:GetDescendants()) do
        if node:IsA("SurfaceAppearance") or node:IsA("Decal") then
            node:Destroy()
        elseif node:IsA("SpecialMesh") then
            node.TextureId = ""
            node.VertexColor = Vector3.one
        elseif node:IsA("BasePart") and node.Transparency < 1 then
            visiblePart = visiblePart or node
            if node:IsA("MeshPart") then
                node.TextureID = ""
            elseif node:IsA("UnionOperation") then
                node.UsePartColor = true
            end
            node.MaterialVariant = ""
            node.Color, node.Material, node.Reflectance = finish[1], finish[2], finish[3]
            if mutationId == "Rainbow" then
                node:AddTag(RainbowTag)
            end
        end
    end
    if mutationId == "Diamond" and visiblePart then
        local sparkles = Instance.new("Sparkles")
        sparkles.SparkleColor = Color3.fromRGB(204, 249, 255)
        sparkles.Parent = visiblePart
    end
end

if RunService:IsClient() then
    local parts = {}
    local stepConnection
    local elapsed = 0

    --- 在同一帧更新所有彩虹部件，让整件物体同步轮色且不产生服务器复制流量。
    --- @param deltaTime number 上一帧消耗的秒数。
    local function updateRainbow(deltaTime)
        elapsed += deltaTime
        if elapsed < 1 / 30 then
            return
        end
        elapsed %= 1 / 30
        local phase = (workspace:GetServerTimeNow() % 3) * #RainbowColors / 3
        local index = math.floor(phase)
        local color = RainbowColors[index + 1]:Lerp(RainbowColors[(index + 1) % #RainbowColors + 1], phase - index)
        for part in pairs(parts) do
            if part:IsDescendantOf(workspace) or part:FindFirstAncestorWhichIsA("ViewportFrame") then
                part.Color = color
            end
        end
    end

    --- 注册新出现的彩虹零件；首个零件出现时才开始刷新。
    --- @param part Instance 添加了彩虹标签的实例。
    local function trackPart(part)
        if part:IsA("BasePart") and not part:IsDescendantOf(ReplicatedStorage) then
            parts[part] = true
            if not stepConnection then
                stepConnection = RunService.Heartbeat:Connect(updateRainbow)
            end
        end
    end

    CollectionService:GetInstanceAddedSignal(RainbowTag):Connect(trackPart)
    CollectionService:GetInstanceRemovedSignal(RainbowTag):Connect(function(part)
        parts[part] = nil
        if stepConnection and not next(parts) then
            stepConnection:Disconnect()
            stepConnection = nil
        end
    end)
    for index, part in ipairs(CollectionService:GetTagged(RainbowTag)) do
        trackPart(part)
    end
end

return Visual
