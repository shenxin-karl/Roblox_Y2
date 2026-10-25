local FXMath = {}
_G.FX.Math = FXMath

-- decimals: 可选，保留的小数位数，不传则不做舍入
function FXMath:GetRandomFloat(min, max, decimals)
    local value = math.random() * (max - min) + min
    if decimals ~= nil and decimals >= 0 then
        local mult = 10 ^ decimals
        value = math.floor(value * mult + 0.5) / mult
    end
    return value
end

function FXMath:GetRandomInt(min, max)
    return math.random(min, max)
end

function FXMath:Lerp(a, b, t)
    return a + (b - a) * t
end

function FXMath:Clamp(value, min, max)
    return math.max(min, math.min(value, max))
end

function FXMath:Clamp01(value)
    return math.max(0, math.min(value, 1))
end

-- 获取进度条缩放比例
function FXMath:GetProgressScale(progress)
    return Vector2.new(self:Clamp(progress, 0.01, 1), 1)
end

-- 给定 Index 1-无穷大, 将索引使用求余限制到 1-N 之间
function FXMath:WrapIndex(index, maxIndex)
    return (index - 1) % maxIndex + 1
end
return true
