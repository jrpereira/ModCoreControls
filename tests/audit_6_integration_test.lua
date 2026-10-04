-- Black-box lifecycle regressions. Run with AUDIT6_BASELINE=1 to report
-- the audited failures without making the whole command fail.
package.path='tests/?.lua;Scripts/?.lua;' .. package.path
local Fixture=require('audit_6_fixture')
local baseline=os.getenv('AUDIT6_BASELINE')=='1'
local failures=0
local function case(name,run)
    local ok,why=pcall(run)
    if ok then print('PASS ' .. name)
    else failures=failures+1;print('FAIL ' .. name .. ': ' .. tostring(why)) end
end
local function check(value,message) assert(value,message) end
local function activations(f)
    local count=0
    for _,item in ipairs(f.calls) do if item:match('^ability:') or item:match('^consumable:') then count=count+1 end end
    return count
end

case('F01 coupled mapping hook, immediate queue',function()
    local f=Fixture.new({mappingLimit=12,coupledHooks=true})
    local ok=f.host:apply(f:plan())
    check(ok,'attachment failed')
    check(f.counts.adds==0,'MCC must not add a mapping context; added ' .. f.counts.adds)
    check(#f:mcc()==1,'MCC key was not mapped into the game context')
    check(f.counts.queues==0,'self-generated mapping queued a sync')
    check(f.host:deactivate(),'deactivation failed')
    check(f.counts.removes==0 and #f:mcc()==0,'deactivation must only unmap MCC keys')
    check(f.native.Mappings[1]==f.swapMapping,'deactivation removed a native mapping')
end)

case('F01 coupled mapping hook, deferred queue',function()
    local f=Fixture.new({deferred=true,coupledHooks=true})
    check(f.host:apply(f:plan()),'attachment failed')
    check(f:drain()==0,'self-generated mapping queued a redundant pass')
    check(f.counts.adds==0 and #f:mcc()==1,'unexpected mapping additions')
    f.native.valid=false
    f:emit('/Script/EnhancedInput.EnhancedInputSubsystemInterface:RemoveMappingContext',f.subsystem,f.native)
    check(f:drain()<=1,'external mapping removal was not coalesced')
end)

case('rebuild pre-hook updates inherited mappings inline without another rebuild',function()
    local f=Fixture.new({deferred=true,coupledRebuild=true})
    local binding={id='inherited',mode=0,phases={'Triggered'},
        standardAction='IA_Combat_ToggleQuickslots',action={type='focus',group=2}}
    check(f.host:apply(f:plan({bindings={binding},overrides={}})),'attachment failed')
    f.swapMapping.Key.KeyName='Z'
    local rebuilds=f.counts.rebuilds or 0
    f:emit('/Script/EnhancedInput.EnhancedInputSubsystemInterface:RequestRebuildControlMappings',f.subsystem)
    check(#f:mcc()==1 and f:mcc()[1].Key.KeyName=='Z','mapping was not ready before request returned')
    check(#f.pending==0,'pre-hook queued work instead of preparing inline')
    check((f.counts.rebuilds or 0)==rebuilds,'pre-hook recursively requested another rebuild')
    local entry=f:mcc()[1]
    f.native:UnmapKey(entry.Action,entry.Key)
    f:emit('/Script/EnhancedInput.EnhancedInputSubsystemInterface:RequestRebuildControlMappings',f.subsystem)
    check(#f:mcc()==1 and f:mcc()[1].Key.KeyName=='Z','unchanged key did not repair missing mappings')
    check(f.host:stop(),'pre-hook cleanup failed')
    check(f.hooks['/Script/EnhancedInput.EnhancedInputSubsystemInterface:RequestRebuildControlMappings']==nil,
        'stop retained rebuild pre-hook')
end)

case('rebuild pre-hook ignores foreign players and nested attachment requests',function()
    local f=Fixture.new({deferred=true,coupledRebuild=true})
    check(f.host:apply(f:plan()),'nested rebuild prevented attachment')
    check(#f:mcc()==1 and #f.pending==0,'nested rebuild scheduled redundant attachment')
    local entry=f:mcc()[1]
    f.native:UnmapKey(entry.Action,entry.Key)
    local foreign=f.makeObject('EnhancedInputLocalPlayerSubsystem','/Engine/Transient.OtherSubsystem')
    f:emit('/Script/EnhancedInput.EnhancedInputSubsystemInterface:RequestRebuildControlMappings',foreign)
    check(#f:mcc()==0,'foreign player request changed MCC mappings')
    check(#f.pending==0,'foreign request scheduled MCC work')
end)

case('F02 unavailable override does not block input attachment',function()
    local f=Fixture.new()
    local ran,active=pcall(function() return f.host:apply(f:plan({overrides={IA_Missing=true}})) end)
    check(ran and active and f.host.ready,'missing override blocked attachment')
    check(f.logs and table.concat(f.logs,' '):find('IA_Missing',1,true),
        'missing override was not identified in the log')
    assert(f:lastCallback('Triggered'))({})
    check(activations(f)==1,'available binding did not deliver')
end)

case('late override is gated when gameplay context changes',function()
    local f=Fixture.new()
    check(f.host:apply(f:plan({overrides={IA_Missing=true}})),
        'missing override blocked initial attachment')
    local loaded=f.makeObject('InputAction','/Game/Input.IA_Missing')
    loaded.Triggers={}
    f.nativeActions[#f.nativeActions+1]=loaded
    f.input.AppliedInputContexts[f.native]=50
    check(f.host:sync(),'context transition failed')
    check(#loaded.Triggers==1,'newly available override was not gated')
end)

case('missing combat toggle does not block group binding',function()
    local f=Fixture.new()
    local focus={id='group.focus',keyName='LeftAlt',mode=2,
        phases={'Started','Completed','Canceled'},action={type='focus',group=2}}
    local plan=f:plan({bindings={focus},overrides={IA_Test=true,
        IA_Combat_ToggleQuickslots=true}})
    check(f.host:apply(plan),'combat toggle blocked attachment')
    check(f.host.ready,'input host did not become ready')
    assert(f:lastCallback('Started'))({})
    check(f.host.state.selectedGroup==2,'group focus key did not select group 2')
end)

case('Hold Swap maps into the game context and restores prior focus',function()
    local f=Fixture.new()
    local press={id='holdSwap.press',keyName='LeftAlt',mode=3,phases={'Triggered'},
        consume=true,layer='global',holdSwapEdge='press',action={type='focus',group=2}}
    local release={id='holdSwap.release',keyName='LeftAlt',mode=4,phases={'Triggered'},
        consume=true,layer='global',holdSwapEdge='release',action={type='focus',group=2}}
    local plan=f:plan({bindings={press,release},defaultGroup=1,holdSwap={enabled=true,defaultGroup=1,
        sourceAction='IA_Combat_ToggleQuickslots'},overrides={}})
    check(f.host:apply(plan),'Hold Swap attachment failed')
    check(f.counts.adds==0 and #f:mcc()==2,'Hold Swap must map its edges into the game context')
    f.callbacks[1].callback({})
    f.callbacks[2].callback({})
    check(f.calls[#f.calls-1]=='select:2' and f.calls[#f.calls]=='select:1',
        'Hold Swap did not focus secondary then restore prior group')
end)

case('Hold Swap follows the standard Toggle Quickslot binding',function()
    local f=Fixture.new()
    local press={id='holdSwap.press',mode=3,phases={'Triggered'},consume=true,
        layer='global',holdSwapEdge='press',action={type='focus',group=2}}
    local release={id='holdSwap.release',mode=4,phases={'Triggered'},consume=true,
        layer='global',holdSwapEdge='release',action={type='focus',group=2}}
    local plan=f:plan({bindings={press,release},holdSwap={enabled=true,defaultGroup=1,
        sourceAction='IA_Combat_ToggleQuickslots'},overrides={IA_Combat_ToggleQuickslots=true}})
    check(f.host:apply(plan),'Hold Swap attachment failed')
    local entries=f:mcc()
    check(#entries==2 and entries[1].Key.KeyName=='LeftAlt'
        and entries[2].Key.KeyName=='LeftAlt','standard binding was not inherited')
    f.swapMapping.Key.KeyName='Z'
    f:emit('/Script/RebelInput.RebelInputMappingSubsystem:ApplyPendingKeyboardMappings')
    entries=f:mcc()
    check(#entries==2 and entries[1].Key.KeyName=='Z' and entries[2].Key.KeyName=='Z',
        'changed standard binding was not applied dynamically')
end)

case('optional inherited key follows its standard control',function()
    local f=Fixture.new()
    local preview={id='global.preview',key=0,mode=2,
        phases={'Started','Completed','Canceled'},standardAction='IA_Combat_ToggleQuickslots',
        action={type='focus',group=2}}
    check(f.host:apply(f:plan({bindings={preview},overrides={}})),
        'inherited optional binding did not attach')
    check(f:mcc()[1].Key.KeyName=='LeftAlt','standard key was not inherited')
    f.swapMapping.Key.KeyName='Z'
    f:emit('/Script/RebelInput.RebelInputMappingSubsystem:ApplyPendingKeyboardMappings')
    check(f:mcc()[1].Key.KeyName=='Z','inherited key did not follow rebinding')
    f.swapMapping.Key.KeyName='None'
    f:emit('/Script/RebelInput.RebelInputMappingSubsystem:ApplyPendingKeyboardMappings')
    check(#f:mcc()==1 and f:mcc()[1].Key.KeyName=='Z','missing runtime key wrote an invalid None mapping')
    check(table.concat(f.logs,' '):find('standard control binding unavailable',1,true),
        'missing runtime key was not reported')
end)

case('F03 owner loss blocks callbacks despite failed restoration',function()
    local options={}
    local f=Fixture.new(options)
    check(f.host:apply(f:plan()),'attachment failed')
    local callback=assert(f:lastCallback())
    options.rebuildThrows=true
    f.pawn.InputComponent=nil
    pcall(function() f.host:sync() end)
    callback({})
    check(activations(f)==0,'lost-owner callback delivered')
    check(not f.host.ready,'lost owner remained ready')
end)

case('F04 held focus resets across native context loss',function()
    local f=Fixture.new()
    local focus={id='focus',mode=2,action={type='focus',group=2}}
    local plan=f:plan({bindings={focus}})
    focus.keyName='LeftAlt';focus.phases={'Started','Completed','Canceled'}
    check(f.host:apply(plan),'attachment failed')
    assert(f:lastCallback('Started'))({})
    check(f.host.state.selectedGroup==2,'focus did not select group 2')
    f.input.AppliedInputContexts[f.native]=nil
    f.host:sync()
    check(f.host.state.selectedGroup==2,'retirement did not restore native group 0')
    check(not f.host.state.held or not next(f.host.state.held),'retirement retained held gesture')
end)

case('Default wheel is activated and published on load and after retirement',function()
    for _,defaultGroup in ipairs({1,2}) do
        local f=Fixture.new()
        local focus={id='focus',keyName='LeftAlt',mode=0,phases={'Triggered'},
            action={type='focus',group=3-defaultGroup}}
        check(f.host:apply(f:plan({bindings={focus},defaultGroup=defaultGroup})),'attachment failed')
        check(#f.events==1 and f.events[1].payload.group.from==nil
            and f.events[1].payload.group.to==defaultGroup,'load did not publish the Default wheel')
        assert(f:lastCallback('Triggered'))({})
        check(f.host.state.selectedGroup==3-defaultGroup and #f.events==2,'focus key did not publish')
        f.input.AppliedInputContexts[f.native]=nil
        f.host:sync()
        local last=f.events[#f.events].payload.group
        check(#f.events==3 and last.from==3-defaultGroup and last.to==defaultGroup,
            'retirement did not publish its reset to Default')
        f.input.AppliedInputContexts[f.native]=5
        f.host:sync()
        check(f.host.ready and #f.events==3 and f.host.state.selectedGroup==defaultGroup,
            're-attachment changed the published focus')
    end
end)

case('F06 priority-only transition keeps MCC keys in the game context',function()
    local f=Fixture.new()
    check(f.host:apply(f:plan()),'attachment failed')
    check(#f:mcc()==1 and f.input.AppliedInputContexts[f.native]==5,'initial mapping missing')
    f.input.AppliedInputContexts[f.native]=50
    check(f.host:sync(),'priority sync failed')
    check(#f:mcc()==1,'priority change lost or duplicated MCC keys')
    check(f.counts.adds==0,'priority change applied an MCC context')
end)

case('F07 unchanged established sync avoids global scans and glyph writes',function()
    local f=Fixture.new()
    check(f.host:apply(f:plan()),'attachment failed')
    local scans,sets=f.counts.scans,f.counts.sets
    check(f.host:sync(),'unchanged sync failed')
    check(f.counts.scans==scans,'unchanged sync enumerated all InputActions')
    check(f.counts.sets==sets,'unchanged sync rewrote indicator')
end)

case('F07 unchanged established sync avoids glyph writes',function()
    local f=Fixture.new()
    check(f.host:apply(f:plan()),'attachment failed')
    local sets=f.counts.sets
    check(f.host:sync(),'unchanged sync failed')
    check(f.counts.sets==sets,'unchanged sync rewrote indicator')
end)

case('F07 Apply forces one active indicator glyph refresh',function()
    local f=Fixture.new()
    check(f.host:apply(f:plan()),'initial Apply failed')
    local assigns=f.counts.assigns
    check(f.host:apply(f:plan()),'repeat Apply failed')
    check(f.counts.assigns==assigns+1,'Apply should refresh the one active indicator once')
end)

case('F07 startup adoption removes stale MCC gate and preserves foreign trigger',function()
    local f=Fixture.new()
    local stale=f.makeObject('InputAction','/Game/Input.IA_Stale')
    local foreign=f.makeObject('InputTrigger','/Game/Input.ForeignTrigger')
    local gate=f.makeObject('InputTriggerChordAction',stale.path .. ':MCC_OverrideChord')
    stale.Triggers={foreign,gate}
    f.nativeActions[#f.nativeActions+1]=stale
    check(f.host:apply(f:plan({overrides={}})),'attachment failed')
    check(#stale.Triggers==1 and stale.Triggers[1]==foreign,
        'startup adoption did not remove only the stale MCC gate')
end)

case('F02 bind-time callback cannot deliver after commit',function()
    local f=Fixture.new({deferred=true,duringBind=function(f,index) f.callbacks[index].callback({}) end})
    check(f.host:apply(f:plan()),'attachment failed')
    f:drain()
    check(activations(f)==0,'bind-time event became eligible after commit')
end)

case('F02 mapping mutate-then-throw cannot leave a delivering candidate',function()
    local f=Fixture.new({mapThrows=true})
    local ran,active=pcall(function() return f.host:apply(f:plan()) end)
    check(ran,'mapping exception escaped Apply')
    check(not active and not f.host.ready,'failed mapping attachment published readiness')
    local callback=f:lastCallback();if callback then callback({}) end
    check(activations(f)==0,'failed mapping candidate delivered')
end)

case('F03 bridge close failure retains cleanup ownership without delivery',function()
    local options={}
    local f=Fixture.new(options)
    check(f.host:apply(f:plan()),'attachment failed')
    local callback=assert(f:lastCallback())
    options.closeThrows=true
    f.pawn.InputComponent=nil
    pcall(function() f.host:sync() end)
    callback({})
    check(activations(f)==0,'closed-owner callback delivered during cleanup failure')
    check(not f.host.ready,'cleanup failure retained readiness')
    options.closeThrows=false
    f.host:sync()
    check(not f.host.ready,'no-owner sync incorrectly reattached')
end)

case('F03 bridge disappearance retires an established owner',function()
    local f=Fixture.new()
    check(f.host:apply(f:plan()),'attachment failed')
    local callback=assert(f:lastCallback())
    f.bridgeAvailable=false
    local active=f.host:sync()
    check(not active and not f.host.ready,'missing bridge left host ready')
    callback({})
    check(activations(f)==0,'missing-bridge callback delivered')
    check(#f:mcc()==0,'missing bridge retained MCC keys in the game context')
    check(f.indicator.EnhancedInputAction==f.original,'missing bridge retained indicator assignment')
end)

case('F05 owned HUD wins over earlier valid foreign HUD',function()
    local f=Fixture.new({twoHuds=true})
    check(f.host:apply(f:plan()),'attachment failed')
    check(f.service:hud()==f.hud,'service selected foreign HUD')
    check(f.indicator.EnhancedInputAction~=f.original,'owned indicator was not assigned')
    assert(f:lastCallback())({})
    local owned,foreign=false,false
    for _,call in ipairs(f.calls) do
        if call=='owned-click' then owned=true end
        if call=='foreign-click' then foreign=true end
    end
    check(owned and not foreign,'quickslot delivery used foreign HUD')
end)

case('F08 delayed readiness retries are bounded and generation-aware',function()
    local f=Fixture.new()
    local component=f.pawn.InputComponent
    f.pawn.InputComponent=nil
    local active=f.host:apply(f:plan())
    check(not active and not f.host.ready,'incomplete stack became ready')
    check(#f.delayed==1 and f.delayed[1].ms==100,'first readiness retry was not 100 ms')
    check(f:fireDelay()==100,'first retry missing')
    check(#f.delayed==1 and f.delayed[1].ms==500,'second readiness retry was not 500 ms')
    f.pawn.InputComponent=component
    check(f:fireDelay()==500,'second retry missing')
    check(f.host.ready,'ready stack did not attach on delayed retry')
    check(#f.delayed==0,'ready stack kept scheduling retries')
    local adds=f.counts.adds
    check(f.host:stop(),'stop failed')
    check(#f.delayed==0 and f.counts.adds==adds,'stopped host scheduled more attachment work')
end)

case('F14 MCC attaches only while a game context is applied',function()
    local f=Fixture.new()
    check(f.host:apply(f:plan()),'attachment failed')
    f.input.AppliedInputContexts[f.native]=nil
    local active=f.host:sync()
    check(not active and not f.host.ready,'context loss did not retire')
    check(#f:mcc()==0,'retiring left MCC keys in the game context')
    f.pawn.InputComponent=f.makeObject('EnhancedInputComponent','/Engine/Transient.Component_1')
    active=f.host:sync()
    check(not active and not f.host.ready,'MCC attached without an applied game context')
    f.input.AppliedInputContexts[f.native]=5
    check(f.host:sync() and f.host.ready,'MCC did not attach once the game context returned')
    check(#f:mcc()==1,'returning context did not receive MCC keys')
end)

case('F01 unrelated external wake during mapping mutation is coalesced',function()
    local fired=false
    local f=Fixture.new({deferred=true,coupledHooks=true})
    local map=f.native.MapKey
    function f.native:MapKey(action,key)
        if not fired then
            fired=true
            f:emit('/Script/Engine.PlayerController:ClientRestart',f.controller)
            f:emit('/Script/Engine.PlayerController:ClientRestart',f.controller)
        end
        return map(self,action,key)
    end
    check(f.host:apply(f:plan()),'attachment failed')
    check(f:drain()==1,'external wake must produce exactly one follow-up pass')
    check(#f:mcc()==1,'external wake remapped unchanged keys')
end)

case('F08 stop prevents queued wake from resurrecting input',function()
    local f=Fixture.new({deferred=true})
    check(f.host:apply(f:plan()),'attachment failed')
    local callback=assert(f:lastCallback())
    f:emit('/Script/Engine.PlayerController:ClientRestart',f.controller)
    check(type(f.host.stop)=='function','host stop API unavailable')
    check(f.host:stop(),'stop failed')
    f:drain()
    callback({});f:drain()
    check(not f.host.ready,'queued wake resurrected stopped host')
    check(#f:mcc()==0,'queued wake mapped MCC keys again')
    check(activations(f)==0,'stopped callback delivered')
end)

case('F02 queue rejection does not publish callback delivery',function()
    local options={queueRejects=true}
    local f=Fixture.new(options)
    check(f.host:apply(f:plan()),'attachment failed')
    local callback=assert(f:lastCallback())
    callback({})
    check(activations(f)==0,'rejected callback queue delivered')
end)

case('F02 queue exception does not publish callback delivery',function()
    local options={queueThrows=true}
    local f=Fixture.new(options)
    check(f.host:apply(f:plan()),'attachment failed')
    local callback=assert(f:lastCallback())
    callback({})
    check(activations(f)==0,'failed callback queue delivered')
end)

case('F09 DMM Apply, runtime delivery, and invalid-file retention',function()
    local Menu,Config,DMM,Plan=require('mc_menu'),require('mc_config'),require('mc_dmm'),require('mc_input_plan')
    local definition=Menu.define(require('mc_sections'),require('mc_maps'))
    local directory=os.tmpname()
    assert(os.remove(directory))
    assert(os.execute('mkdir ' .. string.format('%q',directory)))
    local configPath=directory .. '/config.ini'
    local passed,why=pcall(function()
        local choices={}
        function choices.open()
            local model={items={},pending={},committed={}}
            for i,item in ipairs(definition.settings) do
                model.items[i]={id=item.id}
                model.pending[i],model.committed[i]=item.default,item.default
            end
            return model
        end
        DMM.installStorage(choices)
        local model=choices.open({id='ModCoreControls',path=directory .. '/mod_settings.ini'})
        check(not model.error,model.error)
        local indices={}
        for i,item in ipairs(model.items) do indices[item.id]=i end
        local map=assert(indices.MCC_actions_Map)
        local slot=assert(indices.MCC_actions_global_SlotAction1_Key)
        model.pending[map]=2;model.pending[slot]=74
        local saved,saveWhy,event=model:apply()
        check(saved,saveWhy)
        check(event and event.values.MCC_actions_Map==2,'Apply event missing selected map')
        local store=Config.open(configPath,definition)
        local selected=Menu.new(definition,store.values)
        local plan=Plan.build(definition,selected.values)
        local f=Fixture.new()
        for name in pairs(plan.overrides) do
            local action=f.makeObject('InputAction','/Game/Input.' .. name)
            action.Triggers={}
            f.nativeActions[#f.nativeActions+1]=action
        end
        check(f.host:apply(plan),'saved plan did not activate')
        local callback=assert(f:lastCallback('Triggered'))
        callback({})
        check(activations(f)==1,'saved plan did not deliver')
        local file=assert(io.open(configPath,'wb'))
        assert(file:write('[ModCoreControls.actions]\nmap=corrupt\n'))
        assert(file:close())
        local decoded=pcall(Config.open,configPath,definition)
        check(not decoded,'corrupt config was accepted')
        check(f.host.ready,'invalid saved file retired live plan')
        callback({})
        check(activations(f)==2,'invalid file disabled previous live plan')
        check(f.host:deactivate(),'deactivation failed')
        check(f.indicator.EnhancedInputAction==f.original,'indicator not restored')
    end)
    os.remove(configPath)
    os.execute('rmdir ' .. string.format('%q',directory))
    check(passed,why)
end)

case('Default owns the swap on the Toggle Quickslots key',function()
    local Menu=require('mc_menu')
    local definition=Menu.define(require('mc_sections'),require('mc_maps'))
    local model=Menu.new(definition,{})
    local default=definition.sections[1].maps[1]
    local f=Fixture.new()
    local down=f.makeObject('InputTriggerDown','/Game/Input.NativeDown')
    f.swapAction.Triggers={down}
    f.nativeActions[#f.nativeActions+1]=f.swapAction
    check(f.host:apply(require('mc_input_plan').build(definition,model.values)),
        'Default failed to attach in OW')
    check(f.counts.adds==0,'Default must not apply an MCC context')
    local entries=f:mcc()
    check(#entries==1 and entries[1].Key.KeyName=='LeftAlt',
        'the MCC toggle must be mapped into the game context on the player key')
    check(f.swapAction.Triggers[1]==down and f.swapAction.Triggers[2]
        and f.swapAction.Triggers[2].path:find('MCC_OverrideChord',1,true),
        'the native toggle must be suppressed by an override, keeping its own triggers')
    check(#f.callbacks==1 and f.callbacks[1].phase=='Triggered','the MCC toggle must be bound')
    local before=#f.calls
    f.callbacks[1].callback({});f:drain()
    check(f.calls[before+1]=='select:1','the toggle must focus the other wheel')
    f.callbacks[1].callback({});f:drain()
    check(f.calls[before+2]=='select:2','a second toggle must return')
    check(f.host:deactivate(),'Default cleanup failed')
    check(#f.swapAction.Triggers==1 and f.swapAction.Triggers[1]==down,
        'cleanup must restore the native toggle')
    check(#f:mcc()==0,'cleanup must unmap the MCC toggle')
    model:set(default.holdSwap.enabled.id,1)
    local f2=Fixture.new()
    f2.nativeActions[#f2.nativeActions+1]=f2.swapAction
    check(f2.host:apply(require('mc_input_plan').build(definition,model.values)),
        'Hold Swap failed to attach')
    entries=f2:mcc()
    check(#entries==2 and entries[1].Key.KeyName=='LeftAlt' and entries[2].Key.KeyName=='LeftAlt',
        'Hold Swap must map press and release edges on the player key')
    check(f2.host:deactivate(),'Hold Swap cleanup failed')
end)


case('everywhere keys live in IMC_Base across combat transitions',function()
    local f=Fixture.new()
    local base=f.makeObject('InputMappingContext','/Game/Input.IMC_Base.Runtime')
    base.Mappings={};base.MapKey=f.native.MapKey;base.UnmapKey=f.native.UnmapKey
    f.input.AppliedInputContexts[base]=0
    local combat=f.makeObject('InputMappingContext','/Game/Input.IMC_RTCombat.Runtime')
    combat.Mappings={};combat.MapKey=f.native.MapKey;combat.UnmapKey=f.native.UnmapKey
    local Menu=require('mc_menu')
    local definition=Menu.define(require('mc_sections'),require('mc_maps'))
    f.nativeActions[#f.nativeActions+1]=f.swapAction
    check(f.host:apply(require('mc_input_plan').build(definition,Menu.new(definition,{}).values)),
        'Default failed to attach')
    local function mcc(context)
        local count=0
        for _,entry in ipairs(context.Mappings) do
            if entry.Action.path:find('IA_MCC_',1,true) then count=count+1 end
        end
        return count
    end
    check(mcc(base)==1 and #f:mcc()==0,'the swap usable everywhere must live in IMC_Base')
    -- Entering combat replaces IMC_OW with IMC_RTCombat; leaving restores neither.
    f.input.AppliedInputContexts[f.native]=nil
    f.input.AppliedInputContexts[combat]=3
    check(f.host:sync() and mcc(base)==1 and mcc(combat)==0,'combat must keep the swap in IMC_Base')
    f.input.AppliedInputContexts[combat]=nil
    check(f.host:sync() and f.host.ready and mcc(base)==1,
        'after combat the swap must still be mapped in IMC_Base')
end)

print(('AUDIT 6 integration: %d failure(s)'):format(failures))
if failures>0 and not baseline then os.exit(1) end
