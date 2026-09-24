local M = {}
local controlsId = 'player.quickslots'
local slotNames = {'left', 'top', 'right', 'bottom'}

local function resolved(index, fallbackKind, fallbackSlot)
    if not index then return fallbackKind, fallbackSlot end
    assert(type(index) == 'number' and index >= 1 and index <= 8
        and index % 1 == 0, 'invalid quickslot action assignment')
    return index <= 4 and 'ability' or 'consumable', ((index - 1) % 4) + 1
end

local function signal(state, phase, index, fallbackKind, fallbackSlot, group)
    if not state.events then return end
    if phase ~= 'Started' and phase ~= 'Triggered' and phase ~= 'Completed'
        and phase ~= 'Canceled' then return end
    local kind, slot = resolved(index, fallbackKind, fallbackSlot)
    if not kind or not slotNames[slot] then return end
    state.events:emit('ControlAction' .. phase, controlsId, group,
        'quickslot.' .. kind .. '.' .. slotNames[slot])
end

local function activate(service, index, fallbackKind, fallbackSlot)
    local kind, slot = resolved(index, fallbackKind, fallbackSlot)
    return service:activateQuickslot(kind, slot)
end

function M.deliver(template, state, definition, phase, service)
    if definition.shared then
        local group = state.selectedGroup or state.defaultGroup or 1
        local kind = state.groupTypes and state.groupTypes[group]
        local assignments = state.settings and state.settings.assignments
        local index = assignments and assignments.groups
            and assignments.groups[tostring(group)]
            and assignments.groups[tostring(group)][definition.slot]
        signal(state, phase, index, kind, definition.slot, kind)
        if phase ~= 'Triggered' then return true end
        return kind and activate(service, index, kind, definition.slot)
    end
    if definition.slot then
        if state.settings and state.settings.access == 2
            and state.selectedGroup ~= definition.groupIndex then return true end
        local assignments = state.settings and state.settings.assignments
        local index = assignments and assignments.flat
            and assignments.flat[definition.controlIndex]
        signal(state, phase, index, definition.type, definition.slot, definition.type)
        if phase ~= 'Triggered' then return true end
        return activate(service, index, definition.type, definition.slot)
    end
    if definition.targetSlot and phase ~= 'Triggered' then
        signal(state, phase, definition.actionIndex, definition.type,
            definition.targetSlot, definition.type)
        return true
    end
    local previousGroup = state.selectedGroup
    if definition.binding.mode == 2 and (phase == 'Completed' or phase == 'Canceled') then
        state.selectedGroup = state.defaultGroup
    elseif phase == 'Triggered' or phase == 'Started' then
        if phase == 'Triggered' and definition.binding.mode == 0 and state.defaultUnbound
            and state.selectedGroup == definition.groupIndex then
            state.selectedGroup = state.defaultGroup
        else
            state.selectedGroup = definition.groupIndex
        end
    else
        return true
    end
    -- A detached wheel is no longer a child of the native switcher. The
    -- selection still updates KET state, but cannot change its active index.
    if template.detachSecondaryWheel ~= true then
        local selected = service:selectQuickslotGroup(state.selectedGroup)
        if selected == false then return false end
    end
    if state.events and previousGroup ~= state.selectedGroup then
        local types = state.groupTypes or {}
        state.events:emit('ControlGroupUnfocused', controlsId, types[previousGroup])
        state.events:emit('ControlGroupFocused', controlsId, types[state.selectedGroup])
    end
    if definition.targetSlot and phase == 'Triggered' then
        signal(state, phase, definition.actionIndex, definition.type,
            definition.targetSlot, definition.type)
        return activate(service, definition.actionIndex, definition.type, definition.targetSlot)
    end
    return true
end

return M
