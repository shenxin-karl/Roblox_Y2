local FX = _G.FX or {}
_G.FX = FX

local CurveSampler = {}
FX.CurveSampler = CurveSampler

local curveCache = setmetatable({}, { __mode = "k" })
local formulaCache = setmetatable({}, { __mode = "k" })
local groupCache = setmetatable({}, { __mode = "k" })
local lotteryCache = setmetatable({}, { __mode = "k" })

--- 返回采样结果的副本，避免调用方修改缓存。
--- @param values table 待复制的采样结果。
--- @return table 独立的结果表。
local function CopyValues(values)
    local copy = {}
    for key, value in pairs(values) do
        copy[key] = value
    end
    return copy
end

--- 缓存同一曲线输入的计算结果。
--- @param compiled table 已编译的曲线或概率缓存。
--- @param input any 采样输入或输入范围配置。
--- @param value any 待检查或缓存的值。
local function StoreSample(compiled, input, value)
    compiled.samples[input] = value
end

-- 判断数值是否为有限数字，避免 NaN / inf 进入曲线计算。
--- 过滤会污染曲线结果的非数值和无穷值。
--- @param value any 待检查或缓存的值。
--- @return boolean 是否为有限数字。
local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

--- 限制曲线输入为有限整数。
--- @param value any 待检查或缓存的值。
--- @return boolean 是否为有限整数。
local function IsInteger(value)
    return IsFiniteNumber(value) and value % 1 == 0
end

-- 读取数字；非法值使用 fallback。
--- 为非有限输入采用指定替代值。
--- @param value any 待检查或缓存的值。
--- @param fallback number 无效数字的替代值。
--- @return number 规范化的数字。
local function NormalizeNumber(value, fallback)
    if IsFiniteNumber(value) then
        return value
    end

    return fallback
end

-- 未配置输入限制时保留负数夹到 0 的旧曲线行为。
--- 识别曲线支持的取整方式。
--- @param value any 待检查或缓存的值。
--- @return boolean 是否支持该取整方式。
local function IsCurveRoundMode(value)
    return value == nil or value == "none" or value == "round" or value == "floor" or value == "ceil"
end

--- 按导出配置执行取整。
--- @param value any 待检查或缓存的值。
--- @param roundMode string? 配置指定的取整方式。
--- @return number 取整结果。
local function ApplyCurveRound(value, roundMode)
    if roundMode == "round" then
        return math.floor(value + 0.5)
    end
    if roundMode == "floor" then
        return math.floor(value)
    end
    if roundMode == "ceil" then
        return math.ceil(value)
    end

    return value
end

--- 保持单曲线输入的取整与负数兼容规则。
--- @param value any 待检查或缓存的值。
--- @param roundMode string? 配置指定的取整方式。
--- @param limits table? 输入上下界配置。
--- @return number 规范化的整数输入。
local function NormalizeCurveInput(value, roundMode, limits)
    if not IsFiniteNumber(value) then
        error("Curve input must resolve to a finite integer: " .. tostring(value) .. ".", 3)
    end

    local numberValue = NormalizeNumber(value, 0)
    if numberValue < 0 and not (limits and (limits.min ~= nil or limits.max ~= nil)) then
        numberValue = 0
    end

    local normalizedValue = ApplyCurveRound(numberValue, roundMode or "none")
    if not IsInteger(normalizedValue) then
        error("Curve input must resolve to a finite integer: " .. tostring(value) .. ".", 3)
    end

    return normalizedValue
end

--- 统一曲线组的整数输入。
--- @param value any 待检查或缓存的值。
--- @param roundMode string? 配置指定的取整方式。
--- @return number 规范化的整数输入。
local function NormalizeGroupInput(value, roundMode)
    if not IsFiniteNumber(value) then
        error("CurveGroup input must resolve to a finite integer: " .. tostring(value) .. ".", 3)
    end

    local normalizedValue = ApplyCurveRound(NormalizeNumber(value, 0), roundMode or "none")
    if not IsInteger(normalizedValue) then
        error("CurveGroup input must resolve to a finite integer: " .. tostring(value) .. ".", 3)
    end

    return normalizedValue
end

