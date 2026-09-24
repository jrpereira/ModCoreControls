-- Public control lifecycle events. Payloads use stable string identifiers so
-- consumers do not need the publisher's Lua objects or HUD implementation.
local M = {}
local names = {
    ControlContextAttached=true, ControlContextDetached=true,
    ControlGroupFocused=true, ControlGroupUnfocused=true,
    ControlActionStarted=true, ControlActionTriggered=true,
    ControlActionCompleted=true, ControlActionCanceled=true,
}
function M.canonical(name)
    assert(type(name) == 'string', 'control event name required')
    assert(names[name], 'unknown control event: ' .. name)
    return name
end

function M.new(options)
    options = options or {}
    local listeners = {}
    local publisher
    local bus = {}

    function bus:setPublisher(callback)
        assert(callback == nil or type(callback) == 'function', 'event publisher must be a function')
        publisher = callback
    end

    function bus:subscribe(name, callback)
        name = M.canonical(name)
        assert(type(callback) == 'function', 'control event callback required')
        local entries = listeners[name] or {}
        listeners[name] = entries
        local entry = {callback=callback, active=true}
        entries[#entries + 1] = entry
        return function()
            entry.active = false
        end
    end

    function bus:receive(name, ...)
        name = M.canonical(name)
        local entries = listeners[name]
        if not entries then return 0 end
        local snapshot = {}
        for _, entry in ipairs(entries) do snapshot[#snapshot + 1] = entry end
        local delivered = 0
        for _, entry in ipairs(snapshot) do
            if entry.active then
                local ok, why = pcall(entry.callback, ...)
                if ok then delivered = delivered + 1
                elseif options.onError then options.onError(name, why) end
            end
        end
        return delivered
    end

    function bus:emit(name, ...)
        name = M.canonical(name)
        local count = self:receive(name, ...)
        if publisher then
            local ok, why = pcall(publisher, name, ...)
            if not ok and options.onError then options.onError(name, why) end
        end
        return count
    end

    return bus
end

local shared
function M.shared()
    if not shared then shared = M.new({onError=function(name, why)
        print('[ModCoreControls] ' .. name .. ' listener failed: ' .. tostring(why) .. '\n')
    end}) end
    return shared
end

return M
