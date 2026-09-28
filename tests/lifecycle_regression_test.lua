-- Regression coverage for lifecycle cutover and event retirement.
local root=arg[1] or '..'
package.path=root..'/ModCoreControls/Scripts/?.lua;'..package.path
local function object(name)
    return {IsValid=function() return true end,GetFullName=function() return name end}
end
local component=object('EnhancedInputComponent /Game/Pawn.Input')
local pawn=object('Pawn /Game/Pawn');pawn.InputComponent=component
local input=object('PlayerInput /Game/Input')
local nativeContext=object('InputMappingContext /Game/IMC_OW.Instance')
input.AppliedInputContexts={[nativeContext]=1}
local controller=object('BP_PlayerController_C /Game/BP_PlayerController_C.Instance')
controller.PlayerInput,controller.AcknowledgedPawn=input,pawn
local subsystem=object('EnhancedInputLocalPlayerSubsystem /Game/Subsystem')
local hooks={}
FindAllOf=function(class)
    if class=='BP_PlayerController_C' then return {controller} end
    if class=='EnhancedInputLocalPlayerSubsystem' then return {subsystem} end
    return {}
end
StaticFindObject=function() end
StaticConstructObject=function() end
FName=function(v) return v end
RegisterHook=function(path,_,after) hooks[path]=after end
NotifyOnNewObject=function() end
UE4SSLuaEventBridge={API_VERSION=4,
    GetCapabilities=function() return {api=4,enhanced_input=true,explicit_target=true,
        detailed_errors=true,target_ue4ss_commit='97b7e501'} end,
    OpenInputComponent=function() end,BindAction=function() end,CloseInputComponent=function() end}
local actualRuntime=require('mc.player_actions.runtime')
local commits,callback,mapped=0,nil,false
local plan={actions={{id='slot',slot=1,type='ability',binding={key=49,mode=0}}}}
package.loaded['mc.player_actions.runtime']=function()
    return {
        prepare=function() return {},plan end,
        commit=function() commits=commits+1;mapped=true end,
        deactivate=function() mapped=false end,
        hasMapping=function() return mapped end,
    }
end
package.loaded['mc.player_actions.dispatch']=function()
    return {bind=function(_,_,_,_,fn) callback=fn; return true end,close=function() return true end}
end
local Events=require('mc.events')
local events=Events.new()
local delivered=0
local host=require('mc.player_actions.ue4ss_host').new(function(fn) fn() end,function() end,
    {contexts={'openworld'},actions={}},events)
local service={activateQuickslot=function() delivered=delivered+1;return true end}
assert(host:apply({category='player.quickslots'},{PrimaryWheel=1},service))
assert(commits==1 and mapped)
mapped=false -- Engine removes MCC context while native gameplay context stays active.
hooks['/Script/EnhancedInput.EnhancedInputSubsystemInterface:RemoveMappingContext']()
assert(commits==2 and mapped and host.ready)

assert(host:deactivate())
assert(not mapped and not host.ready)
hooks['/Script/Engine.PlayerController:ClientRestart']()
assert(not mapped and not host.ready and commits==2)
assert(host:apply({category='player.quickslots'},{PrimaryWheel=1},service))

events:subscribe('ControlActionTriggered',function() host:deactivate() end)
callback(plan.actions[1],'Triggered')
assert(not host.ready and delivered==0)

do
    local present=false
    local native=object('InputAction /Game/Native.Action')
    native.Triggers={}
    local inactive=object('InputAction /Game/Inactive')
    local gate=object('InputTriggerChordAction /Game/Native.Action:MCC_NativeActionGate')
    local runtime=actualRuntime({input={category={}},nativeTargets={'native'},
        resolve=function() return present and native or nil end,
        valid=function(v) return v~=nil end,
        path=function(v) return v:GetFullName():match('^%S+%s+(.+)$') end,
        same=function(a,b) return a==b end,
        each=function(values,fn) for i,v in ipairs(values) do fn(i,v) end;return true end,
        retainInactive=function() return inactive end,
        constructGate=function() return gate end,
        chord=function(v) return v.ChordAction end,
        setChord=function(v,a) v.ChordAction=a end,
        setTriggers=function(v,t) v.Triggers=t end,
        rebuild=function() return true end})
    assert(not pcall(function() runtime:ready() end))
    present=true
    assert(runtime:ready())
    assert(native.Triggers[1]==gate)
end

do
    local bus=Events.new()
    local weak=setmetatable({},{__mode='v'})
    local function add()
        local retained={};weak[1]=retained
        return bus:subscribe('ControlActionTriggered',function() return retained end)
    end
    local stop=add();stop();stop=nil
    collectgarbage('collect');collectgarbage('collect')
    assert(weak[1]==nil)
end
do
    local previousFind=FindAllOf
    FindAllOf=function(class)
        if class=='BP_PlayerController_C' then return {} end
        return previousFind(class)
    end
    ExecuteWithDelay=function() error('boot must not schedule polling') end
    local pending=require('mc.player_actions.ue4ss_host').new(function(fn)fn()end,
        function()end,{contexts={'openworld'},actions={}})
    assert(not pending:apply({category='player.quickslots'},{PrimaryWheel=1},service))
    assert(not pending.bound and not pending.ready,
        'boot without a gameplay player must not bind input')
    FindAllOf=previousFind
    hooks['/Script/Engine.PlayerController:ClientRestart']()
    assert(pending.bound and pending.ready,
        'controller restart must wake attachment once gameplay input exists')
    assert(pending:deactivate())
    FindAllOf=function(class)
        if class=='BP_PlayerController_C' then return {} end
        return previousFind(class)
    end
    local cancelled=require('mc.player_actions.ue4ss_host').new(function(fn)fn()end,
        function()end,{contexts={'openworld'},actions={}})
    assert(not cancelled:apply({category='player.quickslots'},{PrimaryWheel=1},service))
    assert(cancelled:deactivate())
    FindAllOf=previousFind
    hooks['/Script/Engine.PlayerController:ClientRestart']()
    assert(not cancelled.bound and not cancelled.ready,
        'retired host must ignore controller restart')
end
print('PASS: input lifecycle regression cases')
