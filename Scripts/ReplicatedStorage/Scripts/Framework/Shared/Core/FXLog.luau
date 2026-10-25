local Log = {}
_G.FX.Log = Log
for _, level in ipairs({ "Debug", "Info", "Warn", "Error" }) do
    --- @param self table 日志模块。
    --- @param ... any 日志上下文。
    Log[level] = function(self, ...)
        if level == "Debug" and not game:GetService("RunService"):IsStudio() then
            return
        end

        local output = (level == "Warn" or level == "Error") and warn or print
        output("[" .. level .. "]", ...)
    end

    --- @param self table 日志模块。
    --- @param format string 格式串。
    --- @param ... any 格式参数。
    Log[level .. "Fmt"] = function(self, format, ...)
        self[level](self, string.format(format, ...))
    end
end

return Log
