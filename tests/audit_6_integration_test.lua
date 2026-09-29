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
    check(f.counts.adds==1,'self-generated AddMappingContext caused ' .. f.counts.adds .. ' additions')
    check(f.counts.queues==0,'self-generated mapping queued a sync')
    check(f.host:deactivate(),'deactivation failed')
    check(f.counts.removes==1,'self-generated removal caused ' .. f.counts.removes .. ' removals')
end)

case('F01 coupled mapping hook, deferred queue',function()
    local f=Fixture.new({deferred=true,coupledHooks=true})
    check(f.host:apply(f:plan()),'attachment failed')
    check(f:drain()==0,'self-generated mapping queued a redundant pass')
    check(f.counts.adds==1,'unexpected mapping additions')
    f.native.valid=false
    f:emit('/Script/EnhancedInput.EnhancedInputSubsystemInterface:RemoveMappingContext',f.subsystem,f.native)
    check(f:drain()<=1,'external mapping removal was not coalesced')
end)

case('F02 unavailable override never publishes readiness',function()
    local f=Fixture.new()
    local ran,active=pcall(function() return f.host:apply(f:plan({overrides={IA_Missing=true}})) end)
    check(ran,'Apply propagated an exception')
    check(not active and not f.host.ready,'failed attachment remained ready')
    local callback=f:lastCallback();if callback then callback({}) end
    check(activations(f)==0,'uncommitted callback delivered')
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
    check(f.host.state.selectedGroup==1,'retirement left alternative focus selected')
    check(not f.host.state.held or not next(f.host.state.held),'retirement retained held gesture')
end)

case('F06 priority-only transition updates owned mapping',function()
    local f=Fixture.new()
    check(f.host:apply(f:plan()),'attachment failed')
    local context=f.retained['InputMappingContext:IMC_MCC_Exploration']
    check(f.input.AppliedInputContexts[context]==1005,'initial priority mismatch')
    f.input.AppliedInputContexts[f.native]=50
    check(f.host:sync(),'priority sync failed')
    check(f.input.AppliedInputContexts[context]==1050,'priority change was ignored')
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
    local f=Fixture.new({addThrows=true})
    local ran,active=pcall(function() return f.host:apply(f:plan()) end)
    check(ran,'mapping exception escaped Apply')
    check(not active and not f.host.ready,'failed mapping attachment published readiness')
    local callback=f:lastCallback();if callback then callback({}) end
    check(activations(f)==0,'failed mapping candidate delivered')
    local mapping=f.retained['InputMappingContext:IMC_MCC_Exploration']
    check(f.input.AppliedInputContexts[mapping]==nil,'partially added mapping was not removed')
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
    local mapping=f.retained['InputMappingContext:IMC_MCC_Exploration']
    check(f.input.AppliedInputContexts[mapping]==nil,'missing bridge retained generated mapping')
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

case('F14 observed native context loss does not re-enable fallback on unchanged stack',function()
    local f=Fixture.new()
    check(f.host:apply(f:plan()),'attachment failed')
    f.input.AppliedInputContexts[f.native]=nil
    local active=f.host:sync()
    check(not active and not f.host.ready,'context loss did not retire')
    local adds=f.counts.adds
    active=f.host:sync()
    check(not active and not f.host.ready,'unchanged stack incorrectly reused initial exploration fallback')
    check(f.counts.adds==adds,'unchanged stack added a fallback mapping')
    f.pawn.InputComponent=f.makeObject('EnhancedInputComponent','/Engine/Transient.Component_1')
    check(f.host:sync(),'fresh stack did not permit initial exploration fallback')
    check(f.host.ready,'fresh stack remained pending')
end)

case('F01 unrelated external wake during mapping mutation is coalesced',function()
    local fired=false
    local f=Fixture.new({deferred=true,coupledHooks=true,duringAdd=function(f)
        if not fired then
            fired=true
            f:emit('/Script/Engine.PlayerController:ClientRestart',f.controller)
            f:emit('/Script/Engine.PlayerController:ClientRestart',f.controller)
        end
    end})
    check(f.host:apply(f:plan()),'attachment failed')
    check(f:drain()==1,'external wake must produce exactly one follow-up pass')
    check(f.counts.adds==1,'external wake reattached unchanged mapping')
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
    check(f.counts.adds==1,'queued wake added another mapping')
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
        local slot=assert(indices.MCC_actions_flat_SlotAction1_Key)
        model.pending[map]=1;model.pending[slot]=74
        local saved,saveWhy,event=model:apply()
        check(saved,saveWhy)
        check(event and event.values.MCC_actions_Map==1,'Apply event missing selected map')
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

print(('AUDIT 6 integration: %d failure(s)'):format(failures))
if failures>0 and not baseline then os.exit(1) end
