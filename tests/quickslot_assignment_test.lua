package.path = 'Scripts/?.lua;' .. package.path

local Delivery = require('kec.player_actions.delivery')
local Events = require('kec.events')
local seen = {}
local emitted = {}
local events = Events.new()
for _, name in ipairs({'ControlActionStarted', 'ControlActionTriggered',
    'ControlActionCompleted', 'ControlActionCanceled',
    'ControlGroupFocused', 'ControlGroupUnfocused'}) do
    events:subscribe(name, function(controls, group, action)
        emitted[#emitted + 1] = {name, controls, group, action}
    end)
end
local service = {
    activateQuickslot=function(_, kind, slot)
        seen[#seen + 1] = kind .. ':' .. slot
        return true
    end,
    selectQuickslotGroup=function() return true end,
}
local state = {selectedGroup=1, defaultGroup=1,
    events=events,
    groupTypes={[1]='ability',[2]='consumable'},
    settings={access=0, assignments={flat={[1]=8},
        groups={['1']={[2]=6}}}}}
assert(Delivery.deliver({}, state,
    {slot=1, controlIndex=1, type='ability', binding={mode=0}},
    'Triggered', service))
assert(seen[1] == 'consumable:4')
assert(emitted[1][1] == 'ControlActionTriggered'
    and emitted[1][4] == 'quickslot.consumable.bottom')
for _, phase in ipairs({'Started','Completed','Canceled'}) do
    assert(Delivery.deliver({}, state,
        {slot=1, controlIndex=1, type='ability', binding={mode=0}},
        phase, service))
end
assert(emitted[2][1] == 'ControlActionStarted')
assert(emitted[3][1] == 'ControlActionCompleted')
assert(emitted[4][1] == 'ControlActionCanceled')
state.settings.access = 1
assert(Delivery.deliver({}, state,
    {shared=true, slot=2, binding={mode=0}}, 'Triggered', service))
assert(seen[2] == 'consumable:2')
assert(Delivery.deliver({}, state,
    {groupIndex=2, targetSlot=1, type='consumable', actionIndex=1,
        binding={mode=0}}, 'Triggered', service))
assert(seen[3] == 'ability:1')
local groupEvents = {}
for _, item in ipairs(emitted) do
    if item[1] == 'ControlGroupFocused' or item[1] == 'ControlGroupUnfocused' then
        groupEvents[#groupEvents + 1] = item
    end
end
assert(groupEvents[1][1] == 'ControlGroupUnfocused'
    and groupEvents[1][3] == 'ability')
assert(groupEvents[2][1] == 'ControlGroupFocused'
    and groupEvents[2][3] == 'consumable')
print('KEC assignments route controls to selected quickslot actions')
