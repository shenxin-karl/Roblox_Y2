local FXTask = {}
_G.FX.Task = FXTask

--- @param func function 待调度任务。
--- @return thread 可取消的协程句柄。
function FXTask:Spawn(func)
    return task.spawn(func)
end

--- @param duration number 至少等待的秒数。
--- @return number 实际等待秒数。
function FXTask:Wait(duration)
    return task.wait(duration)
end

--- @param func function 下一调度周期执行的任务。
--- @return thread 任务句柄。
function FXTask:Defer(func)
    return task.defer(func)
end

--- @param duration number 延迟秒数。
--- @param func function 待执行任务。
--- @return thread 任务句柄。
function FXTask:Delay(duration, func)
    return task.delay(duration, func)
end

--- @param interval number 调用间隔秒数。
--- @param func function 返回 false 可停止后续调用。
--- @return thread 任务句柄，所属对象析构时必须取消。
function FXTask:Interval(interval, func)
    assert(interval > 0, "interval must be positive")
    return task.spawn(function()
        while true do
            task.wait(interval)
            if func() == false then
                return
            end
        end
    end)
end

--- @param interval number 调用间隔秒数。
--- @param count number 最大调用次数。
--- @param func function 返回 false 提前停止。
--- @return thread 任务句柄。
function FXTask:Runtimes(interval, count, func)
    assert(count > 0 and count % 1 == 0, "count must be positive integer")
    local remaining = count
    return self:Interval(interval, function()
        remaining -= 1
        return func() ~= false and remaining > 0
    end)
end

--- @param handle thread 已完成的任务允许重复取消。
function FXTask:Cancel(handle)
    if handle and coroutine.status(handle) ~= "dead" and handle ~= coroutine.running() then
        task.cancel(handle)
    end
end

return FXTask