--- 拒绝非法输入上下界配置。
--- @param input any 采样输入或输入范围配置。
--- @param fieldPath string 错误信息中的配置字段路径。
--- @param level number 错误栈回溯层级。
local function AssertInputLimits(input, fieldPath, level)
    for _, bound in ipairs({ "min", "max" }) do
        if input[bound] ~= nil and not IsInteger(input[bound]) then
            error(fieldPath .. "." .. bound .. " must be a finite integer.", level)
        end
    end
    if input.min ~= nil and input.max ~= nil and input.min > input.max then
        error(fieldPath .. ".min must be less than or equal to max.", level)
    end
end

--- 检查采样输入是否越界。
--- @param value any 待检查或缓存的值。
--- @param limits table? 输入上下界配置。
--- @return number 校验通过的输入。
local function ValidateInputRange(value, limits)
    if limits.min ~= nil and value < limits.min then
        error("Curve.input.min: input " .. tostring(value) .. " is below minimum " .. tostring(limits.min) .. ".", 3)
    end
    if limits.max ~= nil and value > limits.max then
        error("Curve.input.max: input " .. tostring(value) .. " is above maximum " .. tostring(limits.max) .. ".", 3)
    end
    return value
end

--- 拒绝未支持的取整配置。
--- @param value any 待检查或缓存的值。
--- @param fieldPath string 错误信息中的配置字段路径。
--- @param level number 错误栈回溯层级。
local function AssertCurveRoundMode(value, fieldPath, level)
    if not IsCurveRoundMode(value) then
        error(fieldPath .. ' only supports "floor", "ceil", "round" or "none".', level)
    end
end

--- 校验常量或分段线性参数结构。
--- @param parameter table 常量或分段线性参数。
--- @param fieldPath string 错误信息中的配置字段路径。
--- @param level number 错误栈回溯层级。
local function AssertCurveParameter(parameter, fieldPath, level)
    if type(parameter) ~= "table" then
        error(fieldPath .. " must be a constant or linear parameter table.", level)
    end

    if parameter.kind == "constant" then
        if not IsFiniteNumber(parameter.value) then
            error(fieldPath .. ".value must be a finite number.", level)
        end
        return
    end

    if parameter.kind ~= "linear" then
        error(fieldPath .. '.kind must be "constant" or "linear".', level)
    end

    local ranges = parameter.ranges
    if type(ranges) ~= "table" or #ranges == 0 then
        error(fieldPath .. ".ranges must be a non-empty table.", level)
    end

    local previousToInput = nil
    for index = 1, #ranges do
        local range = ranges[index]
        if
            type(range) ~= "table"
            or not IsFiniteNumber(range.fromInput)
            or not IsFiniteNumber(range.toInput)
            or not IsFiniteNumber(range.fromValue)
            or not IsFiniteNumber(range.toValue)
        then
            error(fieldPath .. ".ranges[" .. index .. "] must contain finite fromInput, toInput, fromValue and toValue.", level)
        end

        if not IsInteger(range.fromInput) then
            error(fieldPath .. ".ranges[" .. index .. "].fromInput must be an integer.", level)
        end
        if not IsInteger(range.toInput) then
            error(fieldPath .. ".ranges[" .. index .. "].toInput must be an integer.", level)
        end
        if range.fromInput > range.toInput then
            error(fieldPath .. ".ranges[" .. index .. "].fromInput must be less than or equal to toInput.", level)
        end
        if range.fromInput == range.toInput and range.fromValue ~= range.toValue then
            error(fieldPath .. ".ranges[" .. index .. "].fromValue must be equal to toValue.", level)
        end
        if previousToInput ~= nil and range.fromInput <= previousToInput then
            error(fieldPath .. ".ranges[" .. index .. "].fromInput must be greater than the previous toInput.", level)
        end
        previousToInput = range.toInput
    end
end

--- 校验幂函数和指数函数的公式配置。
--- @param formula table 导出的曲线公式。
--- @param fieldPath string 错误信息中的配置字段路径。
--- @param level number 错误栈回溯层级。
local function AssertCurveFormula(formula, fieldPath, level)
    if type(formula) ~= "table" then
        error(fieldPath .. " must be a curve formula table.", level)
    end
    if formula.kind ~= "Power" and formula.kind ~= "BaseExp" then
        error(fieldPath .. '.kind only supports "Power" or "BaseExp".', level)
    end
    if not IsFiniteNumber(formula.base) then
        error(fieldPath .. ".base must be a finite number.", level)
    end
    AssertCurveParameter(formula.multiplier, fieldPath .. ".multiplier", level)
    AssertCurveParameter(formula.power, fieldPath .. ".power", level)
    AssertCurveRoundMode(formula.rounding, fieldPath .. ".rounding", level)
