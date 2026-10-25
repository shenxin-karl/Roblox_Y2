local FX = _G.FX
local FXTime = {}
FX.Time = FXTime

-- 获取日期
function FXTime:GetCurrentDate()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- 日志转换时间戳
function FXTime:DateToTimeStamp(date)
    return os.time({
        year = tonumber(date:sub(1, 4)),
        month = tonumber(date:sub(6, 7)),
        day = tonumber(date:sub(9, 10)),
        hour = tonumber(date:sub(12, 13)),
        min = tonumber(date:sub(15, 16)),
        sec = tonumber(date:sub(18, 19)),
    })
end

-- 时间戳转换日期
function FXTime:TimeStampToDate(timeStamp)
    return os.date("%Y-%m-%d %H:%M:%S", timeStamp)
end

-- 计算两个日期之间的天数差
function FXTime:GetDayDifference(date1, date2)
    local time1 = os.time({
        year = tonumber(date1:sub(1, 4)),
        month = tonumber(date1:sub(6, 7)),
        day = tonumber(date1:sub(9, 10)),
    })
    local time2 = os.time({
        year = tonumber(date2:sub(1, 4)),
        month = tonumber(date2:sub(6, 7)),
        day = tonumber(date2:sub(9, 10)),
    })
    return (time2 - time1) / (24 * 60 * 60)
end

-- 计算两个日期之间的天数差，以当天24点为刷新点
function FXTime:GetDayDifferenceAtMidnight(date1, date2)
    local time1 = os.time({
        year = tonumber(date1:sub(1, 4)),
        month = tonumber(date1:sub(6, 7)),
        day = tonumber(date1:sub(9, 10)),
        hour = 23,
        min = 59,
        sec = 59,
    })
    local time2 = os.time({
        year = tonumber(date2:sub(1, 4)),
        month = tonumber(date2:sub(6, 7)),
        day = tonumber(date2:sub(9, 10)),
        hour = 23,
        min = 59,
        sec = 59,
    })
    return (time2 - time1) / (24 * 60 * 60)
end

-- 计算两个日期之间的秒差
function FXTime:GetSecondDifference(date1, date2)
    local time1 = self:DateToTimeStamp(date1)
    local time2 = self:DateToTimeStamp(date2)
    local diffInSeconds = math.abs(time2 - time1)
    return diffInSeconds
end

-- 计算两个日期之间的分钟差, 向下取整
function FXTime:GetMinuteDifference(date1, date2)
    local seconds = self:GetSecondDifference(date1, date2)
    local minutes = math.floor(seconds / 60)
    return minutes
end

-- 计算两个日期之间的分钟差, 向上取整
function FXTime:GetMinuteDifferenceCeil(date1, date2)
    local seconds = self:GetSecondDifference(date1, date2)
    local minutes = math.ceil(seconds / 60)
    return minutes
end

-- 判断是否午夜
function FXTime:IsMidnight()
    local tm = os.date("*t")
    return tm.hour == 0 and tm.min == 0 and tm.sec == 0
end

-- 获取当天0点的时间
function FXTime:GetMidnightTime()
    local now = os.time()
    local dateTable = os.date("*t", now)
    dateTable.hour = 0
    dateTable.min = 0
    dateTable.sec = 0
    local midnightTimestamp = os.time(dateTable)
    local midnightTime = os.date("%Y-%m-%d %H:%M:%S", midnightTimestamp)
    return midnightTime
end

-- 获取明天0点的时间
function FXTime:GetTomorrowMidnightTime()
    local now = os.time()
    local tomorrow = now + 86400
    local date_table = os.date("*t", tomorrow)
    date_table.hour = 0
    date_table.min = 0
    date_table.sec = 0
    local tomorrow_midnight_timestamp = os.time(date_table)
    local tomorrow_midnight_time = os.date("%Y-%m-%d %H:%M:%S", tomorrow_midnight_timestamp)
    return tomorrow_midnight_time
end

-- 将日期转换为当天0点的时间字符串
function FXTime:DateToMidnightTime(date)
    local timeStamp = self:DateToTimeStamp(date)
    local dateTable = os.date("*t", timeStamp)
    dateTable.hour = 0
    dateTable.min = 0
    dateTable.sec = 0
    local midnightTimestamp = os.time(dateTable)
    local midnightTime = os.date("%Y-%m-%d %H:%M:%S", midnightTimestamp)
    return midnightTime
end

-- 获取下周一0点的时间
function FXTime:GetNextMondayMidnight()
    local now = os.time()
    local day_of_week = tonumber(os.date("%w", now)) or 7 -- 1=星期日，7=星期六
    local days_until_next_monday = (8 - day_of_week) % 7
    if days_until_next_monday == 0 then
        days_until_next_monday = 7
    end
    local next_monday_time = now + days_until_next_monday * 86400
    local t = os.date("*t", next_monday_time)
    t.hour, t.min, t.sec = 0, 0, 0
    return os.date("%Y-%m-%d %H:%M:%S", os.time(t))
end

-- 获取指定时间戳对应的当天 0 点时间戳
function FXTime:GetDayStartTimeStamp(timeStamp)
    local timeTable = os.date("*t", timeStamp)
    timeTable.hour = 0
    timeTable.min = 0
    timeTable.sec = 0
    return os.time(timeTable)
end

-- 获取指定时间戳对应的本周一 0 点时间戳
--- 用秒数回退到周一，避免将跨月的非正 day 传入 Roblox os.time。
--- @param timeStamp number UTC 时间戳。
--- @return number 本周一零点 UTC 时间戳。
function FXTime:GetWeekStartTimeStamp(timeStamp)
    local timeTable = os.date("!*t", timeStamp)
    return self:GetDayStartTimeStamp(timeStamp) - ((timeTable.wday + 5) % 7) * 86400
end

-- 获取指定时间戳对应的下周一 0 点时间戳
function FXTime:GetNextMondayMidnightTimeStamp(timeStamp)
    local weekStartTimeStamp = self:GetWeekStartTimeStamp(timeStamp)
    return weekStartTimeStamp + 7 * 24 * 60 * 60
end

-- 判断两个时间戳是否在同一自然月
function FXTime:IsSameMonth(timeStamp1, timeStamp2)
    local timeTable1 = os.date("*t", timeStamp1)
    local timeTable2 = os.date("*t", timeStamp2)
    return timeTable1.year == timeTable2.year and timeTable1.month == timeTable2.month
end

return true
