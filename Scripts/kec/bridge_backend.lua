-- The bundled UE4SS Lua Event Bridge owns native input objects. KEC owns the
-- action-to-control map and is the only installed mod folder for both pieces.
local M = {}

function M.new(options)
    assert(type(options) == 'table', 'backend options required')
    assert(type(options.targets) == 'function', 'live target resolver required')
    assert(type(options.queue) == 'function', 'game-thread dispatcher required')
    local api = {}

    function api:install(plan, emit)
        local bridge = options.bridge or rawget(_G, 'UE4SSLuaEventBridge')
        if type(bridge) ~= 'table' or type(bridge.Helpers) ~= 'table'
            or type(bridge.Helpers.OpenInput) ~= 'function'
            or type(bridge.Helpers.Trigger) ~= 'table' then
            return nil, 'bundled UE4SS Lua Event Bridge helper API unavailable'
        end
        local caps = type(bridge.GetCapabilities) == 'function'
            and bridge.GetCapabilities() or nil
        if type(caps) ~= 'table' or tonumber(caps.api or 0) < 4
            or caps.helpers ~= true or caps.trigger_tap ~= true
            or caps.trigger_hold ~= true then
            return nil, 'UE4SS Lua Event Bridge API 4 Tap/Hold helpers required'
        end
        local component, subsystem = options.targets()
        if type(component) ~= 'string' or type(subsystem) ~= 'string' then
            return nil, 'live input component and subsystem paths required'
        end
        local scope, why = bridge.Helpers.OpenInput({
            component_path=component, subsystem_path=subsystem,
            mapping_priority=options.priority or 1000,
            debug_label='KEngineControls',
        })
        if not scope then return nil, why end
        for _, item in ipairs(plan) do
            local trigger = bridge.Helpers.Trigger[item.trigger]
            if trigger == nil then
                scope:Close()
                return nil, 'unsupported trigger: ' .. tostring(item.trigger)
            end
            local settings = {threshold_seconds=item.threshold_seconds,
                one_shot=item.one_shot}
            local handle, bindWhy = scope:Bind(item.key, trigger, function(event)
                options.queue(function() emit(item.action, event) end)
            end, settings)
            if not handle then
                local closed, closeWhy = scope:Close()
                if not closed then bindWhy = tostring(bindWhy) .. '; cleanup: ' .. tostring(closeWhy) end
                return nil, bindWhy
            end
        end
        return {close=function()
            return scope:Close()
        end}
    end

    return api
end

return M