end

--- 兼容包装曲线与直接公式两种配置。
--- @param curve table 曲线或概率配置。
--- @param level number 错误栈回溯层级。
--- @return table 曲线公式。
--- @return string? 输入取整方式。
local function ResolveCurveFormula(curve, level)
    if type(curve) ~= "table" then
        error('Curve.kind must be "curve", "Power" or "BaseExp".', level)
    end

    if curve.kind == "curve" then
        if type(curve.input) ~= "table" then
            error("Curve.input must be a table.", level)
        end
        AssertInputLimits(curve.input, "Curve.input", level)
        AssertCurveRoundMode(curve.input.rounding, "Curve.input.rounding", level)
        return curve.formula, curve.input.rounding
    end

    return curve, nil
end

-- 将曲线参数编译成只读采样函数。linear ranges 预计算斜率，并使用二分查找定位区间。
--- 预计算分段斜率，减少重复采样开销。
--- @param parameter table 常量或分段线性参数。
--- @return function 参数采样函数。
local function CompileCurveParameter(parameter)
    if parameter.kind == "constant" then
        local value = parameter.value
        return function()
            return value
        end
    end

    local ranges = parameter.ranges
    local compiledRanges = {}
    for index = 1, #ranges do
        local range = ranges[index]
        local fromInput = range.fromInput
        local toInput = range.toInput
        local fromValue = range.fromValue
        local toValue = range.toValue
        compiledRanges[index] = {
            fromInput = fromInput,
            toInput = toInput,
            fromValue = fromValue,
            toValue = toValue,
            slope = fromInput == toInput and 0 or (toValue - fromValue) / (toInput - fromInput),
        }
    end

    return function(input)
        local low = 1
        local high = #compiledRanges
        while low < high do
            local middle = math.floor((low + high) / 2)
            if input <= compiledRanges[middle].toInput then
                high = middle
            else
                low = middle + 1
            end
        end

        local range = compiledRanges[low]
        if input < range.fromInput then
            if low > 1 then
                return compiledRanges[low - 1].toValue
            end
            return range.fromValue
        end
        if input <= range.toInput then
            return range.fromValue + (input - range.fromInput) * range.slope
        end
        return range.toValue
    end
end

--- 由几何衰减分布生成奖品权重。
--- @param distribution table 几何衰减分布参数。
--- @return table 奖品权重数组。
local function BuildGeometricDecayWeights(distribution)
    if
        type(distribution) ~= "table"
        or distribution.kind ~= "GeometricDecay"
        or not IsFiniteNumber(distribution.prizeCount)
        or distribution.prizeCount % 1 ~= 0
        or distribution.prizeCount < 1
    then
        error("LotteryCurve distribution prizeCount must be an integer greater than or equal to 1.", 3)
    end
    if not IsFiniteNumber(distribution.r) or distribution.r <= 0 or distribution.r > 1 then
        error("LotteryCurve distribution r must be greater than 0 and less than or equal to 1.", 3)
    end

    local weights = {}
    for index = 1, distribution.prizeCount do
        weights[index] = distribution.r ^ (index - 1)
    end
    return weights
end

-- 读取 Lua Config 导出的 LotteryCurve 权重数组，也兼容 TS 侧 GeometricDecay distribution。
--- 兼容导出权重与分布描述。
--- @param curve table 曲线或概率配置。
--- @return table 奖品权重数组。
local function GetLotteryWeights(curve)
    if type(curve) ~= "table" then
        error("LotteryCurve weights must be a table.", 3)
    end

    if curve.kind == "lottery" then
        return BuildGeometricDecayWeights(curve.distribution)
    end
    if curve.kind == "GeometricDecay" then
        return BuildGeometricDecayWeights(curve)
    end
    if curve.kind == "LotteryProbability" then
        return GetLotteryWeights(curve.distribution)
    end

    local weights = curve.weights or curve
    if type(weights) ~= "table" or #weights == 0 then
        error("LotteryCurve weights must be a non-empty table.", 3)
    end

    return weights
end

-- 计算权重总和，同时校验权重必须是非负有限数字。
--- 验证非负权重并计算归一化分母。
--- @param weights table 按奖品编号排列的权重。
--- @return number 权重总和。
local function GetLotteryWeightTotal(weights)
    local total = 0
    for index = 1, #weights do
        local weight = weights[index]
        if not IsFiniteNumber(weight) or weight < 0 then
            error("LotteryCurve weights must contain non-negative finite numbers.", 3)
        end
        total = total + weight
    end

    if total <= 0 then
        error("LotteryCurve weights total must be greater than 0.", 3)
    end

    return total
