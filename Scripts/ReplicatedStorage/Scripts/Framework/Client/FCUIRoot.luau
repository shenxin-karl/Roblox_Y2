-- 框架通用 UI 共享画布：按需创建，随客户端会话保留，不归单个面板或组件所有。
local Players = game:GetService("Players")
local FCUIRoot = {}
local _root

--- 为所有通用提示提供同一个 ScreenGui，不依赖 Studio 预制节点。
--- @return ScreenGui 当前客户端的框架通用画布，调用方只清理自己创建的子节点。
function FCUIRoot.Get()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    if not _root then
        _root = Instance.new("ScreenGui")
        _root.Name = "FrameworkCommonUI"
        _root.ResetOnSpawn = false
        _root.DisplayOrder = 100
        _root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        _root.Parent = playerGui
    end
    return _root
end

return FCUIRoot
