package.path = 'Scripts/?.lua;' .. package.path

local Events = require('mcc.events')
local Transport = require('mcc.event_transport')
local Topology = require('mcc.topology')
local Core = require('mcc.core')
local shared, handlers = {}, {}
ModRef = {
    GetSharedVariable=function(_, key) return shared[key] end,
    SetSharedVariable=function(_, key, value) shared[key] = value end,
}
RegisterConsoleCommandHandler = function(command, callback)
    handlers[command] = callback
    return true
end
do
    local unavailableBus=Events.new()
    local leaked=0
    local savedModRef,savedRegister=ModRef,RegisterConsoleCommandHandler
    ModRef,RegisterConsoleCommandHandler=nil,nil
    assert(not pcall(Transport.subscribe,'ControlActionTriggered',function()leaked=leaked+1 end,
        unavailableBus))
    unavailableBus:emit('ControlActionTriggered','controls','ability','slot')
    assert(leaked==0,'failed transport setup must not retain a local listener')
    ModRef,RegisterConsoleCommandHandler=savedModRef,savedRegister
end
local viewport = {IsValid=function() return true end,
    ProcessConsoleExec=function(_, command)
        return handlers[command] and handlers[command]() or false
    end}
local pc = {IsValid=function() return true end, Player={ViewportClient=viewport}}
local producer, consumer = Events.new(), Events.new()
producer:setPublisher(Transport.publisher(function() return pc end))
local remote = {}
local stop = Transport.subscribe('ControlContextDetached', function(context)
    remote[#remote + 1] = context
end, consumer)
producer:emit('ControlContextDetached', 'combat')
assert(remote[1] == 'combat')
stop()
producer:emit('ControlContextDetached', 'openworld')
assert(#remote == 1)
local secondBus=Events.new()
local second=0
local stopSecond=Transport.subscribe('ControlContextDetached',function()second=second+1 end,secondBus)
producer:emit('ControlContextDetached','combat')
assert(second==1,'each explicitly subscribed event bus must receive transport delivery')
stopSecond()

local seen, executed = {}, 0
local bus = Events.new({onError=function() end})
for _, name in ipairs({'ControlContextAttached','ControlContextDetached',
    'ControlGroupFocused','ControlGroupUnfocused','ControlActionStarted',
    'ControlActionTriggered','ControlActionCompleted','ControlActionCanceled'}) do
    bus:subscribe(name, function(...)
        seen[#seen + 1] = {name, ...}
    end)
end
local backend = {install=function(_, _, callback)
    backendCallback = callback
    return {close=function() return true end}
end}
local core = Core.new({backend=backend, events=bus})
core:registerAction({id='dash', label='Dash', execute=function()
    executed = executed + 1
end})
core:registerLayout({id='basic', label='Basic', bindings={dash={key='F10', trigger='Tap'}}})
assert(core:activate('combat'))
backendCallback('dash', {phase='Started'})
backendCallback('dash', {phase='Triggered'})
backendCallback('dash', {phase='Completed'})
backendCallback('dash', {phase='Canceled'})
assert(executed == 1)
assert(core:deactivate())
assert(seen[1][1] == 'ControlContextAttached' and seen[1][2] == 'combat')
assert(seen[2][1] == 'ControlActionStarted')
assert(seen[3][1] == 'ControlActionTriggered')
assert(seen[4][1] == 'ControlActionCompleted')
assert(seen[5][1] == 'ControlActionCanceled')
assert(seen[6][1] == 'ControlContextDetached')

local topology = Topology.new({id='quickslots', events=bus,
    groups={{id='ability', label='Abilities', actions={'ability.left'}},
        {id='consumable', label='Consumables', actions={'consumable.left'}}},
    dispatch=function() executed = executed + 1 end})
topology:choose('Groups')
topology:selectGroup('consumable')
topology:trigger('slot.1', {phase='Triggered'})
assert(seen[7][1] == 'ControlGroupFocused' and seen[7][3] == 'ability')
assert(seen[8][1] == 'ControlGroupUnfocused' and seen[8][3] == 'ability')
assert(seen[9][1] == 'ControlGroupFocused' and seen[9][3] == 'consumable')
assert(seen[10][1] == 'ControlActionTriggered'
    and seen[10][2] == 'quickslots' and seen[10][3] == 'consumable'
    and seen[10][4] == 'consumable.left')
assert(executed == 2)
assert(not pcall(Events.canonical, 'ControlActionEnded'))
assert(not pcall(Events.canonical, 'ControlContextDettached'))
print('MCC lifecycle events and cross-mod delivery passed')
