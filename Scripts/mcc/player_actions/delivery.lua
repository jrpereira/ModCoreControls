local M = {}
local controlsId = 'player.quickslots'
local slotNames = {'left', 'top', 'right', 'bottom'}

local function resolved(index, fallbackKind, fallbackSlot)
    if not index then return fallbackKind, fallbackSlot end
    assert(type(index) == 'number' and index >= 1 and index <= 8
        and index % 1 == 0, 'invalid quickslot action assignment')
    return index <= 4 and 'ability' or 'consumable', ((index - 1) % 4) + 1
end

local function signal(state, phase, index, fallbackKind, fallbackSlot, group, current)
    if not state.events then return true end
    if phase ~= 'Started' and phase ~= 'Triggered' and phase ~= 'Completed'
        and phase ~= 'Canceled' then return true end
    local kind, slot = resolved(index, fallbackKind, fallbackSlot)
    if not kind or not slotNames[slot] then return true end
    state.events:emit('ControlAction' .. phase, controlsId, group,
        'quickslot.' .. kind .. '.' .. slotNames[slot])
    return current()==true
end

local function activate(service, index, fallbackKind, fallbackSlot)
    local kind, slot = resolved(index, fallbackKind, fallbackSlot)
    return service:activateQuickslot(kind, slot)
end

local function gesture(state, definition, phase, index, fallbackKind, fallbackSlot, group)
    state.gestures = state.gestures or {}
    local key = definition.id or tostring(definition)
    local owned = state.gestures[key]
    if phase == 'Started' or not owned then
        local kind, slot = resolved(index, fallbackKind, fallbackSlot)
        owned = {index=index, kind=kind, slot=slot, group=group}
        if phase == 'Started' then state.gestures[key] = owned end
    end
    if phase == 'Completed' or phase == 'Canceled' then state.gestures[key] = nil end
    return owned
end

local function signalGesture(state, phase, owned, current)
    return signal(state, phase, owned.index, owned.kind, owned.slot, owned.group, current)
end

local function heldSelection(state)
    local selected, sequence = state.defaultGroup, -1
    for group, order in pairs(state.heldGroups or {}) do
        if order > sequence then selected, sequence = group, order end
    end
    return selected
end

function M.deliver(template, state, definition, phase, service, current)
    current=current or function() return true end
    if not current() then return true end
    if definition.shared then
        local group = state.selectedGroup or state.defaultGroup or 1
        local kind = state.groupTypes and state.groupTypes[group]
        local assignments = state.settings and state.settings.assignments
        local index = assignments and assignments.groups
            and assignments.groups[tostring(group)]
            and assignments.groups[tostring(group)][definition.slot]
        local owned = gesture(state, definition, phase, index, kind, definition.slot, kind)
        if not signalGesture(state, phase, owned, current) then return true end
        if phase ~= 'Triggered' then return true end
        return owned.kind and activate(service, owned.index, owned.kind, owned.slot)
    end
    if definition.slot then
        local assignments = state.settings and state.settings.assignments
        local index = assignments and assignments.flat
            and assignments.flat[definition.controlIndex]
        local owned = gesture(state, definition, phase, index,
            definition.type, definition.slot, definition.type)
        if not signalGesture(state, phase, owned, current) then return true end
        if phase ~= 'Triggered' then return true end
        return activate(service, owned.index, owned.kind, owned.slot)
    end
    local previousGroup = state.selectedGroup
    if definition.binding.mode ~= 2 then return true end
    state.heldGroups = state.heldGroups or {}
    if phase == 'Started' then
        state.groupPressSequence = (state.groupPressSequence or 0) + 1
        state.heldGroups[definition.groupIndex] = state.groupPressSequence
        state.selectedGroup = definition.groupIndex
    elseif phase == 'Completed' or phase == 'Canceled' then
        state.heldGroups[definition.groupIndex] = nil
        state.selectedGroup = heldSelection(state)
    else
        return true
    end
    if not current() then return true end
    local selected = service:selectQuickslotGroup(state.selectedGroup)
    if selected == false then return false end
    if not current() then return true end
    if state.events and previousGroup ~= state.selectedGroup then
        local types = state.groupTypes or {}
        state.events:emit('ControlGroupUnfocused', controlsId, types[previousGroup])
        if not current() then return true end
        state.events:emit('ControlGroupFocused', controlsId, types[state.selectedGroup])
        if not current() then return true end
    end
    return true
end

return M