end

--- 缓存概率表与抽奖累计权重。
--- @param curve table 曲线或概率配置。
--- @return table 已编译的概率缓存。
local function CompileLottery(curve)
    local cached = lotteryCache[curve]
    if cached ~= nil then
        return cached
    end

    local weights = GetLotteryWeights(curve)
    local total = GetLotteryWeightTotal(weights)
    local probabilities = {}
    local cumulative = {}
    local accumulated = 0
    for index = 1, #weights do
        accumulated = accumulated + weights[index]
        probabilities[index] = weights[index] / total
        cumulative[index] = accumulated
    end

    local compiled = {
        count = #weights,
        total = total,
        probabilities = probabilities,
        cumulative = cumulative,
    }
    lotteryCache[curve] = compiled
    return compiled
end

-- 判断曲线组列是否为导出后的 LotteryCurve。
--- 区分概率列与普通数值曲线列。
--- @param curve table 曲线或概率配置。
--- @return boolean 是否为概率曲线。
local function IsLotteryCurve(curve)
    return type(curve) == "table" and (
        type(curve.weights) == "table"
        or curve.kind == "lottery"
        or curve.kind == "GeometricDecay"
        or curve.kind == "LotteryProbability"
    )
end

--- 检查曲线组输入和列定义。
--- @param group table 包含输入与列依赖的曲线组。
--- @param level number 错误栈回溯层级。
local function AssertCurveGroup(group, level)
    if type(group) ~= "table" then
        error('CurveGroup.kind must be "curveGroup".', level)
    end
    if group.kind ~= nil and group.kind ~= "curveGroup" then
        error('CurveGroup.kind must be "curveGroup".', level)
    end
    if type(group.columns) ~= "table" or #group.columns == 0 then
        error("CurveGroup columns must contain at least one column.", level)
    end
    if type(group.input) == "table" then
        AssertInputLimits(group.input, "CurveGroup.input", level)
        AssertCurveRoundMode(group.input.rounding, "CurveGroup.input.rounding", level)
    end
end

--- 按输入取整方式缓存编译后的公式。
--- @param formula table 导出的曲线公式。
--- @param inputRounding string? 曲线输入取整方式。
--- @return table 已编译的公式缓存。
local function CompileCurveFormula(formula, inputRounding)
    local roundingKey = inputRounding or "none"
    local cachedByRounding = formulaCache[formula]
    if cachedByRounding ~= nil and cachedByRounding[roundingKey] ~= nil then
        return cachedByRounding[roundingKey]
    end

    AssertCurveFormula(formula, "Curve.formula", 3)
    local compiled = {
        formulaKind = formula.kind,
        base = formula.base,
        inputRounding = inputRounding,
        outputRounding = formula.rounding or "none",
        multiplier = CompileCurveParameter(formula.multiplier),
        power = CompileCurveParameter(formula.power),
        samples = {},
    }
    if cachedByRounding == nil then
        cachedByRounding = {}
        formulaCache[formula] = cachedByRounding
    end
    cachedByRounding[roundingKey] = compiled
    return compiled
end

--- 保留曲线输入范围并复用公式缓存。
--- @param curve table 曲线或概率配置。
--- @return table 带输入范围的曲线缓存。
local function CompileCurve(curve)
    local cached = curveCache[curve]
    if cached ~= nil then
        return cached
    end

    local formula, inputRounding = ResolveCurveFormula(curve, 3)
    local compiled = CopyValues(CompileCurveFormula(formula, inputRounding))
    if curve.kind == "curve" then
        compiled.min = curve.input.min
        compiled.max = curve.input.max
    end
    curveCache[curve] = compiled
    return compiled
end

