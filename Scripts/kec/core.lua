-- Action identities and player controls are deliberately separate. A producer
-- registers what an action does; a layout decides which input invokes it.
local M = {}
local Events = require('kec.events')

local function identifier(value, what)
    assert(type(value) == 'string' and value:match('^[%a][%w_.%-]*$') and #value <= 96,
        what .. ' must be a stable identifier')
    return value
end

local function binding(value, what)
    assert(type(value) == 'table', what .. ' must be a binding')
    assert(type(value.key) == 'string' and value.key:match('^[%w_]+$')
        and #value.key <= 64, what .. ' needs an Unreal key name')
    assert(value.trigger == 'Tap' or value.trigger == 'Hold',
        what .. ' trigger must be Tap or Hold')
    if value.context ~= nil then identifier(value.context, what .. ' context') end
    return {key=value.key, trigger=value.trigger, context=value.context,
        threshold_seconds=value.threshold_seconds, one_shot=value.one_shot}
end

local function sortedKeys(source)
    local keys = {}
    for key in pairs(source) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function M.new(options)
    options = options or {}
    local actions, layouts, overrides = {}, {}, {}
    local selected, active, backend, context = nil, nil, options.backend, nil
    local events = options.events or Events.shared()
    local api = {}

    function api:subscribe(name, callback) return events:subscribe(name, callback) end
    function api:events() return events end

    function api:registerAction(definition)
        assert(type(definition) == 'table', 'action definition required')
        local id = identifier(definition.id, 'action id')
        assert(not actions[id], 'duplicate action: ' .. id)
        assert(type(definition.label) == 'string' and definition.label:find('%S'),
            'action label required: ' .. id)
        assert(type(definition.execute) == 'function', 'action callback required: ' .. id)
        actions[id] = {id=id, label=definition.label, execute=definition.execute}
        return id
    end

    function api:registerLayout(definition)
        assert(type(definition) == 'table', 'layout definition required')
        local id = identifier(definition.id, 'layout id')
        assert(not layouts[id], 'duplicate layout: ' .. id)
        assert(type(definition.label) == 'string' and definition.label:find('%S'),
            'layout label required: ' .. id)
        assert(type(definition.bindings) == 'table', 'layout bindings required: ' .. id)
        local bindings = {}
        for actionId, source in pairs(definition.bindings) do
            identifier(actionId, 'binding action id')
            bindings[actionId] = binding(source, id .. '.' .. actionId)
        end
        layouts[id] = {id=id, label=definition.label, bindings=bindings}
        if not selected then selected = id end
        return id
    end

    function api:layouts()
        local result = {}
        for _, id in ipairs(sortedKeys(layouts)) do
            result[#result + 1] = {id=id, label=layouts[id].label}
        end
        return result
    end

    function api:selectedLayout() return selected end

    function api:selectLayout(id)
        assert(layouts[id], 'unknown layout: ' .. tostring(id))
        local previous = selected
        selected = id
        if active then
            local ok, why = self:activate(context)
            if not ok then selected = previous; return false, why end
        end
        return true
    end

    function api:configure(actionId, value, layoutId)
        identifier(actionId, 'action id')
        assert(actions[actionId], 'unknown action: ' .. actionId)
        layoutId = layoutId or selected
        assert(layouts[layoutId], 'unknown layout: ' .. tostring(layoutId))
        local nextBinding
        if value == false then nextBinding = false
        else nextBinding = binding(value, actionId) end
        local current = overrides[layoutId] or {}
        local prior = current[actionId]
        current[actionId] = nextBinding
        overrides[layoutId] = current
        if active and layoutId == selected then
            local ok, why = self:activate(context)
            if not ok then current[actionId] = prior; return false, why end
        end
        return true
    end

    function api:plan(layoutId, activeContext)
        layoutId = layoutId or selected
        local layout = assert(layouts[layoutId], 'unknown layout: ' .. tostring(layoutId))
        local result = {}
        local custom = overrides[layoutId] or {}
        local included = {}
        for id in pairs(layout.bindings) do included[id] = true end
        for id in pairs(custom) do included[id] = true end
        for _, id in ipairs(sortedKeys(included)) do
            local selectedBinding = custom[id]
            if selectedBinding == nil then selectedBinding = layout.bindings[id] end
            assert(actions[id], 'layout ' .. layoutId .. ' references missing action ' .. id)
            if selectedBinding and (not selectedBinding.context
                or selectedBinding.context == activeContext) then
                local item = {action=id, key=selectedBinding.key,
                    trigger=selectedBinding.trigger, context=selectedBinding.context,
                    threshold_seconds=selectedBinding.threshold_seconds,
                    one_shot=selectedBinding.one_shot}
                result[#result + 1] = item
            end
        end
        return result
    end

    function api:dispatch(actionId, event)
        local action = assert(actions[actionId], 'unknown action: ' .. tostring(actionId))
        local phase = type(event) == 'table' and event.phase or 'Triggered'
        if phase == nil then phase = 'Triggered' end
        if phase == 'Started' or phase == 'Triggered' or phase == 'Completed'
            or phase == 'Canceled' then
            events:emit('ControlAction' .. phase, selected, nil, actionId)
        end
        if phase ~= 'Triggered' then return true end
        return action.execute(event)
    end

    function api:activate(activeContext)
        assert(backend and type(backend.install) == 'function', 'input backend required')
        local plan = self:plan(nil, activeContext)
        local replacement, why = backend:install(plan, function(id, event)
            return self:dispatch(id, event)
        end)
        if not replacement then return false, why end
        if active then
            local closed, closeWhy = active:close()
            if not closed then
                replacement:close()
                return false, closeWhy
            end
            events:emit('ControlContextDetached', context)
        end
        active, context = replacement, activeContext
        events:emit('ControlContextAttached', context)
        return true
    end

    function api:deactivate()
        if not active then return true end
        local closed, why = active:close()
        if not closed then return false, why end
        events:emit('ControlContextDetached', context)
        active, context = nil, nil
        return true
    end

    return api
end

return M
