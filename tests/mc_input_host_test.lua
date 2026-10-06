package.path='Scripts/?.lua;'..package.path
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
function bridge.GetCapabilities()return {api=5,enhanced_input=true,explicit_target=true}end
function bridge.OpenInputComponent(path)return path end
function bridge.BindAction(_,_,phase,callback)callbacks[#callbacks+1]={phase=phase,callback=callback};return #callbacks end
function bridge.CloseInputComponent()closeCount=closeCount+1;return true end
local hooks={}
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
input.AppliedInputContexts[native]=nil
hooks['/Script/EnhancedInput.EnhancedInputSubsystemInterface:RemoveMappingContext']()
assert(not host.ready and closeCount==3,'native context detach must retire MCC input')
assert(#mccKeys()==0,'native context detach must unmap MCC keys')
assert(#nativeOverride.Triggers==0,'native context detach must remove the override chord')
assert(indicator.EnhancedInputAction==originalIndicator and indicatorSets==6,
    'native context detach must restore the original indicator action')
input.AppliedInputContexts[native]=5
hooks['/Script/EnhancedInput.EnhancedInputSubsystemInterface:AddMappingContext']()
assert(host.ready and indicatorSets==7,'native context reattach must restore MCC indicators')
assert(nativeOverride.Triggers[1]==overrideGate,'reattach must reuse the root-captured chord')
rejectOverrideRebuild=true
local removed=host:deactivate()
assert(not removed and host.ready and nativeOverride.Triggers[1]==overrideGate,
    'failed override restoration must leave active replacement input intact')
rejectOverrideRebuild=false
assert(host:deactivate() and closeCount==4)
assert(#nativeOverride.Triggers==0 and overrideRebuilds>0)
assert(indicator.EnhancedInputAction==originalIndicator and indicatorSets==8)
callbacks[2].callback({})
assert(#calls==2,'deactivated callback generation must not deliver')
print('PASS Enhanced Input host attach, replacement, and stale callback rejection')
local stopped,stopReason=host:stop()
assert(not stopped and tostring(stopReason):find('temporary removal failure',1,true))
assert(host.phase=='stopped' and #unhooked==6)
assert(host:stop() and #unhooked==7 and next(hookIds)==nil)
local secondHost=require('mc_input_host').new(function(callback)callback();return true end,
    function()end,service,environment)
assert(secondHost:stop() and #unhooked==14 and next(hookIds)==nil)
print('PASS named hook removal retries failures and releases each successful hook once')

local togglePath='/Game/_Dawnwalker/Player/Input/Actions/Combat/'
    ..'IA_Combat_ToggleQuickslots.IA_Combat_ToggleQuickslots'
local toggle=object('InputAction',togglePath)
toggle.Triggers={};toggle.bConsumeInput=false
resolved[togglePath]=toggle
native.Mappings={{Action=toggle,Key={KeyName='None'}}}
local runtimeKey='LeftAlt'
local queries=0
environment.profileKeys=function(live,action)
    assert(live.subsystem==subsystem and live.component==component,
        'key query must use the player whose input component receives the bindings')
    assert(action==toggle,'query must receive the exact action used by the mappings')
    queries=queries+1
    return {{KeyName=runtimeKey},{KeyName='Gamepad_FaceButton_Bottom'}}
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
environment.profileKeys=function(live,action)
    assert(live.subsystem==subsystem and action==toggle,'profile query must use the owning player and action')
    profileQueries=profileQueries+1
    return {{KeyName='LeftAlt'},{KeyName='Gamepad_FaceButton_Bottom'}}
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
environment.profileKeys=nil
print('PASS inherited keys come from the Settings key profile')

-- A player key bound on the swap's inherited key takes it over: the swap steps
-- aside, and returns once that key moves elsewhere.
environment.profileKeys=function() return {{KeyName='LeftAlt'}} end
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
environment.profileKeys=function() return {{KeyName='LeftAlt'},{KeyName='Gamepad_FaceButton_Bottom'},{KeyName='Q'}} end
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
environment.profileKeys=nil
print('PASS swap steps aside for a player key on its inherited key')

-- An inherited key that cannot be resolved skips only its own bindings: the rest
-- attach, a warning is written once, and the key attaches once the player binds it.
local profile={}
environment.profileKeys=function() return profile end
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
profile={{KeyName='LeftAlt'}}
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
assert(partialHost:sync(),'a resolution error must not fail the sync')
assert(#mccKeys()==1 and mccKeys()[1]=='J' and unboundSwap.unresolved)
assert(count('key resolution failed')==1)
environment.full=full
assert(partialHost:stop() and #mccKeys()==0)
environment.profileKeys=nil
print('PASS an unresolved inherited key skips only its own bindings')

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

-- While enabled but not attached, retries continue at a steady interval rather than
-- stopping after two, one at a time, and end once input attaches.
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
    local intervals={}
    for _=1,4 do
        local next=table.remove(scheduled,1)
        intervals[#intervals+1]=next.ms
        next.callback()
    end
    assert(table.concat(intervals,',')=='100,500,3000,3000','retries continue: '..table.concat(intervals,','))
    assert(#scheduled==1 and not retryHost.ready)
    input.AppliedInputContexts[native]=5
    table.remove(scheduled,1).callback()
    assert(retryHost.ready and #mccKeys()==1,'the retry attaches once gameplay is ready')
    assert(#scheduled==0,'no retry once attached')
    assert(retryHost:stop() and #mccKeys()==0)
    environment.delay=nil
end
print('PASS sync retries continue while not attached')

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
    -- A newly constructed Bindings widget gets its indicators on the next turn.
    local bindingsClass='/Game/_Dawnwalker/UI/_Unified/HUD/Quickslots/WBP_HUD_Quickslots_Bindings.'
        ..'WBP_HUD_Quickslots_Bindings_C'
    assert(hooks[bindingsClass],'Bindings construction must be observed')
    indicator.EnhancedInputAction=originalIndicator
    hooks[bindingsClass]({})
    hooks[bindingsClass]({})
    assert(#pending==before+3,'Bindings constructed in one turn share one update')
    assert(indicator.EnhancedInputAction==originalIndicator,'the update waits for construction to return')
    pending[#pending]()
    assert(indicator.EnhancedInputAction==mccAction,'the queued update assigns the new indicators')
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
