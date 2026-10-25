local HttpService = game:GetService("HttpService")
local Json = {}
_G.FX.Json = Json

--- @param value table JSON 可序列化对象。
--- @return string JSON 文本；失败返回 nil。
--- @return string 成功为 ok，否则为错误信息。
function Json:Encode(value)
    local ok, result = pcall(HttpService.JSONEncode, HttpService, value)
    if not ok then
        return nil, tostring(result)
    end

    return result, "ok"
end

--- @param value string JSON 文本。
--- @return table 解码对象；失败返回 nil。
--- @return string 成功为 ok，否则为错误信息。
function Json:Decode(value)
    local ok, result = pcall(HttpService.JSONDecode, HttpService, value)
    if not ok then
        return nil, tostring(result)
    end

    return result, "ok"
end

return Json
