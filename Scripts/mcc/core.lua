-- Action identities and player controls are deliberately separate. A producer
-- registers what an action does; a layout decides which input invokes it.
local M = {}
local Events = require('mcc.events')

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
    if value.threshold_seconds ~= nil then
        assert(type(value.threshold_seconds) == 'number'
            and value.threshold_seconds == value.threshold_seconds
            and value.threshold_seconds >= 0 and value.threshold_seconds < math.huge,
            what .. ' threshold_seconds must be a non-negative finite number')
    end
    if value.one_shot ~= nil then
        assert(type(value.one_shot) == 'boolean', what .. ' one_shot must be boolean')
        assert(value.trigger == 'Hold', what .. ' one_shot requires Hold')
    end
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
    local activeGeneration
    local pendingCleanup = {}
    local function closeHandle(handle)
        local called, closed, why = pcall(handle.close, handle)
        if not called then return false, closed end
        if closed ~= true then return false, why or 'close rejected' end
        return true
    end
    local function retryCleanup()
        local remaining, errors = {}, {}
        for _, handle in ipairs(pendingCleanup) do
            local closed, why = closeHandle(handle)
            if not closed then
                remaining[#remaining + 1] = handle
                errors[#errors + 1] = tostring(why)
            end
        end
        pendingCleanup = remaining
        if #errors > 0 then return false, table.concat(errors, '; ') end
        return true
    end
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

    local function dispatch(actionId, event, executionContext)
        if executionContext and not executionContext.isValidGeneration() then return false end
        local action = assert(actions[actionId], 'unknown action: ' .. tostring(actionId))
        local phase = type(event) == 'table' and event.phase or 'Triggered'
        if phase == nil then phase = 'Triggered' end
        if phase == 'Started' or phase == 'Triggered' or phase == 'Completed'
            or phase == 'Canceled' then
            events:emit('ControlAction' .. phase, selected, nil, actionId)
        end
        if phase ~= 'Triggered' then return true end
        -- Event listeners may retire the installation before action delivery.
        if executionContext and not executionContext.isValidGeneration() then return false end
        return action.execute(event, executionContext)
    end

    function api:dispatch(actionId, event)
        -- Explicit dispatch is independent of any backend installation.
        return dispatch(actionId, event)
    end

    function api:activate(activeContext)
        assert(backend and type(backend.install) == 'function', 'input backend required')
        local cleaned, cleanupWhy = retryCleanup()
        if not cleaned then return false, 'pending input cleanup: ' .. cleanupWhy end
        local plan = self:plan(nil, activeContext)
        -- Pending/failed installations never deliver. Each closure retains its
        -- own token, so rebinding the same action cannot revive retired work.
        local generation = {valid=false}
        local executionContext = {isValidGeneration=function()
            return generation.valid
        end}
        local installed = table.pack(pcall(backend.install, backend, plan, function(id, event)
            return dispatch(id, event, executionContext)
        end))
        local replacement, why, failedScope
        if installed[1] then
            replacement, why, failedScope = installed[2], installed[3], installed[4]
        else
            return false, installed[2]
        end
        if not replacement then
            if failedScope then pendingCleanup[#pendingCleanup + 1] = failedScope end
            return false, why
        end
        if active then
            local previous, previousGeneration, previousContext = active, activeGeneration, context
            local closed, closeWhy = closeHandle(active)
            if not closed then
                local removed, removeWhy = closeHandle(replacement)
                if not removed then pendingCleanup[#pendingCleanup + 1] = replacement end
                return false, tostring(closeWhy)
                    .. (removed and '' or '; replacement cleanup: ' .. tostring(removeWhy))
            end
            previousGeneration.valid = false
            activeGeneration = generation
            generation.valid = true
            active, context = replacement, activeContext
            events:emit('ControlContextDetached', previousContext)
            -- A lifecycle listener may replace or deactivate this installation.
            if active == replacement and activeGeneration == generation then
                events:emit('ControlContextAttached', context)
            end
            return true
        end
        activeGeneration = generation
        generation.valid = true
        active, context = replacement, activeContext
        events:emit('ControlContextAttached', context)
        return true
    end

    function api:deactivate()
        local cleaned, cleanupWhy = retryCleanup()
        if not active then
            if not cleaned then return false, 'pending input cleanup: ' .. cleanupWhy end
            return true
        end
        local closed, why = closeHandle(active)
        if not closed then
            return false, tostring(why)
                .. (cleaned and '' or '; pending input cleanup: ' .. cleanupWhy)
        end
        local retiredGeneration, retiredContext = activeGeneration, context
        retiredGeneration.valid = false
        active, context, activeGeneration = nil, nil, nil
        events:emit('ControlContextDetached', retiredContext)
        if not cleaned then return false, 'pending input cleanup: ' .. cleanupWhy end
        return true
    end

    return api
end

return M
