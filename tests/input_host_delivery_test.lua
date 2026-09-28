package.path = 'Scripts/?.lua;' .. package.path

local calls, callback, closed, commits = {}, nil, 0, 0
local function object(fullName)
    return {IsValid=function() return true end, GetFullName=function() return fullName end}
end
local component = object('EnhancedInputComponent /Game/Pawn.InputComponent')
local pawn = object('Pawn /Game/Pawn')
pawn.InputComponent = component
local input = object('PlayerInput /Game/PlayerInput')
input.AppliedInputContexts = {[object('InputMappingContext /Game/IMC_OW.Instance')] = -1}
local controller = object('BP_PlayerController_C /Game/BP_PlayerController_C.Instance')
controller.PlayerInput, controller.AcknowledgedPawn = input, pawn
local subsystem = object('EnhancedInputLocalPlayerSubsystem /Game/Subsystem')
local subsystems = {subsystem}
local directControllerLookup=true
local staleController
FindAllOf = function(class)
    if class == 'BP_PlayerController_C' then return directControllerLookup and {controller} or {} end
    if class == 'PlayerController' then return staleController and {staleController,controller} or {controller} end
    if class == 'EnhancedInputLocalPlayerSubsystem' then return subsystems end
    return {}
end
StaticFindObject = function() return nil end
StaticConstructObject = function() return nil end
FName = function(value) return value end
local hooks={}
RegisterHook = function(path,_,after) hooks[path]=after end
local notifications={}
NotifyOnNewObject = function(path, fn) notifications[path]=fn end
local bridgeApiVersion = 3
UE4SSLuaEventBridge = {API_VERSION=4,GetCapabilities=function() return {api=bridgeApiVersion,enhanced_input=true,
    explicit_target=true,detailed_errors=true,target_ue4ss_commit='97b7e501'} end,
    OpenInputComponent=function() end, BindAction=function() end, CloseInputComponent=function() end}

local plan = {actions={
    {id='IA_GroupSlot1',groupIndex=1,type='ability',binding={key=0,mode=-2}},
    {id='IA_GroupSlot2',groupIndex=2,type='consumable',binding={key=164,mode=2}},
    {id='IA_SharedSlot1',shared=true,slot=1,binding={key=49,mode=0}},
}}
package.loaded['mc.player_actions.runtime'] = function()
    return {
        prepare=function() return {},plan end,
        commit=function(_,kind,owner)
            assert(callback ~= nil, 'bridge must bind before native input is gated')
            assert(kind == 'OW')
            assert(owner == subsystem, 'context must attach to the current local player subsystem')
            commits = commits + 1
        end,
        deactivate=function() end,
    }
end
package.loaded['mc.player_actions.dispatch'] = function()
    return {
        bind=function(_,_,_,_,fn) callback=fn;return true end,
        close=function() closed=closed+1;return true end,
    }
end
local category = {contexts={'openworld'},actions={}}
local events = require('mc.events').new()
local lifecycle = {}
events:subscribe('ControlContextAttached', function(context)
    lifecycle[#lifecycle + 1] = 'attached:' .. context
end)
events:subscribe('ControlContextDetached', function(context)
    lifecycle[#lifecycle + 1] = 'detached:' .. context
end)
local host = require('mc.player_actions.ue4ss_host').new(function(fn) fn() end,
    function(message) error(message) end, category, events)
local service = {
    activateQuickslot=function(_,kind,slot) calls[#calls+1]=kind..':'..slot;return true end,
    selectQuickslotGroup=function(_,index) calls[#calls+1]='group:'..index;return true end,
}
local accepted, reason = host:apply({category='player.quickslots'}, {PrimaryWheel=1}, service)
assert(not accepted and reason=='UE4SSLuaEventBridge lacks the required Enhanced Input API 4')
assert(commits==0 and callback==nil, 'API 3 must not bind or gate native input')
bridgeApiVersion=4
assert(host:apply({category='player.quickslots'}, {PrimaryWheel=1}, service))
assert(commits == 1)
assert(lifecycle[1] == 'attached:openworld')
local activeCallback = callback
activeCallback(plan.actions[3], 'Triggered')
activeCallback(plan.actions[2], 'Started')
activeCallback(plan.actions[3], 'Triggered')
activeCallback(plan.actions[2], 'Completed')
activeCallback(plan.actions[3], 'Triggered')
assert(table.concat(calls, ',') == 'ability:1,group:2,consumable:1,group:1,ability:1')
assert(host:deactivate() and closed == 1)
assert(lifecycle[2] == 'detached:openworld')
activeCallback(plan.actions[3], 'Triggered')
assert(#calls == 5, 'stale bridge callbacks must not dispatch after deactivation')
directControllerLookup=false
pawn.InputComponent=nil
staleController = object('BP_PlayerController_C /Game/PreviousWorld.BP_PlayerController_C.Instance')
staleController.PlayerInput = input
staleController.AcknowledgedPawn = object('Pawn /Game/PreviousWorld.Pawn')
local retryLogs={}
local later = require('mc.player_actions.ue4ss_host').new(function(fn) fn() end,
    function(message) retryLogs[#retryLogs+1]=message end, category)
local ready,why=later:apply({category='player.quickslots'}, {PrimaryWheel=1}, service)
assert(not ready and why=='gameplay Enhanced Input stack unavailable')
assert(not later.bound and commits==1,
    'a pawn without an assigned input component must not bind or gate input')
pawn.InputComponent=component
hooks['/Script/Engine.PlayerController:ClientRestart']()
assert(commits==2, 'controller restart post-hook must attach after pawn input assignment')
assert(retryLogs[1]=='Quickslot controls attached to player input')
assert(later:deactivate())
directControllerLookup=true
staleController=nil
local localPlayer=object('LocalPlayer /Game/Current.LocalPlayer')
controller.Player=localPlayer
subsystem.GetOuter=function() return localPlayer end
local oldSubsystem=object('EnhancedInputLocalPlayerSubsystem /Game/Previous.Subsystem')
oldSubsystem.GetOuter=function() return object('LocalPlayer /Game/Previous.LocalPlayer') end
subsystems={oldSubsystem,subsystem}
input.AppliedInputContexts={}
local early = require('mc.player_actions.ue4ss_host').new(function(fn) fn() end,
    function(message) error(message) end, category)
assert(early:apply({category='player.quickslots'}, {PrimaryWheel=1}, service),
    'MCC must attach to the player subsystem before the game adds native contexts')
assert(commits==3)
assert(early:deactivate())
print('PASS input host delivery: bound before gate, shared group routing, stale callback guard')
