-- HUD-independent control topology for action collections such as quickslots.
-- Flat has one control per action. Groups has one selector per group plus a
-- shared control per position. Advanced adds group-specific controls to Flat.
-- The visual consumer may observe group changes.
local M = {}
local Events = require('mc.events')

local function id(value, where)
    assert(type(value) == 'string' and value:match('^[%a][%w_.%-]*$'),
        where .. ' must be a stable identifier')
    return value
end

local function copy(list)
    local result = {}
    for index, value in ipairs(list) do result[index] = value end
    return result
end

function M.new(options)
    assert(type(options) == 'table' and type(options.groups) == 'table'
        and #options.groups > 0, 'action groups required')
    assert(type(options.dispatch) == 'function', 'action dispatcher required')
    local groups, byId, flat, maxSlots = {}, {}, {}, 0
    local actionIds = {}
    for index, source in ipairs(options.groups) do
        assert(type(source) == 'table', 'action group required')
        local groupId = id(source.id, 'group id')
        assert(not byId[groupId], 'duplicate group: ' .. groupId)
        assert(type(source.label) == 'string' and source.label:find('%S'),
            'group label required')
        assert(type(source.actions) == 'table' and #source.actions > 0,
            'group actions required')
        local actions = {}
        for slot, action in ipairs(source.actions) do
            actions[slot] = id(action, 'action id')
            assert(not actionIds[action], 'duplicate action in topology: ' .. action)
            actionIds[action] = true
            flat[#flat + 1] = action
        end
        maxSlots = math.max(maxSlots, #actions)
        local group = {id=groupId, label=source.label, actions=actions, index=index}
        groups[index], byId[groupId] = group, group
    end
    local fixed, fixedById = {}, {}
    for _, source in ipairs(options.fixed or {}) do
        assert(type(source) == 'table', 'fixed action slot required')
        local fixedId = id(source.id, 'fixed slot id')
        local action = id(source.action, 'fixed action id')
        assert(not fixedById[fixedId], 'duplicate fixed slot: ' .. fixedId)
        assert(not actionIds[action], 'duplicate action in topology: ' .. action)
        assert(type(source.label) == 'string' and source.label:find('%S'),
            'fixed slot label required')
        actionIds[action] = true
        local slot = {id=fixedId, label=source.label, action=action}
        fixed[#fixed + 1], fixedById[fixedId] = slot, slot
    end
    local mode = 'Flat'
    local events = options.events or Events.shared()
    local controlsId = options.id or 'mcc.controls'
    local selectedGroup = options.defaultGroup or groups[1].id
    assert(byId[selectedGroup], 'unknown default group')
    local flatAssignment, groupedAssignment, advancedAssignment = copy(flat), {}, {}
    for _, group in ipairs(groups) do
        groupedAssignment[group.id] = copy(group.actions)
        advancedAssignment[group.id] = copy(group.actions)
    end
    local api = {}

    function api:subscribe(name, callback) return events:subscribe(name, callback) end

    local function actionEvent(action, event, group)
        local phase = type(event) == 'table' and event.phase or 'Triggered'
        if phase == nil then phase = 'Triggered' end
        if phase == 'Started' or phase == 'Triggered' or phase == 'Completed'
            or phase == 'Canceled' then
            events:emit('ControlAction' .. phase, controlsId, group, action)
        end
        if phase ~= 'Triggered' then return true end
        return options.dispatch(action, event)
    end

    function api:layout() return mode end
    function api:group() return selectedGroup end

    function api:choose(layout)
        assert(layout == 'Flat' or layout == 'Groups' or layout == 'Advanced',
            'layout must be Flat, Groups, or Advanced')
        if mode ~= layout then
            if mode ~= 'Flat' then
                events:emit('ControlGroupUnfocused', controlsId, selectedGroup)
            end
            mode = layout
            if mode ~= 'Flat' then
                events:emit('ControlGroupFocused', controlsId, selectedGroup)
            end
        end
        return true
    end

    function api:selectGroup(groupId)
        assert(byId[groupId], 'unknown group: ' .. tostring(groupId))
        if selectedGroup == groupId then return true end
        local previous = selectedGroup
        selectedGroup = groupId
        if options.onGroupChanged then options.onGroupChanged(groupId) end
        if mode ~= 'Flat' then
            events:emit('ControlGroupUnfocused', controlsId, previous)
            events:emit('ControlGroupFocused', controlsId, groupId)
        end
        return true
    end

    function api:assign(layout, slot, action, groupId)
        assert(layout == 'Flat' or layout == 'Groups' or layout == 'Advanced', 'invalid layout')
        id(action, 'action id')
        assert(actionIds[action], 'unknown action: ' .. action)
        assert(type(slot) == 'number' and slot % 1 == 0 and slot >= 1,
            'slot must be a positive integer')
        if layout == 'Flat' then
            assert(slot <= #flatAssignment and groupId == nil, 'invalid flat slot')
            flatAssignment[slot] = action
        elseif layout == 'Groups' then
            local group = assert(byId[groupId], 'unknown group')
            assert(slot <= #group.actions, 'invalid grouped slot')
            groupedAssignment[groupId][slot] = action
        else
            local group = assert(byId[groupId], 'unknown group')
            assert(slot <= #group.actions, 'invalid advanced slot')
            advancedAssignment[groupId][slot] = action
        end
        return true
    end

    function api:assignment(layout, slot, groupId)
        if layout == 'Flat' then return flatAssignment[slot] end
        if layout == 'Groups' and groupedAssignment[groupId] then
            return groupedAssignment[groupId][slot]
        end
        if layout == 'Advanced' and advancedAssignment[groupId] then
            return advancedAssignment[groupId][slot]
        end
        return nil
    end

    function api:controls(layout)
        layout = layout or mode
        assert(layout == 'Flat' or layout == 'Groups' or layout == 'Advanced', 'invalid layout')
        local result = {}
        if layout == 'Flat' or layout == 'Advanced' then
            for slot, action in ipairs(flatAssignment) do
                result[#result + 1] = {id='flat.' .. slot, label='Action ' .. slot,
                    action=action}
            end
        end
        if layout == 'Advanced' then
            for _, group in ipairs(groups) do
                for slot, action in ipairs(advancedAssignment[group.id]) do
                    result[#result + 1] = {id='group.' .. group.id .. '.slot.' .. slot,
                        label=group.label .. ' slot ' .. slot,
                        group=group.id, slot=slot, action=action}
                end
            end
        elseif layout == 'Groups' then
            for _, group in ipairs(groups) do
                result[#result + 1] = {id='group.' .. group.id,
                    label=group.label, group=group.id}
            end
            for slot = 1, maxSlots do
                result[#result + 1] = {id='slot.' .. slot,
                    label='Slot ' .. slot, slot=slot}
            end
        end
        for _, slot in ipairs(fixed) do
            result[#result + 1] = {id='fixed.' .. slot.id, label=slot.label,
                action=slot.action, fixed=true}
        end
        return result
    end

    function api:trigger(controlId, event)
        assert(type(controlId) == 'string', 'control id required')
        local fixedId = controlId:match('^fixed%.([%w_.%-]+)$')
        if fixedId then
            local slot = assert(fixedById[fixedId], 'unknown fixed control: ' .. controlId)
            return actionEvent(slot.action, event, nil)
        end
        if mode == 'Flat' or mode == 'Advanced' then
            local slot = tonumber(controlId:match('^flat%.(%d+)$'))
            if slot and flatAssignment[slot] then
                return actionEvent(flatAssignment[slot], event, nil)
            end
            if mode == 'Flat' then error('unknown flat control: ' .. controlId) end
            local groupId, groupSlot = controlId:match('^group%.([%w_.%-]+)%.slot%.(%d+)$')
            local advancedAction = groupId and advancedAssignment[groupId]
                and advancedAssignment[groupId][tonumber(groupSlot)]
            assert(advancedAction, 'unknown advanced control: ' .. controlId)
            self:selectGroup(groupId)
            return actionEvent(advancedAction, event, groupId)
        end
        local groupId = controlId:match('^group%.([%w_.%-]+)$')
        if groupId then return self:selectGroup(groupId) end
        local slot = tonumber(controlId:match('^slot%.(%d+)$'))
        local action = slot and groupedAssignment[selectedGroup][slot]
        assert(action, 'unknown grouped control: ' .. controlId)
        return actionEvent(action, event, selectedGroup)
    end

    function api:snapshot()
        local grouped, advanced = {}, {}
        for _, group in ipairs(groups) do
            grouped[group.id] = copy(groupedAssignment[group.id])
            advanced[group.id] = copy(advancedAssignment[group.id])
        end
        return {layout=mode, selectedGroup=selectedGroup,
            flat=copy(flatAssignment), groups=grouped, advanced=advanced,
            fixed=copy(fixed)}
    end

    return api
end

return M