--- 计算并缓存已编译曲线的单点结果。
--- @param compiled table 已编译的曲线或概率缓存。
--- @param x number 需要采样的输入值。
--- @param normalized boolean? 是否已由曲线组完成输入校验。
--- @return number 采样值。
local function SampleCompiledCurve(compiled, x, normalized)
    local normalizedX = normalized and x or ValidateInputRange(NormalizeCurveInput(x, compiled.inputRounding, compiled), compiled)
    local cached = compiled.samples[normalizedX]
    if cached ~= nil then
        return cached
    end

    local multiplier = compiled.multiplier(normalizedX)
    local power = compiled.power(normalizedX)
    local rawValue
    if compiled.formulaKind == "BaseExp" then
        rawValue = compiled.base + power ^ normalizedX * multiplier
    else
        rawValue = compiled.base + normalizedX ^ power * multiplier
    end

    local result = ApplyCurveRound(rawValue, compiled.outputRounding)
    StoreSample(compiled, normalizedX, result)
    return result
end

-- 采样单条 Curve。采样输入和 linear ranges 的输入边界只支持整数。
-- 支持 Power / BaseExp，支持 multiplier 和 power 使用 Linear ranges 插值参数。
--- 按配置采样单条曲线。
--- @param curve table 曲线或概率配置。
--- @param x number 需要采样的输入值。
--- @return number 采样值。
function CurveSampler:SampleCurve(curve, x)
    return SampleCompiledCurve(CompileCurve(curve), x)
end

-- 读取 LotteryCurve 指定奖品 ID 的概率。
-- prizeId 从 1 开始，对应 weights[1] 到 weights[n]。
--- 读取指定奖品的归一化概率。
--- @param curve table 曲线或概率配置。
--- @param prizeId number 从 1 开始的奖品编号。
--- @return number 奖品概率。
function CurveSampler:SampleLotteryProbability(curve, prizeId)
    local compiled = CompileLottery(curve)
    if not IsFiniteNumber(prizeId) or prizeId % 1 ~= 0 or prizeId < 1 or prizeId > compiled.count then
        error("LotteryCurve prize id must be an integer within weights.", 2)
    end

    return compiled.probabilities[prizeId]
end

-- 按 LotteryCurve 权重抽取奖品 ID。
-- 使用 math.random() 生成 0..1 随机数。
--- 按照累计权重抽取奖品编号。
--- @param curve table 曲线或概率配置。
--- @return number 抽中的奖品编号。
function CurveSampler:SampleLotteryPrize(curve)
    local compiled = CompileLottery(curve)
    local randomValue = math.random()
    if randomValue >= 1 then
        randomValue = 1 - 1e-12
    end

    local target = randomValue * compiled.total
    local low = 1
    local high = compiled.count
    while low < high do
        local middle = math.floor((low + high) / 2)
        if target < compiled.cumulative[middle] then
            high = middle
        else
            low = middle + 1
        end
    end
    return low
end

--- 校验前置列依赖并编译曲线组。
--- @param group table 包含输入与列依赖的曲线组。
--- @return table 已编译的曲线组。
local function CompileCurveGroup(group)
    local cached = groupCache[group]
    if cached ~= nil then
        return cached
    end

    AssertCurveGroup(group, 3)
    local inputRounding = type(group.input) == "table" and group.input.rounding or nil
    local columns = {}
    local columnIndexes = {}
    for index = 1, #group.columns do
        local column = group.columns[index]
        if type(column) ~= "table" then
            error("CurveGroup columns must be tables.", 3)
        end
        if type(column.key) ~= "string" or column.key == "" then
            error("CurveGroup column key must be a non-empty string.", 3)
        end
        if columnIndexes[column.key] ~= nil then
            error("CurveGroup column key must be unique: " .. column.key, 3)
        end
        columnIndexes[column.key] = index
    end

    for index = 1, #group.columns do
        local column = group.columns[index]
        local input = column.input
        local dependencyIndex = nil
        if type(input) == "table" and input.source ~= nil and input.source ~= "groupInput" then
            if input.source ~= "column" or type(input.key) ~= "string" then
                error("CurveGroup column input source must be groupInput or column.", 3)
            end
            dependencyIndex = columnIndexes[input.key]
            if dependencyIndex == nil then
                error("CurveGroup column depends on a missing column.", 3)
            end
            if dependencyIndex >= index then
                error("CurveGroup column can only depend on previous columns.", 3)
            end
        end

        local formula = column.formula
        local isLottery = IsLotteryCurve(formula)
        columns[index] = {
            key = column.key,
            dependencyIndex = dependencyIndex,
            isLottery = isLottery,
            sampler = isLottery
                and CompileLottery(formula)
                or CompileCurveFormula(type(formula) == "table" and formula or {}, inputRounding),
        }
    end

    local compiled = {
        inputRounding = inputRounding,
        min = type(group.input) == "table" and group.input.min or nil,
        max = type(group.input) == "table" and group.input.max or nil,
        columns = columns,
        columnIndexes = columnIndexes,
        samples = {},
    }
    groupCache[group] = compiled
    return compiled
