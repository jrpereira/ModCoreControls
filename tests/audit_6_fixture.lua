package.path='Scripts/?.lua;' .. package.path

local Host=require('mc_input_host')
local F={}

local function object(class,path)
    local value={class=class,path=path,full=class .. ' ' .. path,valid=true}
    function value:IsValid() return self.valid end
    function value:GetFullName() return self.full end
    return value
end

function F.new(options)
    options=options or {}
    local f={hooks={},hookIds={},pending={},delayed={},callbacks={},calls={},counts={adds=0,removes=0,scans=0,sets=0,assigns=0,saves=0,queues=0,drains=0,closes=0}}
    local c=f.counts
    local nextHookId=0
    f.player=object('LocalPlayer','/Engine/Transient.Player_0')
    f.input=object('PlayerInput','/Engine/Transient.Input_0')
    f.component=object('EnhancedInputComponent','/Engine/Transient.Component_0')
    f.pawn=object('Pawn','/Engine/Transient.Pawn_0');f.pawn.InputComponent=f.component
    f.controller=object('BP_PlayerController_C','/Engine/Transient.Controller_0')
    f.controller.PlayerInput,f.controller.AcknowledgedPawn,f.controller.Player=f.input,f.pawn,f.player
    f.subsystem=object('EnhancedInputLocalPlayerSubsystem','/Engine/Transient.Subsystem_0')
    f.subsystem.Outer=f.player
    f.native=object('InputMappingContext','/Game/Input.IMC_OW.Runtime')
    f.input.AppliedInputContexts={[f.native]=5}
    f.override=object('InputAction','/Game/Input.IA_Test');f.override.Triggers={}
    f.swapAction=object('InputAction','/Game/Input.IA_Combat_ToggleQuickslots')
    f.swapAction.Triggers={}
    f.swapMapping={Action=f.swapAction,Key={KeyName='LeftAlt'}}
    f.native.Mappings={f.swapMapping}
    -- MCC maps its keys into the game's own context and removes only its own.
    function f.native:MapKey(action,key)
        c.maps=(c.maps or 0)+1
        local entry={Action=action,Key=key}
        self.Mappings[#self.Mappings+1]=entry
        if options.mapThrows then error('injected MapKey error after mutation') end
        return entry
    end
    -- MCC's own entries in the game context, in mapping order.
    function f:mcc()
        local entries={}
        for _,entry in ipairs(self.native.Mappings) do
            if entry.Action.path:find('IA_MCC_',1,true) then entries[#entries+1]=entry end
        end
        return entries
    end
    function f.native:UnmapKey(action,key)
        for index=#self.Mappings,1,-1 do
            local entry=self.Mappings[index]
            if entry.Action==action and entry.Key.KeyName==key.KeyName then table.remove(self.Mappings,index) end
        end
    end
    f.makeObject=object
    f.nativeActions={f.override}
    f.original=object('InputAction','/Game/Input.IA_Original')
    f.indicator=object('Widget','/Engine/Transient.AbilityLeft')
    f.indicator.EnhancedInputAction=f.original
    local bindingWidgets=object('Bindings','/Engine/Transient.Bindings');bindingWidgets.Left=f.indicator
    local wheel=object('Wheel','/Engine/Transient.Wheel');wheel.WBP_AA_Quickslots_Bindings=bindingWidgets
    f.hud=object('WBP_GameHUD_C','/Engine/Transient.HUD');f.hud.WBP_AA_Quickslots=wheel
    if options.twoHuds then
        f.foreignHud=object('WBP_GameHUD_C','/Engine/Transient.ForeignHUD')
        f.foreignController=object('BP_PlayerController_C','/Engine/Transient.ForeignController')
        f.foreignHud.OwningPlayer=f.foreignController
        f.hud.OwningPlayer=f.controller
        local button=object('Button','/Engine/Transient.AbilityLeftButton')
        function button:BP_OnClicked() f.calls[#f.calls+1]='owned-click';return true end
        wheel.Left=button
        local foreignWheel=object('Wheel','/Engine/Transient.ForeignWheel')
        local foreignButton=object('Button','/Engine/Transient.ForeignLeftButton')
        function foreignButton:BP_OnClicked() f.calls[#f.calls+1]='foreign-click';return true end
        foreignWheel.Left=foreignButton
        f.foreignHud.WBP_AA_Quickslots=foreignWheel
        local switcher=object('Switcher','/Engine/Transient.Switcher')
        function switcher:GetChildrenCount() return 2 end
        function switcher:SetActiveWidgetIndex(index) self.activeIndex=index;return true end
        f.hud.QuickslotsSwitcher=switcher
    end
    local retained,indicatorState={},nil
    local resolved={[f.indicator.path]=f.indicator,[f.original.path]=f.original,
        ['/Game/_Dawnwalker/Player/Input/Actions/Combat/IA_Combat_ToggleQuickslots.IA_Combat_ToggleQuickslots']=f.swapAction}
    local gate
    local mappingHook='/Script/EnhancedInput.EnhancedInputSubsystemInterface:'
    function f:emit(name,...)
        local callback=self.hooks[name]
        if callback then callback(...) end
    end
    function f.subsystem:AddMappingContext(mapping,priority)
        c.adds=c.adds+1
        if c.adds>(options.mappingLimit or 20) then error('fixture mapping recursion limit') end
        f.input.AppliedInputContexts[mapping]=priority
        if options.addThrows then error('injected AddMappingContext error after mutation') end
        if options.duringAdd then options.duringAdd(f,mapping) end
        if options.coupledRebuild then f:emit(mappingHook .. 'RequestRebuildControlMappings',self) end
        if options.coupledHooks then f:emit(mappingHook .. 'AddMappingContext',self,mapping,priority) end
    end
    function f.subsystem:RemoveMappingContext(mapping)
        c.removes=c.removes+1
        f.input.AppliedInputContexts[mapping]=nil
        if options.removeThrows then error('injected RemoveMappingContext error after mutation') end
        if options.coupledHooks then f:emit(mappingHook .. 'RemoveMappingContext',self,mapping) end
    end
    function f.subsystem:ClearAllMappings()
        f.input.AppliedInputContexts={}
        if options.coupledHooks then f:emit(mappingHook .. 'ClearAllMappings',self) end
    end
    local function retain(kind,name)
        local key=kind .. ':' .. name
        if retained[key] then return retained[key] end
        local value=object(kind,'/Engine/Transient.' .. name);value.Triggers={}
        function value:UnmapAll() self.mappings={} end
        function value:MapKey(action,key)
            local entry={action=action,key=key,Triggers={}}
            self.mappings[#self.mappings+1]=entry
            return entry
        end
        retained[key]=value;resolved[value.path]=value
        return value
    end
    f.retained=retained
    local bridge={}
    function bridge.GetCapabilities() return {api=5,enhanced_input=true,explicit_target=true} end
    function bridge.OpenInputComponent(path)
        if options.openThrows then error('injected open error') end
        return path
    end
    function bridge.BindAction(_,_,phase,callback)
        f.callbacks[#f.callbacks+1]={phase=phase,callback=callback}
        if options.duringBind then options.duringBind(f,#f.callbacks) end
        if options.bindThrows then error('injected bind error') end
        return #f.callbacks
    end
    function bridge.CloseInputComponent()
        c.closes=c.closes+1
        if options.closeThrows then error('injected close error') end
        return true
    end
    f.bridge=bridge
    local environment={
        bridge=function() if f.bridgeAvailable==false then return nil end;return bridge end,
        valid=function(value) return value and value.valid==true end,
        unwrap=function(value) return value end,
        full=function(value) return value and value.full end,
        path=function(value) return value and value.path end,
        each=function(values,callback)
            for key,value in pairs(values or {}) do
                if type(key)=='number' then callback(value,key) else callback(key,value) end
            end
            return true
        end,
        find=function(class,predicate)
            local items=class=='BP_PlayerController_C' and (f.controllers or {f.controller})
                or class=='EnhancedInputLocalPlayerSubsystem' and {f.subsystem}
                or class=='WBP_GameHUD_C' and {f.hud} or {}
            for _,value in ipairs(items) do if value.valid and (not predicate or predicate(value)) then return value end end
        end,
        all=function(class)
            if class=='InputAction' then c.scans=c.scans+1;return f.nativeActions end
            if class=='EnhancedInputLocalPlayerSubsystem' then return {f.subsystem} end
            if class=='WBP_GameHUD_C' and options.twoHuds then return {f.foreignHud,f.hud} end
            return {}
        end,
        mappingContexts=function() return f.configuredContexts or {} end,
        runtimeKeys=function(live,action)
            assert(live.subsystem==f.subsystem,'runtime query used a foreign player')
            if f.runtimeKeys then return f.runtimeKeys end
            if action==f.swapAction then return {f.swapMapping.Key} end
            return {}
        end,
        retain=retain,initialize=function() end,
        trigger=function(_,name) local value=object(name,'/Engine/Transient.' .. name);value.Triggers={};return value end,
        name=function(value) return value end,
        resolve=function(path) return resolved[path] end,
        setIndicatorAction=function(widget,action)
            c.sets=c.sets+1
            if action and action.path and action.path:find('IA_MCC_',1,true) then c.assigns=c.assigns+1 end
            if options.setThrows then error('injected indicator setter error') end
            widget.EnhancedInputAction=action
            return true
        end,
        loadIndicatorState=function() return indicatorState end,
        saveIndicatorState=function(value)
            c.saves=c.saves+1
            if options.saveThrows then error('injected journal error') end
            indicatorState=value;return true
        end,
        constructOverride=function(action,marker)
            if not gate then gate=object('InputTriggerChordAction',action.path .. ':' .. marker) end
            return gate
        end,
        rebuild=function()
            if options.rebuildThrows then error('injected override rebuild error') end
            c.rebuilds=(c.rebuilds or 0)+1
            if options.coupledRebuild then f:emit(mappingHook .. 'RequestRebuildControlMappings',f.subsystem) end
            return true
        end,
        options={},
        preHook=function(name,callback)
            nextHookId=nextHookId+2
            local id=nextHookId-1
            f.hooks[name]=callback;f.hookIds[name]={id,id+1}
            return id,id+1
        end,
        hook=function(name,callback)
            nextHookId=nextHookId+2
            local id=nextHookId-1
            f.hooks[name]=callback;f.hookIds[name]={id,id+1}
            return id,id+1
        end,
        unhook=function(name,pre,post)
            local ids=assert(f.hookIds[name],'unknown hook')
            assert(ids[1]==pre and ids[2]==post,'incorrect hook removal signature')
            f.hooks[name]=nil;f.hookIds[name]=nil
            return true
        end,
        notify=function(name,callback) f.hooks[name]=callback;return name end,
        hud=function() return f.hud end,
        hudForOwner=not options.twoHuds and function() return f.hud end or nil,
        delay=function(ms,callback)
            f.delayed[#f.delayed+1]={ms=ms,callback=callback}
            return true
        end,
    }
    f.environment=environment
    local service={}
    function service:bind(owner,generation) self.owner,self.generation=owner,generation;return true end
    function service:hud() return f.hud end
    function service:invalidate() self.owner=nil;return true end
    function service:reset(group) f.calls[#f.calls+1]='reset:' .. group;return true end
    function service:activate(kind,slot) f.calls[#f.calls+1]=kind .. ':' .. slot;return true end
    function service:select(group) f.calls[#f.calls+1]='select:' .. group;return true end
    f.events={}
    function service:emit(name,payload) f.events[#f.events+1]={name=name,payload=payload};return true end
    if options.twoHuds then
        service=require('mc_quickslots').new({valid=environment.valid,unwrap=environment.unwrap})
    end
    f.service=service
    local function queue(callback)
        c.queues=c.queues+1
        if options.queueThrows then error('injected queue error') end
        if options.queueRejects then return false,'injected queue rejection' end
        if options.deferred then f.pending[#f.pending+1]=callback
        else callback() end
        return true
    end
    function f:drain(limit)
        local count=0
        while #self.pending>0 do
            count=count+1
            assert(count<=(limit or 30),'fixture queue failed to settle')
            local callback=table.remove(self.pending,1)
            c.drains=c.drains+1;callback()
        end
        return count
    end
    function f:fireDelay()
        local item=table.remove(self.delayed,1)
        if item then item.callback() end
        return item and item.ms
    end
    f.host=Host.new(queue,function(message) f.logs=f.logs or {};f.logs[#f.logs+1]=message end,service,environment)
    function f:plan(extra)
        local plan={contexts={'exploration'},bindings={{id='global.slot1',keyName='One',mode=0,
            phases={'Triggered'},action={type='ability',slot=1}}},overrides={IA_Test=true}}
        if extra then for key,value in pairs(extra) do plan[key]=value end end
        return plan
    end
    function f:lastCallback(phase)
        for index=#self.callbacks,1,-1 do
            if not phase or self.callbacks[index].phase==phase then return self.callbacks[index].callback end
        end
    end
    return f
end

return F
