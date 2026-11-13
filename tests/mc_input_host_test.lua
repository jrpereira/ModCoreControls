package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local function object(class,path)
    local value={class=class,path=path,full=class..' '..path,valid=true}
    function value:IsValid()return self.valid end
    function value:GetFullName()return self.full end
    return value
end
local player=object('LocalPlayer','/Engine/Transient.LocalPlayer_0')
local input=object('PlayerInput','/Engine/Transient.PlayerInput_0')
local component=object('EnhancedInputComponent','/Engine/Transient.Component_1')
local pawn=object('Pawn','/Engine/Transient.Pawn_0');pawn.InputComponent=component
local controller=object('BP_PlayerController_C','/Engine/Transient.BP_PlayerController_C_0')
controller.PlayerInput,controller.AcknowledgedPawn,controller.Player=input,pawn,player
local subsystem=object('EnhancedInputLocalPlayerSubsystem','/Engine/Transient.Subsystem_0')
subsystem.Outer=player
local native=object('InputMappingContext','/Game/Input.IMC_OW.Runtime')
input.AppliedInputContexts={[native]=5}
-- MCC maps its keys into the game's own context; it never adds one.
native.Mappings={}
function native:MapKey(action,key)self.Mappings[#self.Mappings+1]={Action=action,Key=key}end
function native:UnmapKey(action,key)
    for index=#self.Mappings,1,-1 do
        local entry=self.Mappings[index]
        if entry.Action==action and entry.Key.KeyName==key.KeyName then table.remove(self.Mappings,index) end
    end
end
local function mccKeys()
    local keys={}
    for _,entry in ipairs(native.Mappings) do
        if entry.Action.path:find('IA_MCC_',1,true) then keys[#keys+1]=entry.Key.KeyName end
    end
    return keys
end
function subsystem:AddMappingContext()error('MCC must not add a mapping context')end
local nativeOverride=object('InputAction','/Game/Input.IA_Test');nativeOverride.Triggers={}
function subsystem:AddMappingContext(mapping,priority)input.AppliedInputContexts[mapping]=priority end
function subsystem:RemoveMappingContext(mapping)input.AppliedInputContexts[mapping]=nil end

local retained={}
local function retain(kind,name)
    local key=kind..':'..name
    if retained[key] then return retained[key] end
    local value=object(kind,'/Engine/Transient.'..name);value.Triggers={}
    function value:UnmapAll()self.mappings={}end
    function value:MapKey(action,key)self.mappings[#self.mappings+1]={action=action,key=key}end
    retained[key]=value;return value
end
local callbacks,closeCount={},0
local bridge={API_VERSION=5}
function bridge.GetCapabilities()return {api=6,enhanced_input=true,explicit_target=true}end
function bridge.OpenInputComponent(path)return path end
function bridge.BindAction(_,_,phase,callback)callbacks[#callbacks+1]={phase=phase,callback=callback};return #callbacks end
function bridge.CloseInputComponent()closeCount=closeCount+1;return true end
local hooks={}
-- The game adding a gameplay mapping context: MCC's signal that its input is set up.
local SETUP='/Script/DogwoodSystem.DWSystemBlueprintFunctionLibrary:AddInputMappingContext'
local gameplayContext={full='InputMappingContext /Game/Input/IMC_OW.IMC_OW'}
local function gameSetsUpInput() hooks[SETUP](nil,nil,gameplayContext) end
local hookIds,nextHookId,unhooked={},0,{}
local failUnhook=true
local availableBridge
local originalIndicator=object('InputAction','/Game/Input.IA_Original')
local indicator=object('Widget','/Engine/Transient.AbilityLeft')
indicator.EnhancedInputAction=originalIndicator
local bindings=object('Bindings','/Engine/Transient.AbilityBindings');bindings.Left=indicator
local wheel=object('Wheel','/Engine/Transient.AbilityWheel');wheel.WBP_AA_Quickslots_Bindings=bindings
local hud=object('WBP_GameHUD_C','/Engine/Transient.HUD');hud.WBP_AA_Quickslots=wheel
local resolved={[indicator.path]=indicator,[originalIndicator.path]=originalIndicator}
local indicatorState,indicatorSets=nil,0
local overrideGate,overrideRebuilds,rejectOverrideRebuild=nil,0,false
local environment={
    bridge=function()return availableBridge end,
    valid=function(value)return value and value.valid end,
    unwrap=function(value)return value end,
    full=function(value)return value.full end,
    path=function(value)return value.path end,
    each=function(values,callback)
        for key,value in pairs(values) do
            if type(key)=='number' then callback(value,key) else callback(key,value) end
        end
        return true
    end,
    find=function(class,predicate)
        local value=class=='BP_PlayerController_C' and controller
            or class=='EnhancedInputLocalPlayerSubsystem' and subsystem
            or class=='WBP_GameHUD_C' and hud or nil
        return value and (not predicate or predicate(value)) and value or nil
    end,
    all=function(class)
        if class=='EnhancedInputLocalPlayerSubsystem' then return {subsystem} end
        if class=='InputAction' then return {nativeOverride} end
        return {}
    end,
    retain=retain,
    initialize=function()end,
    trigger=function(_,name)local value=object(name,'/Engine/Transient.'..name);value.Triggers={};return value end,
    name=function(value)return value end,
    resolve=function(path)return resolved[path] end,
    setIndicatorAction=function(widget,action)
        widget.EnhancedInputAction=action;indicatorSets=indicatorSets+1
        if action then resolved[action.path]=action end
        return true
    end,
    loadIndicatorState=function()return indicatorState end,
    saveIndicatorState=function(value)indicatorState=value;return true end,
    constructOverride=function(action,marker)
        if not overrideGate then
            overrideGate=object('InputTriggerChordAction',action.path..':'..marker)
            overrideGate.rooted=true
        end
        return overrideGate
    end,
    rebuild=function()
        overrideRebuilds=overrideRebuilds+1
        if rejectOverrideRebuild then error('injected override rebuild failure') end
        return true
    end,
    options={},
    hook=function(name,callback)
        nextHookId=nextHookId+2
        hooks[name]=callback;hookIds[name]={nextHookId-1,nextHookId}
        return nextHookId-1,nextHookId
    end,
    unhook=function(name,pre,post)
        local ids=assert(hookIds[name],'unknown hook')
        assert(pre==ids[1] and post==ids[2],'hook removal omitted name or ids')
        if failUnhook then failUnhook=false;return false,'temporary removal failure' end
        hooks[name]=nil;hookIds[name]=nil;unhooked[#unhooked+1]=name
        return true
    end,
    notify=function(name,callback)hooks[name]=callback;return true end,
}
local calls={}
local service={
    activate=function(_,kind,slot)calls[#calls+1]=kind..':'..slot;return true end,
    select=function()return true end,
}
local host=require('mc_input_host').new(function(callback)callback();return true end,function()end,service,environment)
local plan={contexts={'exploration','combat'},bindings={{id='global.slot1',keyName='One',mode=0,
    phases={'Triggered'},action={type='ability',slot=1}}},overrides={IA_Test=true}}
local active,why=host:apply(plan)
assert(not active and why=='UE4SSLuaEventBridge input API unavailable')
availableBridge=bridge
assert(host:sync())
assert(next(hooks) and #callbacks==1)
assert(#mccKeys()==1 and mccKeys()[1]=='One','MCC key must be mapped into the game context')
assert(indicator.EnhancedInputAction==retained['InputAction:IA_MCC_global_slot1'])
assert(indicatorSets==1)
assert(nativeOverride.Triggers[1]==overrideGate and overrideGate.rooted)
callbacks[1].callback({})
assert(calls[1]=='ability:1')
local stale=callbacks[1].callback
component=object('EnhancedInputComponent','/Engine/Transient.Component_2')
pawn.InputComponent=component
assert(host:sync())
assert(closeCount==1 and #callbacks==2,'component replacement must retire and reinstall callbacks')
assert(indicatorSets==3,'component replacement must restore and refresh the indicator')
stale({})
assert(#calls==1,'retired callback generation must not deliver')
callbacks[2].callback({})
assert(#calls==2)
local changed={contexts={'exploration','combat'},bindings={{id='global.slot1',keyName='Two',mode=0,
    phases={'Triggered'},action={type='ability',slot=1}}},overrides={IA_Test=true}}
assert(host:apply(changed))
assert(indicatorSets==5,'Apply must reassign the action so CommonUI refreshes its key glyph')
assert(#mccKeys()==1 and mccKeys()[1]=='Two','Apply must replace the mapped key, not add one')
-- The game lifting every gameplay context for a moment, as during some skills, keeps
-- MCC's input: its keys stay in the game's context and apply again when it returns.
local generation,closes=host.generation,closeCount
input.AppliedInputContexts[native]=nil
assert(host:sync())
assert(host.ready and host.generation==generation and closeCount==closes,'a lifted context must not retire MCC input')
assert(#mccKeys()==1 and nativeOverride.Triggers[1]==overrideGate and indicatorSets==5)
input.AppliedInputContexts[native]=5
assert(host:sync())
assert(host.ready and host.generation==generation and closeCount==closes and indicatorSets==5,
    'its return needs no work')
assert(#mccKeys()==1)
rejectOverrideRebuild=true
local removed=host:deactivate()
assert(not removed and host.ready and nativeOverride.Triggers[1]==overrideGate,
    'failed override restoration must leave active replacement input intact')
rejectOverrideRebuild=false
assert(host:deactivate() and closeCount==closes+1)
assert(#nativeOverride.Triggers==0 and overrideRebuilds>0)
assert(indicator.EnhancedInputAction==originalIndicator and indicatorSets==6)
callbacks[2].callback({})
assert(#calls==2,'deactivated callback generation must not deliver')
print('PASS Enhanced Input host attach, replacement, and stale callback rejection')
local stopped,stopReason=host:stop()
assert(not stopped and tostring(stopReason):find('temporary removal failure',1,true))
assert(host.phase=='stopped' and #unhooked==2)
assert(host:stop() and #unhooked==3 and next(hookIds)==nil)
local secondHost=require('mc_input_host').new(function(callback)callback();return true end,
    function()end,service,environment)
assert(secondHost:stop() and #unhooked==6 and next(hookIds)==nil)
print('PASS named hook removal retries failures and releases each successful hook once')

local togglePath='/Game/_Dawnwalker/Player/Input/Actions/Combat/'
    ..'IA_Combat_ToggleQuickslots.IA_Combat_ToggleQuickslots'
local toggle=object('InputAction',togglePath)
toggle.Triggers={};toggle.bConsumeInput=false
resolved[togglePath]=toggle
native.Mappings={{Action=toggle,Key={KeyName='None'}}}
-- A Settings key profile whose one row maps the toggle to keyNames.
local function keyProfile(keyNames)
    local mappings={}
    for _,keyName in ipairs(keyNames) do
        mappings[#mappings+1]={AssociatedInputAction=toggle,CurrentKey={KeyName=keyName}}
    end
    return {valid=true,PlayerMappedKeys={{Mappings=mappings}}}
end
local runtimeKey='LeftAlt'
local queries=0
environment.profile=function(live)
    assert(live.subsystem==subsystem and live.component==component,
        'key query must use the player whose input component receives the bindings')
    queries=queries+1
    return keyProfile({runtimeKey,'Gamepad_FaceButton_Bottom'})
end
local queryHost=require('mc_input_host').new(function(callback)callback();return true end,
    function()end,service,environment)
-- Default's swap is an MCC toggle on the player's Toggle Quickslots key.
local swapToggle={id='default.swap.toggle',key=0,mode=3,phases={'Triggered'},consume=true,
    contexts={'exploration','combat'},standardAction='IA_Combat_ToggleQuickslots',action={type='flip'}}
assert(queryHost:apply({contexts={'exploration','combat'},bindings={swapToggle},overrides={}}),
    'Default must attach its toggle')
assert(queries>=1,'the toggle key must come from the player binding')
assert(#mccKeys()==1 and mccKeys()[1]==runtimeKey,'the toggle must be mapped on the keyboard key only')
assert(#toggle.Triggers==0,'Default must leave the native toggle triggers alone')
assert(queryHost:stop() and #mccKeys()==0,'stopping must unmap the toggle')
print('PASS Default maps its own toggle on the inherited key')

-- Inherited keys come from the Settings key profile, also when no applied
-- context maps the action, as for the combat toggle in open world.
local profileQueries=0
environment.profile=function(live)
    assert(live.subsystem==subsystem,'profile query must use the owning player')
    profileQueries=profileQueries+1
    return keyProfile({'LeftAlt','Gamepad_FaceButton_Bottom'})
end
local profileHost=require('mc_input_host').new(function(callback)callback();return true end,
    function()end,service,environment)
local inherited={id='grouped.GroupFocus2',key=0,mode=2,sustained=true,
    phases={'Started','Completed','Canceled'},action={type='focus',group=2},
    standardAction='IA_Combat_ToggleQuickslots'}
assert(profileHost:apply({contexts={'exploration'},bindings={inherited},overrides={}}),
    'an inherited key must attach from the key profile')
assert(profileQueries>=1 and #inherited.keyNames==1 and inherited.keyNames[1]=='LeftAlt','inherited key must come from the key profile')
assert(profileHost:stop())
environment.profile=nil
print('PASS inherited keys come from the Settings key profile')

-- A player key bound on the swap's inherited key takes it over: the swap steps
-- aside, and returns once that key moves elsewhere.
environment.profile=function() return keyProfile({'LeftAlt'}) end
local stepHost=require('mc_input_host').new(function(callback)callback();return true end,
    function()end,service,environment)
local swap={id='default.swap.toggle',key=0,swap=true,mode=3,phases={'Triggered'},consume=true,
    contexts={'exploration','combat'},standardAction='IA_Combat_ToggleQuickslots',action={type='flip'}}
local claimant={id='grouped.GroupFocus2',key=164,keyName='LeftAlt',mode=2,sustained=true,
    phases={'Started','Completed','Canceled'},action={type='focus',group=1},
    override='IA_Combat_ToggleQuickslots'}
local stepPlan={contexts={'exploration','combat'},bindings={swap,claimant},overrides={}}
assert(stepHost:apply(stepPlan))
local mapped={}
for _,entry in ipairs(native.Mappings) do
    if entry.Action.path:find('IA_MCC_',1,true) then mapped[#mapped+1]=entry.Action.path end
end
assert(#mapped==1 and mapped[1]:find('GroupFocus2',1,true),'only the player key may map on LeftAlt')
assert(swap.suppressed and swap.suppressed.LeftAlt=='grouped.GroupFocus2')
claimant.key,claimant.keyName=74,'J'
assert(stepHost:sync())
assert(swap.suppressed==nil and #mccKeys()==2,'the swap returns once its key is free')
assert(stepHost:stop() and #mccKeys()==0)
-- Every keyboard key in the profile is attached; a claimed one is left to its claimant.
environment.profile=function() return keyProfile({'LeftAlt','Gamepad_FaceButton_Bottom','Q'}) end
claimant.key,claimant.keyName=164,'LeftAlt'
swap.keyNames,swap.suppressed=nil,nil
local multiHost=require('mc_input_host').new(function(callback)callback();return true end,
    function()end,service,environment)
assert(multiHost:apply({contexts={'exploration','combat'},bindings={swap,claimant},overrides={}}))
assert(#swap.keyNames==2 and swap.keyNames[1]=='LeftAlt' and swap.keyNames[2]=='Q','every keyboard key is kept')
local keysBySource={}
for _,entry in ipairs(native.Mappings) do
    if entry.Action.path:find('IA_MCC_',1,true) then
        local source=entry.Action.path:find('swap',1,true) and 'swap' or 'claimant'
        keysBySource[source]=(keysBySource[source] or '')..entry.Key.KeyName..';'
    end
end
assert(keysBySource.swap=='Q;' and keysBySource.claimant=='LeftAlt;','the swap keeps Q and steps aside on LeftAlt')
assert(multiHost:stop() and #mccKeys()==0)
environment.profile=nil
print('PASS swap steps aside for a player key on its inherited key')

-- An inherited key that cannot be resolved skips only its own bindings: the rest
-- attach, a warning is written once, and the key attaches once the player binds it.
local profileNames={}
environment.profile=function() return keyProfile(profileNames) end
local warnings={}
local partialHost=require('mc_input_host').new(function(callback)callback();return true end,
    function(message) warnings[#warnings+1]=message end,service,environment)
local unboundSwap={id='default.swap.toggle',key=0,swap=true,mode=3,phases={'Triggered'},consume=true,
    contexts={'exploration','combat'},standardAction='IA_Combat_ToggleQuickslots',action={type='flip'}}
local slot={id='global.AbilitySlot1',key=74,keyName='J',mode=0,phases={'Triggered'},
    action={type='ability',slot=1}}
assert(partialHost:apply({contexts={'exploration','combat'},bindings={unboundSwap,slot},overrides={}}),
    'an unbound inherited key must not keep other bindings from attaching')
assert(#mccKeys()==1 and mccKeys()[1]=='J' and unboundSwap.keyNames==nil and unboundSwap.unresolved)
local function count(text)
    local found=0
    for _,message in ipairs(warnings) do if message:find(text,1,true) then found=found+1 end end
    return found
end
assert(count('inherited key unavailable')==1,'the skipped key is reported')
assert(partialHost:sync() and count('inherited key unavailable')==1,'and reported only once')
profileNames={'LeftAlt'}
assert(partialHost:sync())
assert(#mccKeys()==2 and unboundSwap.keyNames[1]=='LeftAlt' and not unboundSwap.unresolved,
    'the skipped binding attaches once its key resolves')
assert(count('inherited key resolved')==1)
-- An error while resolving the key is treated the same way, not as a failed sync.
local full=environment.full
environment.full=function(value)
    if value==toggle then error('action lookup exploded') end
    return full(value)
end
-- The game applying new keyboard mappings is when the keys are read again.
hooks['/Script/RebelInput.RebelInputMappingSubsystem:ApplyPendingKeyboardMappings']()
assert(partialHost:sync(),'a resolution error must not fail the sync')
assert(#mccKeys()==1 and mccKeys()[1]=='J' and unboundSwap.unresolved)
assert(count('key resolution failed')==1)
environment.full=full
assert(partialHost:stop() and #mccKeys()==0)
environment.profile=nil
print('PASS an unresolved inherited key skips only its own bindings')

-- Keys are read when they can have changed, not on every context change.
do
    local reads=0
    environment.profile=function() reads=reads+1;return keyProfile({'LeftAlt'}) end
    local readHost=require('mc_input_host').new(function(callback)callback();return true end,
        function() end,service,environment)
    local swap={id='default.swap.toggle',key=0,swap=true,mode=3,phases={'Triggered'},consume=true,
        contexts={'exploration','combat'},standardAction='IA_Combat_ToggleQuickslots',action={type='flip'}}
    assert(readHost:apply({contexts={'exploration','combat'},bindings={swap},overrides={}}))
    local attached=reads
    assert(attached>=1,'attaching reads the keys')
    hooks['/Script/Engine.PlayerController:ClientRestart']()
    assert(readHost:sync() and reads==attached,'possession and plain syncs read no keys')
    gameSetsUpInput()
    assert(reads==attached,'a gameplay context added while MCC owns the live player reads no keys')
    environment.profile=function() reads=reads+1;return keyProfile({'Q'}) end
    hooks['/Script/RebelInput.RebelInputMappingSubsystem:ApplyPendingKeyboardMappings']()
    assert(reads==attached+1 and swap.keyNames[1]=='Q','new keyboard mappings are read once')
    assert(readHost:apply({contexts={'exploration','combat'},bindings={swap},overrides={}}) and reads==attached+2,
        'an Apply reads them again')
    assert(readHost:stop())
    environment.profile=nil
end
print('PASS inherited keys are read only when they can have changed')

-- An inherited action no InputAction carries is scanned for again only after a while:
-- each scan reads every InputAction, and a sync follows every context change.
do
    local all,scans,now=environment.all,0,0
    environment.all=function(class)
        if class=='InputAction' then scans=scans+1 end
        return all(class)
    end
    environment.clock=function() return now end
    local missing={id='default.missing',key=0,mode=0,phases={'Triggered'},
        standardAction='IA_Nowhere',action={type='ability',slot=2}}
    local slot={id='global.AbilitySlot1',key=74,keyName='J',mode=0,phases={'Triggered'},
        action={type='ability',slot=1}}
    local scanning=require('mc_input_host').new(function(callback)callback();return true end,
        function() end,service,environment)
    assert(scanning:apply({contexts={'exploration','combat'},bindings={missing,slot},overrides={}}))
    local first=scans
    assert(first>0 and missing.unresolved)
    assert(scanning:sync() and scanning:sync() and scans==first,'a missing action is not scanned for on every sync')
    now=6
    assert(scanning:sync() and scans>first,'it is looked up again after the retry interval')
    assert(scanning:stop())
    environment.all,environment.clock=all,nil
end
print('PASS a missing inherited action is not rescanned on every sync')

-- An Apply on attached controls resolves its override targets once, not again in its sync.
do
    local all,scans=environment.all,0
    environment.all=function(class)
        if class=='InputAction' then scans=scans+1 end
        return all(class)
    end
    local slot={id='global.AbilitySlot1',key=74,keyName='J',mode=0,phases={'Triggered'},
        action={type='ability',slot=1}}
    local applying=require('mc_input_host').new(function(callback)callback();return true end,
        function() end,service,environment)
    local function applyPlan() return {contexts={'exploration','combat'},bindings={slot},overrides={IA_Test=true}} end
    assert(applying:apply(applyPlan()) and applying.ready)
    scans=0
    assert(applying:apply(applyPlan()))
    assert(scans==1,'one InputAction scan per Apply, got '..scans)
    assert(applying:stop())
    environment.all=all
end
print('PASS an Apply scans InputActions once')

-- An override name shared by several actions picks the game's own input action; when
-- that does not settle it, only that override is skipped and every key still attaches.
do
    local all,construct=environment.all,environment.constructOverride
    local gates={}
    environment.constructOverride=function(action,marker)
        local path=action.path..':'..marker
        gates[path]=gates[path] or object('InputTriggerChordAction',path)
        return gates[path]
    end
    local function action(path) local value=object('InputAction',path);value.Triggers={};return value end
    local game=action('/Game/_Dawnwalker/Player/Input/Actions/IA_Shared.IA_Shared')
    local copy=action('/Game/Other/IA_Shared.IA_Shared')
    local other=action('/Game/Elsewhere/IA_Shared.IA_Shared')
    local actions={}
    environment.all=function(class)
        if class=='InputAction' then return actions end
        return all(class)
    end
    local warnings={}
    local function count(text)
        local found=0
        for _,message in ipairs(warnings) do if message:find(text,1,true) then found=found+1 end end
        return found
    end
    local key={id='global.AbilitySlot1',key=74,keyName='J',mode=0,phases={'Triggered'},
        action={type='ability',slot=1}}
    local ambiguousPlan={contexts={'exploration','combat'},bindings={key},overrides={IA_Shared=true}}

    actions={copy,other}
    local ambiguousHost=require('mc_input_host').new(function(callback)callback();return true end,
        function(message) warnings[#warnings+1]=message end,service,environment)
    assert(ambiguousHost:apply(ambiguousPlan),'an ambiguous override must not keep input from attaching')
    assert(#mccKeys()==1 and mccKeys()[1]=='J')
    assert(#copy.Triggers==0 and #other.Triggers==0,'neither ambiguous action is overridden')
    assert(count('IA_Shared (ambiguous: 2 actions)')==1,'the skipped override is reported')
    assert(ambiguousHost:apply(ambiguousPlan) and count('IA_Shared (ambiguous')==1,'and reported only once')
    assert(ambiguousHost:stop() and #mccKeys()==0)

    actions={copy,game,other}
    local preferredHost=require('mc_input_host').new(function(callback)callback();return true end,
        function(message) warnings[#warnings+1]=message end,service,environment)
    assert(preferredHost:apply(ambiguousPlan))
    assert(#game.Triggers==1 and #copy.Triggers==0 and #other.Triggers==0,
        'the action in the game input folder is the one overridden')
    assert(preferredHost:stop() and #game.Triggers==0,'stopping restores it')
    environment.all,environment.constructOverride=all,construct
end
print('PASS an ambiguous override skips only itself, preferring the game input action')

-- A native override action lost while attached is resolved again: the rest of MCC
-- input stays attached and the replacement action takes the override.
do
    local all,construct=environment.all,environment.constructOverride
    local gates={}
    environment.constructOverride=function(action,marker)
        local path=action.path..':'..marker
        gates[path]=gates[path] or object('InputTriggerChordAction',path)
        return gates[path]
    end
    local function action(path) local value=object('InputAction',path);value.Triggers={};return value end
    local original=action('/Game/_Dawnwalker/Player/Input/Actions/IA_Lost.IA_Lost')
    local actions={original}
    environment.all=function(class)
        if class=='InputAction' then return actions end
        return all(class)
    end
    local key={id='global.AbilitySlot1',key=74,keyName='J',mode=0,phases={'Triggered'},
        action={type='ability',slot=1}}
    local lostHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,environment)
    assert(lostHost:apply({contexts={'exploration','combat'},bindings={key},overrides={IA_Lost=true}}))
    assert(#original.Triggers==1)
    local generation,closes=lostHost.generation,closeCount
    original.valid=false
    local replacement=action('/Game/_Dawnwalker/Player/Input/Actions/IA_Lost.IA_Lost')
    actions={replacement}
    assert(lostHost:sync(),'a lost override target must not fail the sync')
    assert(lostHost.ready and lostHost.generation==generation and closeCount==closes,
        'the rest of MCC input must stay attached')
    assert(#mccKeys()==1 and mccKeys()[1]=='J')
    assert(#replacement.Triggers==1,'the replacement action takes the override')
    assert(lostHost:stop() and #replacement.Triggers==0 and #mccKeys()==0)
    environment.all,environment.constructOverride=all,construct
end
print('PASS a lost override target is resolved again without retiring input')

-- An Apply that arrives while another operation runs is kept and applied once that
-- operation returns, rather than dropped.
do
    local rebuild=environment.rebuild
    local function plan(keyName)
        return {contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',key=1,keyName=keyName,
            mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={}}
    end
    local deferred={}
    local queuedHost
    local nested
    environment.rebuild=function()
        if nested then
            local later=nested;nested=nil
            local active,why=queuedHost:apply(later)
            assert(not active and why=='Apply queued','a busy host must queue the Apply')
        end
        return true
    end
    queuedHost=require('mc_input_host').new(function(callback)deferred[#deferred+1]=callback;return true end,
        function()end,service,environment)
    nested=plan('K')
    assert(queuedHost:apply(plan('J')))
    assert(#mccKeys()==1 and mccKeys()[1]=='J','the running Apply completes first')
    assert(#deferred>=1,'the queued Apply waits for the next game-thread turn')
    while #deferred>0 do table.remove(deferred,1)() end
    assert(#mccKeys()==1 and mccKeys()[1]=='K','the queued Apply is applied, not dropped')
    assert(queuedHost:stop() and #mccKeys()==0)
    environment.rebuild=rebuild
end
print('PASS an Apply during a running operation is queued, not dropped')

-- While enabled but not attached, retries back off and end; the next loading-screen
-- game input setup starts them again. One retry is scheduled at a time.
do
    local scheduled={}
    environment.delay=function(ms,callback) scheduled[#scheduled+1]={ms=ms,callback=callback};return true end
    input.AppliedInputContexts[native]=nil
    local retryHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,environment)
    local active,why=retryHost:apply({contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',key=74,
        keyName='J',mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={}})
    assert(not active and why=='native gameplay context unavailable')
    assert(#scheduled==1 and scheduled[1].ms==100)
    retryHost:sync()
    assert(#scheduled==1,'only one retry is scheduled at a time')
    local function run()
        local intervals={}
        while #scheduled>0 do
            local next=table.remove(scheduled,1)
            intervals[#intervals+1]=next.ms
            next.callback()
        end
        return table.concat(intervals,',')
    end
    local intervals=run()
    assert(intervals=='100,500,3000,6000,12000','retries end: '..intervals)
    assert(not retryHost.ready)
    gameSetsUpInput()
    intervals=run()
    assert(intervals=='100,500,3000,6000,12000','a game input setup starts them again: '..intervals)
    input.AppliedInputContexts[native]=5
    gameSetsUpInput()
    assert(retryHost.ready and #mccKeys()==1,'the game input setup attaches once gameplay is ready')
    assert(#scheduled==0,'no retry once attached')
    assert(retryHost:stop() and #mccKeys()==0)
    environment.delay=nil
end
print('PASS sync retries end and restart on each game input setup')

-- Without the input setup hook nothing else wakes input, so the retries continue.
do
    local scheduled={}
    environment.delay=function(ms,callback) scheduled[#scheduled+1]={ms=ms,callback=callback};return true end
    local hook=environment.hook
    environment.hook=function(name,callback)
        if name==SETUP then error('no UFunction found') end
        return hook(name,callback)
    end
    input.AppliedInputContexts[native]=nil
    local fallbackHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,environment)
    environment.hook=hook
    assert(not fallbackHost:apply({contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',key=74,
        keyName='J',mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={}}))
    local intervals={}
    for _=1,7 do
        local next=table.remove(scheduled,1)
        intervals[#intervals+1]=next.ms
        next.callback()
    end
    assert(table.concat(intervals,',')=='100,500,3000,6000,12000,12000,12000',
        'retries continue: '..table.concat(intervals,','))
    input.AppliedInputContexts[native]=5
    table.remove(scheduled,1).callback()
    assert(fallbackHost.ready and #scheduled==0)
    assert(fallbackHost:stop() and #mccKeys()==0)
    environment.delay=nil
end
print('PASS without the input setup hook, retries continue while not attached')

-- Rebuild requests come during play, as on every skill: while the kept player lives
-- and owns its input, a sync or a gameplay context added scans for no object. A
-- possession scans.
do
    local all,scans=environment.all,{}
    environment.all=function(class)
        scans[class]=(scans[class] or 0)+1
        return all(class)
    end
    environment.preHook=function(name,callback)
        nextHookId=nextHookId+2
        hooks[name]=callback;hookIds[name]={nextHookId-1,nextHookId}
        return nextHookId-1,nextHookId
    end
    local quietHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,environment)
    assert(quietHost:apply({contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',key=74,
        keyName='J',mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={}}))
    local function scanned()
        local total=0
        for _,class in ipairs({'BP_PlayerController_C','EnhancedInputLocalPlayerSubsystem','WBP_GameHUD_C'}) do
            total=total+(scans[class] or 0)
        end
        return total
    end
    scans={}
    local rebuild=hooks['/Script/EnhancedInput.EnhancedInputSubsystemInterface:RequestRebuildControlMappings']
    for _=1,3 do rebuild(subsystem) end
    assert(quietHost:sync())
    assert(scanned()==0,'a sync on the kept player scans for no object')
    gameSetsUpInput()
    assert(scanned()==0,'a gameplay context added for the kept player scans for no object')
    hooks['/Script/Engine.PlayerController:ClientRestart']()
    assert(scanned()>0,'a possession without a known local player scans for the player')
    assert(quietHost:stop())
    environment.all,environment.preHook=all,nil
end
print('PASS syncs on the kept player scan for no object')

-- The local player and its subsystem outlive a load: a new controller and pawn are
-- read from the kept player, with no scan. A dead local player scans again.
do
    local all,scans=environment.all,{}
    environment.all=function(class)
        scans[class]=(scans[class] or 0)+1
        return all(class)
    end
    local function scanned(class) return scans[class] or 0 end
    player.PlayerController=controller
    local loadingHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,environment)
    assert(loadingHost:apply({contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',key=74,
        keyName='J',mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={}}))
    assert(scanned('EnhancedInputLocalPlayerSubsystem')==1,'the first attach scans for the subsystem')
    -- A load: a new controller, pawn and component for the same local player.
    local nextComponent=object('EnhancedInputComponent','/Engine/Transient.Component_9')
    local nextPawn=object('Pawn','/Engine/Transient.Pawn_9');nextPawn.InputComponent=nextComponent
    local nextController=object('BP_PlayerController_C','/Engine/Transient.BP_PlayerController_C_9')
    nextController.PlayerInput,nextController.AcknowledgedPawn,nextController.Player=input,nextPawn,player
    player.PlayerController=nextController
    scans={}
    hooks['/Script/Engine.PlayerController:ClientRestart']()
    assert(scanned('BP_PlayerController_C')==0 and scanned('EnhancedInputLocalPlayerSubsystem')==0,
        'a load with the kept local player scans for neither controller nor subsystem')
    assert(loadingHost.componentPath=='/Engine/Transient.Component_9','the new component is attached')
    -- A controller the player no longer names is not taken.
    player.PlayerController=object('BP_PlayerController_C','/Engine/Transient.Other')
    player.PlayerController.Player=object('LocalPlayer','/Engine/Transient.LocalPlayer_1')
    player.valid=false
    scans={}
    hooks['/Script/Engine.PlayerController:ClientRestart']()
    assert(scanned('BP_PlayerController_C')>0,'a dead local player falls back to the scans')
    player.valid=true;player.PlayerController=nil
    assert(loadingHost:stop())
    environment.all=all
end
print('PASS a load reads the new controller from the kept local player')

-- A failed attach, as when the game sets up its input a moment before the new player
-- is complete, is retried like a pending one.
do
    local scheduled={}
    environment.delay=function(ms,callback) scheduled[#scheduled+1]={ms=ms,callback=callback};return true end
    local open=bridge.OpenInputComponent
    bridge.OpenInputComponent=function() return nil,'component not ready' end
    local failHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,environment)
    local active,why,detail=failHost:apply({contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',key=74,
        keyName='J',mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={}})
    assert(not active and detail.status=='failure','the attach fails: '..tostring(why))
    assert(#scheduled==1 and scheduled[1].ms==100,'a failed attach schedules a retry')
    bridge.OpenInputComponent=open
    table.remove(scheduled,1).callback()
    assert(failHost.ready and #mccKeys()==1,'the retry attaches once the player is ready')
    assert(#scheduled==0,'no retry once attached')
    assert(failHost:stop() and #mccKeys()==0)
    environment.delay=nil
end
print('PASS a failed attach is retried')

-- The wheel is presented once the player is found, before input attaches: a display
-- waiting for the focus event is not held up by the slower attach.
do
    local selected={}
    local early={select=function(_,group) selected[#selected+1]=group;return true end}
    local open=bridge.OpenInputComponent
    bridge.OpenInputComponent=function() return nil,'component not ready' end
    local earlyHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,early,environment)
    local active=earlyHost:apply({contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',key=74,
        keyName='J',mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={},defaultGroup=2})
    assert(not active,'the input attach fails')
    assert(selected[1]==2,'Default was presented before the attach was tried')
    bridge.OpenInputComponent=open
    assert(earlyHost:stop())
end
print('PASS the wheel is presented before input attaches')

-- After a load the player can be found before the game creates its HUD: only the
-- presentation is tried again, shortly after, until the wheel is shown.
do
    local scheduled,selected={},{}
    environment.delay=function(ms,callback) scheduled[#scheduled+1]={ms=ms,callback=callback};return true end
    local hudReady=false
    local late={select=function(_,group)
        if not hudReady then return false end
        selected[#selected+1]=group;return true
    end}
    local lateHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,late,environment)
    assert(lateHost:apply({contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',key=74,
        keyName='J',mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={},defaultGroup=2}))
    assert(#selected==0 and lateHost.state.pendingGroup==2,'no HUD yet: Default stays pending')
    assert(#scheduled==1 and scheduled[1].ms==100,'a presentation retry is scheduled')
    table.remove(scheduled,1).callback()
    assert(#selected==0 and #scheduled==1 and scheduled[1].ms==250,'still no HUD: tried again later')
    hudReady=true
    local lookups=0
    local hud=environment.hud
    environment.hud=function() lookups=lookups+1 end
    table.remove(scheduled,1).callback()
    environment.hud=hud
    assert(selected[1]==2 and lateHost.state.pendingGroup==nil,'the HUD appeared: Default is presented')
    assert(lookups>0,'and the new HUD\'s key indicators are refreshed')
    assert(#scheduled==0,'and the retries stop')
    assert(lateHost:stop())
    environment.delay=nil
end
print('PASS the wheel presentation is retried until the HUD exists')

-- A load that replaces the player while MCC is attached: the game input setup finds the new
-- input component and reattaches to it.
do
    local fadeHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,environment)
    assert(fadeHost:apply({contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',key=74,
        keyName='J',mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={}}))
    local generation,component=fadeHost.generation,fadeHost.componentPath
    local pawn=controller.AcknowledgedPawn
    local previous=pawn.InputComponent
    pawn.InputComponent=object('EnhancedInputComponent','/Engine/Transient.Pawn.ReplacementInput')
    gameSetsUpInput()
    assert(fadeHost.ready and fadeHost.generation>generation and fadeHost.componentPath~=component,
        'the game input setup reattaches to the replaced component')
    assert(#mccKeys()==1)
    pawn.InputComponent=previous
    assert(fadeHost:stop() and #mccKeys()==0)
end
print('PASS a game input setup reattaches to a replaced player')

-- An attach that left an inherited key unresolved keeps retrying until it resolves,
-- without waiting for a game hook.
do
    local scheduled={}
    environment.delay=function(ms,callback) scheduled[#scheduled+1]={ms=ms,callback=callback};return true end
    local names={}
    environment.profile=function() return keyProfile(names) end
    local swap={id='default.swap.toggle',key=0,swap=true,mode=3,phases={'Triggered'},consume=true,
        contexts={'exploration','combat'},standardAction='IA_Combat_ToggleQuickslots',action={type='flip'}}
    local incompleteHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,environment)
    assert(incompleteHost:apply({contexts={'exploration','combat'},bindings={swap},overrides={}}))
    assert(swap.unresolved and incompleteHost.incomplete)
    for _=1,4 do table.remove(scheduled,1).callback() end
    assert(#scheduled==1 and scheduled[1].ms==12000 and swap.unresolved)
    names={'LeftAlt'}
    table.remove(scheduled,1).callback()
    assert(not swap.unresolved and swap.keyNames[1]=='LeftAlt' and not incompleteHost.incomplete,
        'the retry binds the key once it resolves')
    assert(#scheduled==0,'and retries stop')
    assert(incompleteHost:stop())
    environment.profile,environment.delay=nil,nil
end
print('PASS an incomplete attach is retried until its keys resolve')

-- On the game thread a wheel change applies inside the input callback, so a native slot
-- action on the same key sees the new focus; other callbacks still wait for the queue.
do
    local pending,selected,activated={},{},{}
    local syncService={
        activate=function(_,kind,slot) activated[#activated+1]=kind..':'..slot;return true end,
        select=function(_,group) selected[#selected+1]=group;return true end,
    }
    local onThread=true
    environment.inGameThread=function() return onThread end
    local deferred=require('mc_input_host').new(function(callback) pending[#pending+1]=callback;return true end,
        function() end,syncService,environment)
    local first=#callbacks
    local focusKey={id='grouped.GroupFocus1',keyName='One',mode=3,phases={'Triggered'},direct=true,
        action={type='focus',group=2}}
    local slotKey={id='global.AbilitySlot1',keyName='J',mode=0,phases={'Triggered'},
        action={type='ability',slot=1}}
    assert(deferred:apply({contexts={'exploration','combat'},bindings={focusKey,slotKey},overrides={},
        defaultGroup=1}))
    local function fire(binding)
        for index=first+1,#callbacks do
            if callbacks[index].binding==binding.id then return callbacks[index].callback({}) end
        end
        error('no callback for '..binding.id)
    end
    -- BindAction order follows the plan: the focus key first, then the slot key.
    callbacks[first+1].binding,callbacks[first+2].binding=focusKey.id,slotKey.id
    local queued=#pending
    fire(focusKey)
    assert(selected[#selected]==2 and #pending==queued,'focus applies inside the input callback')
    fire(slotKey)
    assert(#activated==0 and #pending==queued+1,'slot activation still waits for the queue')
    pending[#pending]()
    assert(activated[1]=='ability:1')
    -- Off the game thread a focus change is queued like any other callback.
    onThread=false
    local before=#selected
    fire(focusKey)
    assert(#selected==before and #pending==queued+2,'off-thread focus is queued')
    environment.inGameThread=nil
    assert(deferred:stop())
end
print('PASS wheel changes apply within the input frame on the game thread')

-- MCC never hooks widget construction; indicators are updated after a control
-- mapping rebuild instead, on the game-thread turn after the pre-rebuild sync.
do
    for name in pairs(hooks) do assert(not name:find('AddChild',1,true),'MCC must not hook AddChild') end
    local pending={}
    environment.preHook=function(name,callback)
        nextHookId=nextHookId+2
        hooks[name]=callback;hookIds[name]={nextHookId-1,nextHookId}
        return nextHookId-1,nextHookId
    end
    local rebuildHost=require('mc_input_host').new(function(callback) pending[#pending+1]=callback;return true end,
        function() end,service,environment)
    assert(rebuildHost:apply(plan))
    local mccAction=retained['InputAction:IA_MCC_global_slot1']
    assert(indicator.EnhancedInputAction==mccAction)
    local before=#pending
    local rebuild=hooks['/Script/EnhancedInput.EnhancedInputSubsystemInterface:RequestRebuildControlMappings']
    rebuild(subsystem)
    rebuild(subsystem)
    assert(#pending==before+1,'one indicator update is queued per pending rebuild')
    -- The rebuild resets the indicator before the queued update runs.
    indicator.EnhancedInputAction=originalIndicator
    pending[#pending]()
    assert(indicator.EnhancedInputAction==mccAction,'the queued update restores the MCC indicator')
    rebuild(subsystem)
    assert(#pending==before+2,'a later rebuild queues another update')
    pending[#pending]()
    -- A gameplay context added for the kept player is checked after the call and
    -- changes nothing: no sync and no indicator update.
    gameSetsUpInput()
    assert(#pending==before+3,'the input setup check runs after the hooked call')
    pending[#pending]()
    assert(#pending==before+3,'a context added for the kept player wakes no sync')
    rebuild(subsystem)
    assert(#pending==before+4)
    environment.preHook=nil
    assert(rebuildHost:stop() and indicator.EnhancedInputAction~=mccAction)
    pending[#pending]()
    assert(indicator.EnhancedInputAction~=mccAction,'a stopped host must not reapply indicators')
end
print('PASS indicators update after a control mapping rebuild, without widget hooks')

-- UE4SS returns a new wrapper for every lookup, including a weak handle's get;
-- the same player stack must not read as a new owner and retire MCC's input.
do
    local lifetimes=UE4SSLuaEventBridge.lifetimes
    local weak=lifetimes.weak
    lifetimes.weak=function(object)
        local handle,why=weak(object)
        if not handle then return nil,why end
        local get=handle.get
        return {get=function()
            local live=get(handle)
            return live and setmetatable({},{__index=live}) or nil
        end,release=function() handle:release() end}
    end
    local freshHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,environment)
    assert(freshHost:apply(plan))
    local closes,installed=closeCount,#callbacks
    assert(freshHost:sync())
    assert(freshHost:sync())
    assert(closeCount==closes and #callbacks==installed,'a fresh wrapper of the same owner must not reattach')
    assert(freshHost:stop())
    lifetimes.weak=weak
end
print('PASS a fresh wrapper of the same player stack keeps MCC attached')

-- Hold keys get an underline mark, placed again after a ModCore Templates layout
-- pass and removed when controls are disabled.
do
    local overlay={children={}}
    indicator.parent=overlay
    indicator.Slot={};indicator.placement={x=10}
    local layout,created,placed,removed=nil,0,0,0
    local env=setmetatable({
        holdMark={
            parent=function(widget) return widget.parent end,
            find=function(parent,name)
                for _,child in ipairs(parent.children) do if child.name==name and child.valid then return child end end
            end,
            create=function(parent,name)
                created=created+1
                local mark=object('SizeBox','/Engine/Transient.'..name);mark.name=name
                parent.children[#parent.children+1]=mark
                return mark
            end,
            placement=function(key) return {x=key.placement.x} end,
            apply=function(mark,p) placed=placed+1;mark.x=p.x end,
            remove=function(mark) removed=removed+1;mark.valid=false end,
        },
        subscribeLayout=function(callback) layout=callback;return function() layout=nil end end,
    },{__index=environment})
    local markHost=require('mc_input_host').new(function(callback)callback();return true end,
        function()end,service,env)
    assert(layout,'the host listens for layout passes')
    local holdPlan={contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',keyName='One',mode=1,
        phases={'Triggered'},action={type='ability',slot=1}}},overrides={}}
    assert(markHost:apply(holdPlan))
    local mark=overlay.children[1]
    assert(created==1 and mark and mark.name=='MCC_HoldMark_ability_Left' and mark.x==10,
        'a Hold key is marked where its key is')
    indicator.placement.x=20
    layout({name='templates.layout.changed',category='player.quickslots'})
    assert(mark.x==20,'a layout pass places the mark again')
    local before=placed
    layout({name='templates.layout.changed',category='other.category'})
    assert(placed==before,'other categories are ignored')
    assert(markHost:deactivate())
    assert(not mark.valid and removed==1,'disabling controls removes the mark')
    assert(markHost:stop() and layout==nil,'stopping ends the layout subscription')
    indicator.parent,indicator.Slot,indicator.placement=nil,nil,nil
end
print('PASS Hold keys are underlined and follow layout passes')

-- A Hold key's rim fills from press to the Hold threshold and empties on release;
-- the rim phases are not delivered as input.
do
    local rims,activated={},{}
    local rimService={activate=function(_,kind,slot) activated[#activated+1]=kind..':'..slot;return true end,
        select=function() return true end}
    environment.inGameThread=function() return true end
    environment.setIndicatorProgress=function(widget,value) rims[#rims+1]={widget=widget,value=value} end
    local rimHost=require('mc_input_host').new(function(callback) callback();return true end,
        function() end,rimService,environment)
    local first=#callbacks
    local holdKey={id='global.AbilitySlot1',keyName='One',mode=1,phases={'Triggered'},sharesTap=true,
        progressPhases={'Started','Ongoing','Triggered','Completed','Canceled'},action={type='ability',slot=1}}
    assert(rimHost:apply({contexts={'exploration','combat'},bindings={holdKey},overrides={},holdLow=.1,holdHigh=.4}))
    local function fire(phase,elapsed)
        for index=first+1,#callbacks do
            if callbacks[index].phase==phase then return callbacks[index].callback({elapsed_processed=elapsed}) end
        end
        error('no callback for '..phase)
    end
    fire('Started',0)
    fire('Ongoing',.05)
    fire('Ongoing',.175)
    fire('Ongoing',.25)
    assert(#activated==0,'rim phases are not input')
    local function near(a,b) return math.abs(a-b)<1e-9 end
    assert(rims[1].widget==indicator and rims[1].value==0 and near(rims[2].value,.25) and near(rims[3].value,.5),
        'sharing its key with a Tap, the rim stays empty until low, then fills toward high')
    fire('Ongoing',.9)
    assert(rims[4].value==1,'the rim never overfills')
    fire('Triggered',.4)
    assert(activated[1]=='ability:1' and rims[5].value==0,'the action fires and the rim empties')
    fire('Canceled',.1)
    assert(#rims==5 and #activated==1,'an empty rim is not emptied again')
    assert(rimHost:stop())
    environment.setIndicatorProgress=nil
end
print('PASS a Hold key fills its rim until the threshold')

-- A Hold key alone fills its rim from press to the high mark.
do
    local rims={}
    environment.inGameThread=function() return true end
    environment.setIndicatorProgress=function(widget,value) rims[#rims+1]=value end
    local loneHost=require('mc_input_host').new(function(callback) callback();return true end,
        function() end,service,environment)
    local first=#callbacks
    local key={id='global.AbilitySlot1',keyName='One',mode=1,phases={'Triggered'},
        progressPhases={'Started','Ongoing','Triggered','Completed','Canceled'},action={type='ability',slot=1}}
    assert(loneHost:apply({contexts={'exploration','combat'},bindings={key},overrides={},holdLow=.1,holdHigh=.4}))
    local byPhase={}
    for index=first+1,#callbacks do byPhase[callbacks[index].phase]=callbacks[index].callback end
    byPhase.Started({elapsed_processed=0})
    byPhase.Ongoing({elapsed_processed=.05})
    assert(math.abs(rims[2]-.125)<1e-9,'it fills from press, before low: '..tostring(rims[2]))
    assert(loneHost:stop())
    environment.setIndicatorProgress=nil
end
print('PASS a lone Hold key fills from press')

-- A Tap key's rim is shown, full while pressed, and empties when it fires, is
-- released, or is held past the threshold.
do
    local rims,displays,activated={},{},{}
    local rimService={activate=function(_,kind,slot) activated[#activated+1]=kind..':'..slot;return true end,
        select=function() return true end}
    environment.inGameThread=function() return true end
    environment.setIndicatorProgress=function(widget,value) rims[#rims+1]=value end
    environment.setIndicatorHoldDisplay=function(widget,on) displays[#displays+1]=on end
    local tapHost=require('mc_input_host').new(function(callback) callback();return true end,
        function() end,rimService,environment)
    local first=#callbacks
    local tapKey={id='global.AbilitySlot1',keyName='One',mode=0,phases={'Triggered'},
        progressPhases={'Started','Ongoing','Triggered','Completed','Canceled'},action={type='ability',slot=1}}
    assert(tapHost:apply({contexts={'exploration','combat'},bindings={tapKey},overrides={},holdLow=.1,holdHigh=.4}))
    assert(displays[#displays]==true,'a Tap key shows its rim')
    local function fire(phase,elapsed)
        for index=first+1,#callbacks do
            if callbacks[index].phase==phase then return callbacks[index].callback({elapsed_processed=elapsed}) end
        end
        error('no callback for '..phase)
    end
    fire('Started',0)
    fire('Ongoing',.05)
    fire('Ongoing',.08)
    assert(#rims==1 and rims[1]==1,'full on press, set once while held before low')
    fire('Triggered',.08)
    assert(rims[2]==0 and activated[1]=='ability:1','it empties when the tap fires')
    fire('Started',0)
    fire('Ongoing',.15)
    assert(#rims==3 and rims[3]==1,'past the low mark it stays lit beside the filling Hold')
    fire('Ongoing',.45)
    assert(rims[4]==0 and #activated==1,'at the high mark the Hold fires and the Tap goes dark')
    fire('Canceled',.6)
    assert(#rims==4)
    -- With Show key outline set to Hold, a Tap key no longer shows a rim.
    assert(tapHost:apply({contexts={'exploration','combat'},bindings={{id='global.AbilitySlot1',keyName='One',
        mode=0,phases={'Triggered'},action={type='ability',slot=1}}},overrides={},holdLow=.1,holdHigh=.4,keyOutline=1}))
    assert(displays[#displays]==false,'the Tap rim is turned off')
    assert(tapHost:deactivate())
    assert(tapHost:stop())
    environment.setIndicatorProgress,environment.setIndicatorHoldDisplay=nil,nil
end
print('PASS a Tap key shows a full rim while pressed')

-- Rebuilt triggers replace the player's copies: its action instances are removed.
do
    local forgotten={}
    environment.forgetInstance=function(playerInput,action) forgotten[#forgotten+1]=action;return true end
    local instanceHost=require('mc_input_host').new(function(callback) callback();return true end,
        function() end,service,environment)
    local key={id='global.AbilitySlot1',keyName='One',mode=1,phases={'Triggered'},action={type='ability',slot=1}}
    assert(instanceHost:apply({contexts={'exploration','combat'},bindings={key},overrides={},holdLow=.1,holdHigh=.25}))
    local first=#forgotten
    assert(first==1,'a new trigger forgets the old instance')
    assert(instanceHost:apply({contexts={'exploration','combat'},bindings={key},overrides={},holdLow=.1,holdHigh=1}))
    assert(#forgotten==2,'a new threshold forgets it again')
    assert(instanceHost:sync() and #forgotten==2,'an unchanged plan keeps the instance')
    assert(instanceHost:stop())
    environment.forgetInstance=nil
end
print('PASS rebuilt triggers refresh the player action instances')

-- A key acting on press shows a full rim while it is down.
do
    local rims={}
    environment.inGameThread=function() return true end
    environment.setIndicatorProgress=function(widget,value) rims[#rims+1]=value end
    local pressHost=require('mc_input_host').new(function(callback) callback();return true end,
        function() end,service,environment)
    local first=#callbacks
    local key={id='global.AbilitySlot1',keyName='One',mode=3,phases={'Triggered'},
        progressPhases={'Started','Ongoing','Triggered','Completed','Canceled'},action={type='ability',slot=1}}
    assert(pressHost:apply({contexts={'exploration','combat'},bindings={key},overrides={},holdLow=.1,holdHigh=.4}))
    local byPhase={}
    for index=first+1,#callbacks do byPhase[callbacks[index].phase]=callbacks[index].callback end
    byPhase.Started({elapsed_processed=0})
    byPhase.Triggered({elapsed_processed=0})
    byPhase.Ongoing({elapsed_processed=2})
    assert(#rims==1 and rims[1]==1,'full on press, and it stays full while held')
    byPhase.Completed({elapsed_processed=2.1})
    assert(rims[2]==0,'it empties on release')
    -- A quick press stays full until the low mark has passed.
    local timers={}
    local delay=environment.delay
    environment.delay=function(ms,callback) timers[#timers+1]={ms=ms,run=callback};return true end
    byPhase.Started({elapsed_processed=0})
    byPhase.Completed({elapsed_processed=.04})
    assert(#rims==3 and rims[3]==1 and timers[1].ms==60,'still full after a quick release')
    timers[1].run()
    assert(rims[4]==0,'empty once the low mark has passed')
    -- A newer press is not emptied by the older press's timer.
    byPhase.Started({elapsed_processed=0})
    byPhase.Completed({elapsed_processed=.04})
    byPhase.Started({elapsed_processed=0})
    timers[2].run()
    assert(#rims==6 and rims[6]==1,'the second press keeps its rim')
    environment.delay=delay
    assert(pressHost:stop())
    environment.setIndicatorProgress=nil
end
print('PASS a key acting on press is full while down')

-- The flash lasts until the low mark, however long the window.
do
    local timers={}
    local delay=environment.delay
    environment.inGameThread=function() return true end
    environment.setIndicatorProgress=function() end
    environment.delay=function(ms,callback) timers[#timers+1]=ms;return true end
    local capHost=require('mc_input_host').new(function(callback) callback();return true end,
        function() end,service,environment)
    local first=#callbacks
    local key={id='global.AbilitySlot1',keyName='One',mode=3,phases={'Triggered'},
        progressPhases={'Started','Triggered','Completed','Canceled'},action={type='ability',slot=1}}
    assert(capHost:apply({contexts={'exploration','combat'},bindings={key},overrides={},holdLow=.5,holdHigh=2}))
    local byPhase={}
    for index=first+1,#callbacks do byPhase[callbacks[index].phase]=callbacks[index].callback end
    byPhase.Started({elapsed_processed=0})
    byPhase.Completed({elapsed_processed=.2})
    assert(timers[1]==300,'flash until low: '..tostring(timers[1]))
    assert(capHost:stop())
    environment.delay,environment.setIndicatorProgress=delay,nil
end
print('PASS the rim flash lasts until the low mark')

-- A Groups key fills only the focused wheel's hint, the one focused at press.
do
    local rims={}
    environment.inGameThread=function() return true end
    environment.setIndicatorProgress=function(widget,value) rims[#rims+1]={widget=widget,value=value} end
    local groupHost=require('mc_input_host').new(function(callback) callback();return true end,
        function() end,service,environment)
    local function run(defaultGroup)
        local first=#callbacks
        local key={id='grouped.QuickSlot1',keyName='One',mode=1,phases={'Started','Triggered','Completed','Canceled'},
            progressPhases={'Started','Ongoing','Triggered','Completed','Canceled'},action={type='selected',slot=1}}
        assert(groupHost:apply({contexts={'exploration','combat'},bindings={key},overrides={},
            defaultGroup=defaultGroup,holdLow=.1,holdHigh=.4}))
        local byPhase={}
        for index=first+1,#callbacks do byPhase[callbacks[index].phase]=callbacks[index].callback end
        byPhase.Started({elapsed_processed=0})
        byPhase.Ongoing({elapsed_processed=.25})
    end
    run(2)
    assert(#rims==0,'the abilities hint stays empty while consumables have focus')
    run(1)
    assert(#rims==2 and rims[1].widget==indicator and math.abs(rims[2].value-.625)<1e-9,'the focused wheel fills')
    assert(groupHost:stop())
    environment.setIndicatorProgress=nil
end
print('PASS a Groups key fills only the focused wheel')

