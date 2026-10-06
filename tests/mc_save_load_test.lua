-- Loading a save from a running game frees the old world while MCC is attached
-- to it, and the game's mapping hooks fire during that load. UE4SS IsValid reads
-- the object, so any call on a kept wrapper reads freed memory. Here a freed
-- object raises on every access and counts it; the native lifetime is read
-- without touching the object. MCC's own actions and chords are root-captured
-- and survive.
package.path='Scripts/?.lua;'..package.path
local states=setmetatable({},{__mode='k'})
local Lifetimes=dofile('tests/support/lifetimes.lua')
Lifetimes.install(function(value) return states[value]~=nil and states[value].alive==true end)

local reads,everything,permanent={}, {}, {}
local methods={
    IsValid=function(self) return states[self].alive end,
    GetFullName=function(self) return states[self].full end,
    GetOuter=function(self) return states[self].Outer end,
    GetParent=function(self) return states[self].parent end,
    GetChildrenCount=function() return 2 end,
    SetActiveWidgetIndex=function(self,index) states[self].index=index end,
    SetIsEnabled=function(self,value) states[self].enabled=value end,
    IsA=function() return true end,
    HasAnyInternalFlags=function() return true end,
    MapKey=function(self,action,key)
        local mappings=states[self].Mappings
        mappings[#mappings+1]={Action=action,Key=key}
    end,
    UnmapKey=function(self,action,key)
        local mappings=states[self].Mappings
        for index=#mappings,1,-1 do
            if mappings[index].Action==action and mappings[index].Key.KeyName==key.KeyName then
                table.remove(mappings,index)
            end
        end
    end,
    ProcessConsoleExec=function() end,
}
local function object(class,path,fields)
    local data={full=class..' '..path,alive=true,Mappings={},Triggers={}}
    for key,value in pairs(fields or {}) do data[key]=value end
    local value=setmetatable({},{
        __index=function(_,key)
            if not data.alive then
                reads[#reads+1]=path..'.'..tostring(key)
                error('freed object read: '..path..'.'..tostring(key))
            end
            if methods[key]~=nil then return methods[key] end
            return data[key]
        end,
        __newindex=function(_,key,value)
            if not data.alive then
                reads[#reads+1]=path..'.'..tostring(key)..'='
                error('freed object written: '..path..'.'..tostring(key))
            end
            data[key]=value
        end,
    })
    states[value]=data
    everything[#everything+1]=value
    return value
end
local function free()
    for _,value in ipairs(everything) do
        if not permanent[value] then states[value].alive=false end
    end
end

-- One world's player stack, its applied game context, the overridden native
-- action and the HUD with separately parented wheels.
local world
local function newWorld(n)
    local player=object('LocalPlayer','/Engine/Transient.LocalPlayer_'..n)
    local native=object('InputMappingContext','/Game/Input_'..n..'/IMC_OW.IMC_OW')
    local input=object('PlayerInput','/Engine/Transient.PlayerInput_'..n,
        {AppliedInputContexts={}})
    states[input].AppliedInputContexts[native]=5
    local component=object('EnhancedInputComponent','/Engine/Transient.Component_'..n)
    local pawn=object('Pawn','/Engine/Transient.Pawn_'..n,{InputComponent=component})
    local controller=object('BP_PlayerController_C','/Engine/Transient.BP_PlayerController_C_'..n,
        {PlayerInput=input,AcknowledgedPawn=pawn,Player=player})
    states[player].ViewportClient=object('ViewportClient','/Engine/Transient.Viewport_'..n)
    local subsystem=object('EnhancedInputLocalPlayerSubsystem','/Engine/Transient.Subsystem_'..n,
        {Outer=player})
    local action=object('InputAction','/Game/Input_'..n..'.IA_Test')
    local outside=object('CanvasPanel','/Engine/Transient.HUD_'..n..'.Outside')
    local switcher=object('WidgetSwitcher','/Engine/Transient.HUD_'..n..'.Switcher')
    local ability=object('Wheel','/Engine/Transient.HUD_'..n..'.Ability',{parent=outside,enabled=true})
    local consumable=object('Wheel','/Engine/Transient.HUD_'..n..'.Consumable',{parent=outside,enabled=true})
    local hud=object('WBP_GameHUD_C','/Engine/Transient.HUD_'..n,{QuickslotsSwitcher=switcher,
        WBP_AA_Quickslots=ability,WBP_HUD_Quickslots=consumable})
    world={controller=controller,subsystem=subsystem,input=input,native=native,action=action,
        hud=hud,ability=ability,consumable=consumable}
    return world
end

local retained={}
local gate
local function live(value)
    return value~=nil and states[value]~=nil and states[value].alive and value or nil
end
local hooks,preHooks={}, {}
local callbacks,closed={},0
local bridge={}
function bridge.GetCapabilities() return {api=6,enhanced_input=true,explicit_target=true} end
function bridge.OpenInputComponent(path) return path end
function bridge.BindAction(_,_,phase,callback) callbacks[#callbacks+1]={phase=phase,callback=callback};return #callbacks end
function bridge.CloseInputComponent() closed=closed+1;return true end
local shared={}
_G.ModRef={GetSharedVariable=function(_,key) return shared[key] end,
    SetSharedVariable=function(_,key,value) shared[key]=value end}
local environment
environment={
    bridge=function() return bridge end,
    valid=function(value)
        local ok,result=pcall(function() return value~=nil and value:IsValid() end)
        return ok and result==true
    end,
    unwrap=function(value) return value end,
    full=function(value)
        local ok,result=pcall(function() return value:GetFullName() end)
        return ok and result or nil
    end,
    path=function(value)
        local name=environment.full(value)
        return name and (name:match('^%S+%s+(.+)$') or name) or nil
    end,
    each=function(values,callback)
        for key,value in pairs(values or {}) do
            if type(key)=='number' then callback(value,key) else callback(key,value) end
        end
        return true
    end,
    find=function(class)
        if class=='BP_PlayerController_C' then return live(world.controller) end
        if class=='EnhancedInputLocalPlayerSubsystem' then return live(world.subsystem) end
    end,
    all=function(class)
        local found=class=='BP_PlayerController_C' and world.controller
            or class=='EnhancedInputLocalPlayerSubsystem' and world.subsystem
            or class=='InputAction' and world.action or nil
        return live(found) and {found} or {}
    end,
    retain=function(kind,name)
        local key=kind..':'..name
        if not retained[key] then
            retained[key]=object(kind,'/Engine/Transient.'..name)
            permanent[retained[key]]=true
        end
        return retained[key]
    end,
    initialize=function() end,
    trigger=function(action,name)
        local value=object(name,environment.path(action)..'.'..name)
        permanent[value]=true
        return value
    end,
    name=function(value) return value end,
    -- StaticFindObject finds no collected object.
    resolve=function(path)
        for _,value in ipairs(everything) do
            if states[value].alive and environment.path(value)==path then return value end
        end
    end,
    setIndicatorAction=function() return true end,
    constructOverride=function(action,marker)
        if not gate then
            gate=object('InputTriggerChordAction',environment.path(action)..':'..marker)
            permanent[gate]=true
        end
        return gate
    end,
    rebuild=function(playerInput)
        for context in pairs(playerInput.AppliedInputContexts) do
            assert(environment.valid(context))
        end
        return true
    end,
    hudForOwner=function() return live(world.hud) end,
    inGameThread=function() return true end,
    hook=function(name,callback) hooks[name]=callback;return 1,2 end,
    preHook=function(name,callback) preHooks[name]=callback;return 3,4 end,
    notify=function() return true end,
    unhook=function() return true end,
}
local jobs={}
local function drain()
    while #jobs>0 do table.remove(jobs,1)() end
end
local warnings={}
local host=require('mc_input_host').new(function(callback) jobs[#jobs+1]=callback;return true end,
    function(message) warnings[#warnings+1]=message end,nil,environment)
local plan={contexts={'exploration','combat'},defaultGroup=1,overrides={IA_Test=true},
    bindings={{id='global.slot1',keyName='One',mode=0,phases={'Triggered'},
        action={type='ability',slot=1}}}}

local first=newWorld(1)
assert(host:apply(plan))
drain()
assert(host.ready and #states[first.native].Mappings==1, 'MCC maps its key into the game context')
assert(states[first.action].Triggers[1]==gate, 'the override chord is installed')
assert(states[first.ability].enabled==true and states[first.consumable].enabled==false,
    'the quickslot wheels are routed to the default group')

-- The save loads: the old world, its input assets and its HUD are collected,
-- and the game clears and rebuilds its mappings.
free()
hooks['/Script/EnhancedInput.EnhancedInputSubsystemInterface:ClearAllMappings']()
hooks['/Script/Engine.PlayerController:ClientRestart']()
drain()
assert(#reads==0,'freed objects read: '..table.concat(reads,', '))
assert(not host.ready and host.phase=='pending','MCC retires from the collected world')

-- The new world's player arrives.
local second=newWorld(2)
preHooks['/Script/EnhancedInput.EnhancedInputSubsystemInterface:RequestRebuildControlMappings'](second.subsystem)
hooks['/Script/Engine.PlayerController:ClientRestart']()
drain()
assert(#reads==0,'freed objects read: '..table.concat(reads,', '))
assert(host.ready and #states[second.native].Mappings==1,'MCC attaches to the new player')
assert(states[second.action].Triggers[1]==gate,'the new native action is overridden')
assert(states[second.ability].enabled==true and states[second.consumable].enabled==false)
assert(host:stop())
assert(#reads==0,'freed objects read: '..table.concat(reads,', '))
print('PASS: a save load reads no collected object')