end

--- 在曲线组中检查并采样奖品概率。
--- @param compiled table 已编译的曲线或概率缓存。
--- @param prizeId number 从 1 开始的奖品编号。
--- @param level number 错误栈回溯层级。
--- @return number 奖品概率。
local function SampleCompiledLotteryProbability(compiled, prizeId, level)
    if not IsFiniteNumber(prizeId) or prizeId % 1 ~= 0 or prizeId < 1 or prizeId > compiled.count then
        error("LotteryCurve prize id must be an integer within weights.", level)
    end
    return compiled.probabilities[prizeId]
end

--- 按列顺序计算依赖，返回独立结果表。
--- @param compiled table 已编译的曲线或概率缓存。
--- @param x number 需要采样的输入值。
--- @return table 按列键索引的采样结果。
local function SampleCompiledCurveGroup(compiled, x)
    local normalizedX = ValidateInputRange(NormalizeGroupInput(x, compiled.inputRounding), compiled)
    local cached = compiled.samples[normalizedX]
    if cached ~= nil then
        return CopyValues(cached)
    end

    local values = {}
    local indexedValues = {}
    for index = 1, #compiled.columns do
        local column = compiled.columns[index]
        local input = column.dependencyIndex ~= nil and indexedValues[column.dependencyIndex] or normalizedX
        local value = column.isLottery
            and SampleCompiledLotteryProbability(column.sampler, input, 3)
            or SampleCompiledCurve(column.sampler, input, column.dependencyIndex == nil and (compiled.min ~= nil or compiled.max ~= nil))
        values[column.key] = value
        indexedValues[index] = value
    end

    StoreSample(compiled, normalizedX, values)
    return CopyValues(values)
end

-- 采样 CurveGroup 的所有列。
-- 返回值是以 columns[].key 为键的 table。
-- 普通曲线列返回数值；LotteryCurve 列返回当前输入奖品 ID 对应的概率。
--- 采样曲线组全部列并保留依赖关系。
--- @param group table 包含输入与列依赖的曲线组。
--- @param x number 需要采样的输入值。
--- @return table 按列键索引的采样结果。
function CurveSampler:SampleCurveGroup(group, x)
    return SampleCompiledCurveGroup(CompileCurveGroup(group), x)
end

-- 采样 CurveGroup 中指定列，遵守前置列依赖链。
--- 通过前置列依赖链采样指定列。
--- @param group table 包含输入与列依赖的曲线组。
--- @param columnKey string 目标列的配置键。
--- @param x number 需要采样的输入值。
--- @return number 目标列采样值。
function CurveSampler:SampleCurveGroupColumn(group, columnKey, x)
    local compiled = CompileCurveGroup(group)
    if type(columnKey) ~= "string" or columnKey == "" then
        error("CurveGroup column key must be a non-empty string.", 2)
    end
    if compiled.columnIndexes[columnKey] == nil then
        error("CurveGroup missing column: " .. columnKey, 2)
    end
    return SampleCompiledCurveGroup(compiled, x)[columnKey]
end

-- 只采样 CurveGroup 指定列的公式，不计算该列的前置依赖。
--- 直接采样指定列公式，跳过前置列依赖。
--- @param group table 包含输入与列依赖的曲线组。
--- @param columnKey string 目标列的配置键。
--- @param x number 需要采样的输入值。
--- @return number 目标公式采样值。
function CurveSampler:SampleCurveGroupColumnFormula(group, columnKey, x)
    local compiled = CompileCurveGroup(group)
    if type(columnKey) ~= "string" or columnKey == "" then
        error("CurveGroup column key must be a non-empty string.", 2)
    end
    local columnIndex = compiled.columnIndexes[columnKey]
    if columnIndex == nil then
        error("CurveGroup missing column: " .. columnKey, 2)
    end
    local normalizedX = ValidateInputRange(NormalizeGroupInput(x, compiled.inputRounding), compiled)
    local column = compiled.columns[columnIndex]
    return column.isLottery
        and SampleCompiledLotteryProbability(column.sampler, normalizedX, 2)
        or SampleCompiledCurve(column.sampler, normalizedX, compiled.min ~= nil or compiled.max ~= nil)
end

return CurveSampler
