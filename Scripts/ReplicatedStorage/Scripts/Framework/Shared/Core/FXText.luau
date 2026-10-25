-- 框架文案定义与翻译入口：共享层只定义文案，客户端通过 FC.Localization 翻译。
local RunService = game:GetService("RunService")
local Text = {}

--- 校验按 Key 查询的脚本文案或网络定义；不把字符串隐式当作 Key。
--- @param definition table 含非空字符串 Key、Source 的文案定义。
--- @return table 校验后的定义。
function Text.ValidateDefinition(definition)
    assert(type(definition) == "table", "Text: expected a Key/Source definition")
    assert(type(definition.Key) == "string" and string.find(definition.Key, "%S"),
        "Text: definition.Key must be a non-empty string")
    assert(type(definition.Source) == "string" and string.find(definition.Source, "%S"),
        "Text: definition.Source must be a non-empty string")
    return definition
end

--- 将固定模块前缀和原文表展开为只读定义；两端均可声明，不执行翻译。
--- @param prefix string 简短稳定的 PascalCase 业务前缀，与条目名用句点连接成完整 Key。
--- @param sources table PascalCase 条目名到英文原文或完整参数模板的映射。
--- @return table 按原条目名索引的只读 Key/Source 定义表。
function Text.Define(prefix, sources)
    assert(type(prefix) == "string" and string.match(prefix, "^[A-Z][A-Za-z0-9]*$"),
        "Text: prefix must be a PascalCase business name")
    local definitions = {}
    for name, source in pairs(sources) do
        assert(type(name) == "string" and string.match(name, "^[A-Z][A-Za-z0-9]*$"),
            "Text: entry name must be a PascalCase identifier")
        definitions[name] = table.freeze(Text.ValidateDefinition({
            Key = prefix .. "." .. name,
            Source = source,
        }))
    end
    return table.freeze(definitions)
end

--- 仅客户端可翻译；服务端只传定义和参数，不接受旧原文或字符串 Key。
--- @param definition table 静态脚本文案或显式配置文案定义。
--- @param arguments table? 原生模板参数；itemDefinition 或配置原文 itemSource 在客户端求值为 item。
--- @return string 当前语言文案，缺译时使用定义中的英文兜底。
function Text.Tr(definition, arguments)
    assert(RunService:IsClient(), "Text.Tr is client-only; send the definition and arguments from the server")
    Text.ValidateDefinition(definition)
    local FC = _G.FC
    return FC.Localization:Tr(definition, arguments)
end

--- 仅客户端按原文查询已有译文；不需要 Key，不登记原文或格式化模板参数。
--- @param source string 待查找的完整原文。
--- @return string 当前语言译文，未加载或查询失败时返回原文。
function Text.TrSource(source)
    assert(RunService:IsClient(), "Text.TrSource is client-only")
    local FC = _G.FC
    return FC.Localization:TrSource(source)
end

return Text
