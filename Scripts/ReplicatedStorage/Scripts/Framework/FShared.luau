local root = script.Parent:WaitForChild("Shared")
local core = root:WaitForChild("Core")
for _, name in ipairs({ "FXLoader", "FXTable", "FXClass", "FXLog", "FXTask", "FXTime", "FXMath", "FXJson", "FXCurveSampler" }) do
    require(core:WaitForChild(name))
end

_G.FX.Text = require(core:WaitForChild("FXText"))
require(root:WaitForChild("FXUtility"))
require(core:WaitForChild("FXNetwork"))
for _, name in ipairs({ "FXObjectBaseClass", "FXCompBaseClass", "FXModelAnimationCompClass" }) do
    require(root:WaitForChild("Object"):WaitForChild(name))
end

for _, name in ipairs({ "FXSyncManager", "FXDelayedInvokeClass", "FXProximityPromptObjectClass", "FXItemProcessor", "FXBuyProcessor" }) do
    require(root:WaitForChild(name))
end

return _G.FX
