package.path = 'Scripts/?.lua;' .. package.path

local Delivery = require('mcc.player_actions.delivery')
local Events = require('mcc.events')
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
    selectQuickslotGroup=function(_,index)
        seen[#seen+1]='group:'..index
        return true
    end,
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

local previewState={defaultGroup=1,selectedGroup=1,
    groupTypes={[1]='ability',[2]='consumable'}}
local previewTap={id='preview',preview=true,groupIndex=2,binding={mode=0}}
assert(Delivery.deliver({},previewState,previewTap,'Triggered',service))
assert(previewState.selectedGroup==2 and seen[#seen]=='group:2')
assert(Delivery.deliver({},previewState,previewTap,'Triggered',service))
assert(previewState.selectedGroup==1 and seen[#seen]=='group:1')
local previewHold={id='preview',preview=true,groupIndex=2,binding={mode=2}}
assert(Delivery.deliver({},previewState,previewHold,'Started',service))
assert(previewState.selectedGroup==2 and seen[#seen]=='group:2')
assert(Delivery.deliver({},previewState,previewHold,'Completed',service))
assert(previewState.selectedGroup==1 and seen[#seen]=='group:1')
assert(Delivery.deliver({},previewState,previewHold,'Started',service))
assert(Delivery.deliver({},previewState,previewHold,'Canceled',service))
assert(previewState.selectedGroup==1 and seen[#seen]=='group:1')
local groupedTap={id='group-alt',groupIndex=2,binding={mode=0}}
assert(Delivery.deliver({},previewState,groupedTap,'Triggered',service))
assert(previewState.selectedGroup==2 and seen[#seen]=='group:2')
assert(Delivery.deliver({},previewState,groupedTap,'Triggered',service))
assert(previewState.selectedGroup==1 and seen[#seen]=='group:1')

-- Overlapping Hold selectors retain the most recently pressed group until its
-- own release; releasing an older key cannot cancel a newer held selection.
local held={defaultGroup=1,selectedGroup=1,groupTypes={[1]='ability',[2]='consumable'}}
local first={id='first',groupIndex=1,binding={mode=2}}
local second={id='second',groupIndex=2,binding={mode=2}}
assert(Delivery.deliver({},held,first,'Started',service))
assert(Delivery.deliver({},held,second,'Started',service))
assert(Delivery.deliver({},held,first,'Completed',service))
assert(held.selectedGroup==2)
assert(Delivery.deliver({},held,second,'Completed',service))
assert(held.selectedGroup==1)

-- One physical gesture retains its action identity even when group selection
-- changes between Started and Completed.
local phases={}
local gestureEvents=Events.new()
for _,phase in ipairs({'Started','Triggered','Completed'}) do
    gestureEvents:subscribe('ControlAction'..phase,function(_,_,action)
        phases[#phases+1]=phase..':'..action
    end)
end
local gesture={id='shared-one',shared=true,slot=1,binding={mode=0}}
local gestureState={defaultGroup=1,selectedGroup=1,groupTypes={[1]='ability',[2]='consumable'},
    events=gestureEvents}
assert(Delivery.deliver({},gestureState,gesture,'Started',service))
gestureState.selectedGroup=2
assert(Delivery.deliver({},gestureState,gesture,'Triggered',service))
assert(Delivery.deliver({},gestureState,gesture,'Completed',service))
assert(phases[1]=='Started:quickslot.ability.left'
    and phases[2]=='Triggered:quickslot.ability.left'
    and phases[3]=='Completed:quickslot.ability.left')
print('MCC assignments route controls to selected quickslot actions')
