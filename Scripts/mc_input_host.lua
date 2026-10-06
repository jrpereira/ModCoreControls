-- Discover the live player input stack, own MCC mappings, and retire stale callbacks.
local Context=require('mc_input_context')
local Callbacks=require('mc_native_callbacks')
local Quickslots=require('mc_quickslots')
local KeyIndicators=require('mc_key_indicators')
local Overrides=require('mc_overrides')
local Events=require('mc_events')
local Log=require('mc_log')
local M={}

local function defaultEnvironment()
    local function unwrap(value)
        if value==nil then return nil end
        local ok,result=pcall(function() return value:get() end)
        return ok and result or value
    end
    local function valid(value)
        local ok,result=pcall(function() return value~=nil and value:IsValid() end)
        return ok and result==true
    end
    local function full(value)
        local ok,result=pcall(function() return value:GetFullName() end)
        return ok and tostring(result) or nil
    end
    local function path(value)
        local name=full(value);return name and (name:match('^%S+%s+(.+)$') or name) or nil
    end
    local function each(values,callback)
        if type(values)=='table' then
            for key,value in pairs(values) do
                if type(key)=='number' then callback(unwrap(value),key)
                else callback(unwrap(key),unwrap(value)) end
            end
            return true
        end
        return pcall(function()
            values:ForEach(function(key,value)
                key,value=unwrap(key),unwrap(value)
                if type(key)=='number' then callback(value,key) else callback(key,value) end
            end)
        end)
    end
    local function find(class,predicate)
        local ok,items=pcall(FindAllOf,class)
        if not ok or type(items)~='table' then return nil end
        for _,item in ipairs(items) do if valid(item) and (not predicate or predicate(item)) then return item end end
    end
    local function cls(name)
        return assert(StaticFindObject('/Script/EnhancedInput.' .. name),'missing Enhanced Input class: ' .. name)
    end
    local retained={}
    local function retain(kind,name)
        local cached=retained[kind .. ':' .. name]
        if valid(cached) then return cached end
        -- MCC's actions live in the transient package; MCC owns no mapping context.
        local engine=assert(find('Engine'),'Engine unavailable')
        local outer=assert(engine:GetOuter(),'Transient outer unavailable')
        local objectPath=path(outer) .. '.' .. name
        local object=StaticFindObject(objectPath)
        if not valid(object) then object=StaticConstructObject(cls(kind),outer,FName(name),0xC0) end
        retained[kind .. ':' .. name]=object
        return object
    end
    return {
        valid=valid,unwrap=unwrap,full=full,path=path,each=each,find=find,
        all=function(class)
            local ok,items=pcall(FindAllOf,class)
            return ok and type(items)=='table' and items or {}
        end,
        -- The Settings key profile holds the player's binding even when no
        -- applied context maps the action, e.g. the combat toggle in open world.
        profileKeys=function(live,action)
            local settings=unwrap(live.subsystem:GetUserSettings())
            local profile=valid(settings) and unwrap(settings:GetCurrentKeyProfile())
            if not valid(profile) then return nil end
            local actionPath=path(action)
            local mappable=unwrap(action.PlayerMappableKeySettings)
            local mappingName
            if mappable~=nil then
                local ok,name=pcall(function() return unwrap(mappable.Name):ToString() end)
                mappingName=ok and name or nil
            end
            local keys={}
            each(profile.PlayerMappedKeys,function(_,row)
                each(unwrap(row).Mappings,function(entry)
                    local associated=unwrap(entry.AssociatedInputAction)
                    local named
                    if mappingName then
                        local ok,name=pcall(function() return unwrap(entry.MappingName):ToString() end)
                        named=ok and name==mappingName
                    end
                    if (valid(associated) and path(associated)==actionPath) or named then
                        keys[#keys+1]=entry.CurrentKey
                    end
                end)
            end)
            return keys
        end,
        retain=retain,name=FName,
        -- false for a key name the engine does not know; nil when it cannot tell. The
        -- check is trusted only once it accepts a key that always exists.
        validKey=function(keyName)
            local library=StaticFindObject('/Script/Engine.Default__KismetInputLibrary')
            if not valid(library) then return nil end
            local function known(name)
                local ok,result=pcall(function() return library:Key_IsValid({KeyName=FName(name)}) end)
                if ok and type(result)=='boolean' then return result end
                return nil
            end
            if known('SpaceBar')~=true then return nil end
            return known(keyName)
        end,
        initialize=function(action)
            local library=assert(StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'))
            library:Conv_ObjectToSoftObjectReference(action)
        end,
        trigger=function(action,className) return StaticConstructObject(cls(className),action,0,0x40) end,
        bridge=function() return rawget(_G,'UE4SSLuaEventBridge') end,
        resolve=function(name)
            local ok,value=pcall(StaticFindObject,name)
            return ok and value or nil
        end,
        setIndicatorAction=function(widget,action) widget:SetEnhancedInputAction(action) end,
        constructOverride=function(action,marker)
            local gateClass=cls('InputTriggerChordAction')
            local gatePath=assert(path(action),'override action path unavailable') .. ':' .. marker
            local gate=StaticFindObject(gatePath)
            if not valid(gate) then
                gate=StaticConstructObject(gateClass,action,FName(marker),0xC0)
            end
            assert(valid(gate),'override chord unavailable: ' .. gatePath)
            assert(gate:IsA(gateClass),'unexpected object at override chord path: ' .. gatePath)
            assert(gate:HasAnyInternalFlags(0x40000000),
                'override chord is not root-captured: ' .. gatePath)
            return gate
        end,
        rebuild=function(playerInput)
            local library=assert(StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'),
                'EnhancedInputLibrary unavailable')
            assert(each(playerInput.AppliedInputContexts,function(context)
                context=unwrap(context)
                if valid(context) then library:RequestRebuildControlMappingsUsingContext(context,false) end
            end),'cannot inspect applied input contexts')
            return true
        end,
        loadIndicatorState=function()
            if not ModRef then return nil end
            local ok,value=pcall(function() return ModRef:GetSharedVariable('MCC.IndicatorActions.v2') end)
            return ok and value or nil
        end,
        saveIndicatorState=function(value)
            if not ModRef then return true end
            return pcall(function() ModRef:SetSharedVariable('MCC.IndicatorActions.v2',value) end)
        end,
        hook=function(name,callback) return RegisterHook(name,function() end,callback) end,
        preHook=function(name,callback) return RegisterHook(name,callback) end,
        notify=function(name,callback) return NotifyOnNewObject(name,callback) end,
        unhook=rawget(_G,'UnregisterHook'),
        inGameThread=rawget(_G,'IsInGameThread'),
        delay=rawget(_G,'ExecuteWithDelay'),
    }
end

function M.new(queue,log,service,environment)
    assert(type(queue)=='function','game-thread queue required')
    -- A leveled logger, or a plain function(message) as tests pass.
    log=Log.wrap(log)
    local api
    local publishControl=Events.publisher(rawget(_G,'ModRef'))
    service=service or Quickslots.new({emit=function(name,payload)
        local ok,why=pcall(publishControl,name,payload,api and api.owner)
        if not ok or why==false then
            log.warn('control event publication failed: ',why)
        end
    end})
    local e=environment or defaultEnvironment()
    local context=Context.new(e,log)
    local function property(object,name)
        if object==nil then return nil end
        local ok,value=pcall(function() return object[name] end)
        return ok and e.unwrap(value) or nil
    end
    local function nameString(value)
        value=e.unwrap(value)
        if value==nil then return nil end
        if type(value)=='string' then return value end
        local ok,result=pcall(function() return value:ToString() end)
        return ok and tostring(result) or tostring(value)
    end
    local indicators=KeyIndicators.new({
        valid=e.valid,path=e.path,property=property,
        resolve=e.resolve or function() return nil end,
        setAction=e.setIndicatorAction or function() return false end,
        hud=function()
            if type(service.hud)=='function' then return service:hud() end
            return type(e.hud)=='function' and e.hud() or e.find('WBP_GameHUD_C')
        end,
        load=e.loadIndicatorState,save=e.saveIndicatorState,
    })
    local overrides=Overrides.new({
        marker='MCC_OverrideChord',valid=e.valid,path=e.path,unwrap=e.unwrap,
        same=function(a,b) return a==b or (e.valid(a) and e.valid(b) and e.path(a)==e.path(b)) end,
        each=e.each,actions=function() return e.all('InputAction') end,
        inactive=function()
            local action=e.retain('InputAction','IA_MCC_OverrideInactive')
            action.Triggers={}
            return action
        end,
        construct=e.constructOverride or function() error('override chord construction unavailable') end,
        chord=function(trigger) return e.unwrap(trigger.ChordAction) end,
        setChord=function(trigger,action) trigger.ChordAction=action end,
        setTriggers=function(action,value) action.Triggers=value end,
        rebuild=e.rebuild or function() return true end,
    })
    local callbacks,bridge
    api={enabled=false,ready=false,generation=0,active={},state={},phase='pending'}
    local wakeQueued,busy,pendingWake,internalDepth=false,false,false,0
    local indicatorsQueued=false
    local wake,scheduleRetry
    local registrations={}
    local lastPending,reportedMissing
    local function internal(callback)
        internalDepth=internalDepth+1
        local ok,result,why=pcall(callback)
        internalDepth=internalDepth-1
        if not ok then error(result,0) end
        return result,why
    end
    local function sameOwner(left,right)
        return left and right and left.controller==right.controller
            and left.playerInput==right.playerInput and left.component==right.component
            and left.subsystem==right.subsystem
    end

    local function resolveBridge()
        local candidate=type(e.bridge)=='function' and e.bridge() or e.bridge
        if candidate==bridge and callbacks then return callbacks end
        if type(candidate)~='table' or type(candidate.GetCapabilities)~='function'
            or type(candidate.OpenInputComponent)~='function' or type(candidate.BindAction)~='function'
            or type(candidate.CloseInputComponent)~='function' then
            return nil,'UE4SSLuaEventBridge input API unavailable'
        end
        local ok,caps=pcall(candidate.GetCapabilities)
        if not ok or type(caps)~='table' or tonumber(caps.api or 0)<4
            or caps.enhanced_input~=true or caps.explicit_target~=true then
            return nil,'UE4SSLuaEventBridge Enhanced Input API 4 or newer required'
        end
        if callbacks and api.ready then return nil,'input bridge changed; retiring previous owner' end
        if callbacks and callbacks:hasActive() then
            local closed,why=callbacks:close()
            if not closed then return nil,'previous input bridge cleanup pending: ' .. tostring(why) end
        end
        bridge=candidate;callbacks=Callbacks.new(bridge,e.full)
        return callbacks
    end

    local function stack()
        local controllers=e.all and e.all('BP_PlayerController_C') or {}
        if #controllers==0 and e.find then
            local found=e.find('BP_PlayerController_C',function(item)
                return not (e.full(item) or ''):find('Default__',1,true)
            end)
            if found then controllers={found} end
        end
        for _,controller in ipairs(controllers) do
            if e.valid(controller) and not (e.full(controller) or ''):find('Default__',1,true) then
                local playerInput=property(controller,'PlayerInput')
                local pawn=property(controller,'AcknowledgedPawn') or property(controller,'Pawn')
                local component=pawn and property(pawn,'InputComponent') or nil
                local player=property(controller,'Player')
                if e.valid(playerInput) and e.valid(component) and e.valid(player) then
                    local playerPath=e.path(player)
                    local subsystems=e.all and e.all('EnhancedInputLocalPlayerSubsystem') or {}
                    if #subsystems==0 and e.find then
                        local found=e.find('EnhancedInputLocalPlayerSubsystem')
                        if found then subsystems={found} end
                    end
                    local match,unknown,count=nil,nil,0
                    for _,candidate in ipairs(subsystems) do
                        if e.valid(candidate) then
                            count=count+1
                            local outer=property(candidate,'Outer')
                            if not e.valid(outer) then
                                local ok,value=pcall(function() return candidate:GetOuter() end)
                                if ok then outer=e.unwrap(value) end
                            end
                            if e.valid(outer) then
                                if outer==player or e.path(outer)==playerPath then match=candidate end
                            else unknown=candidate end
                        end
                    end
                    local subsystem=match or (count==1 and unknown or nil)
                    if e.valid(subsystem) then
                        return {controller=controller,player=player,playerInput=playerInput,
                            component=component,subsystem=subsystem,componentPath=e.path(component)}
                    end
                end
            end
        end
    end
    local function call(object,method)
        if not e.valid(object) then return nil end
        local ok,value=pcall(function() return object[method](object) end)
        return ok and e.unwrap(value) or nil
    end
    local function ownerHud(live)
        if type(e.hudForOwner)=='function' then return e.hudForOwner(live) end
        local controllerWorld=call(live.controller,'GetWorld')
        local worldCandidate,count=nil,0
        for _,hud in ipairs(e.all and e.all('WBP_GameHUD_C') or {}) do
            if e.valid(hud) and (e.full(hud) or ''):find('/Engine/Transient',1,true) then
                local owner=property(hud,'OwningPlayer') or call(hud,'GetOwningPlayer')
                if e.valid(owner) then
                    if owner==live.controller or e.path(owner)==e.path(live.controller) then return hud end
                elseif e.valid(controllerWorld) then
                    local hudWorld=call(hud,'GetWorld')
                    if e.valid(hudWorld) and (hudWorld==controllerWorld
                        or e.path(hudWorld)==e.path(controllerWorld)) then
                        count=count+1;worldCandidate=hud
                    end
                end
            end
        end
        if count==1 then return worldCandidate end
    end
    local function wanted(playerInput,contexts)
        local allowed={};for _,name in ipairs(contexts) do allowed[name]=true end
        local result,natives={},{}
        local walked=e.each(playerInput.AppliedInputContexts,function(candidate,priority)
            local name=e.full(candidate) or ''
            for logical,native in pairs(Context.native) do
                -- IMC_Base carries keys usable in every gameplay context.
                if (allowed[logical] or logical=='base') and name:find(native..'.',1,true) then
                    result[logical]=tonumber(priority) or 0;natives[logical]=candidate
                end
            end
        end)
        -- MCC maps its keys into these applied game contexts.
        api.nativeContexts=natives
        -- Keys exist only inside an applied game context; without one MCC waits.
        if walked==false then return {} end
        return result
    end
    -- The one action among same-named candidates: the only one, or else the only one in
    -- the game's own input folder. Otherwise nil and why.
    local gameInput='/Game/_Dawnwalker/Player/Input/'
    local function gameAction(candidates)
        local distinct,seen={},{}
        for _,action in ipairs(candidates) do
            local key=e.path(action) or action
            if not seen[key] then seen[key]=true;distinct[#distinct+1]=action end
        end
        if #distinct==1 then return distinct[1] end
        if #distinct==0 then return nil end
        local preferred
        for _,action in ipairs(distinct) do
            if (e.path(action) or ''):sub(1,#gameInput)==gameInput then
                if preferred then return nil,'ambiguous: '..#distinct..' actions' end
                preferred=action
            end
        end
        if preferred then return preferred end
        return nil,'ambiguous: '..#distinct..' actions'
    end
    -- Native actions found once are reused while still valid and named the same, so a
    -- sync does not scan every InputAction again.
    local standardActions={}
    local function standardAction(actionName)
        if type(actionName)~='string' or actionName=='' then return nil end
        local cached=standardActions[actionName]
        if cached and e.valid(cached) and (e.full(cached) or ''):match('([^%.:/%s]+)$')==actionName then
            return cached
        end
        standardActions[actionName]=nil
        local nativeAction
        if actionName=='IA_Combat_ToggleQuickslots' and type(e.resolve)=='function' then
            nativeAction=e.resolve('/Game/_Dawnwalker/Player/Input/Actions/Combat/'
                ..'IA_Combat_ToggleQuickslots.IA_Combat_ToggleQuickslots')
        end
        if not e.valid(nativeAction) then
            local candidates={}
            for _,candidate in ipairs(e.all('InputAction')) do
                local name=(e.full(candidate) or ''):match('([^%.:/%s]+)$')
                if e.valid(candidate) and name==actionName then candidates[#candidates+1]=candidate end
            end
            local why
            nativeAction,why=gameAction(candidates)
            if why then return nil,'standard input action '..why..': '..actionName end
        end
        if not e.valid(nativeAction) then
            log.debug('Failed to resolve IA: ',actionName)
            return nil,'standard input action unavailable: '..actionName
        end
        log.trace('Resolved IA: ',actionName)
        standardActions[actionName]=nativeAction
        return nativeAction
    end
    local function standardKey(actionName,live)
        local nativeAction,why=standardAction(actionName)
        if not nativeAction then return nil,why end
        -- The player's key comes from the Settings key profile, which holds it
        -- whether or not an applied context maps the action.
        if type(e.profileKeys)~='function' then return nil,'key profile query unavailable: '..actionName end
        local ok,keys=pcall(e.profileKeys,live,nativeAction)
        if not ok then return nil,'key profile query failed: '..tostring(keys) end
        if keys==nil then return nil,'key profile unavailable: '..actionName end
        local found,listed={},{}
        local walked,walkWhy=e.each(keys,function(key)
            local keyName=nameString(property(key,'KeyName'))
            listed[#listed+1]=keyName or '<unreadable>'
            if keyName and keyName~='' and keyName~='None'
                and not keyName:find('^Gamepad_') then found[keyName]=true end
        end)
        if walked==false then return nil,'key profile array could not be read: '..tostring(walkWhy) end
        log.trace('Profile keys: ',actionName,' -> ',#listed>0 and table.concat(listed,', ') or '<none>')
        -- Every keyboard key the player bound to the action is attached.
        local result={}
        for keyName in pairs(found) do result[#result+1]=keyName end
        if #result==0 then return nil,'standard control binding unavailable: ' .. actionName end
        table.sort(result)
        return result,nil,nativeAction
    end
    -- Returns whether any inherited key changed, and the actions whose keys could not
    -- be resolved (action name -> reason). An unresolved action leaves only its own
    -- bindings without keys; every other binding still attaches.
    local function assignStandardKeys(plan,playerInput,live)
        local resolved,resolvedActions,changed,unresolved={},{},{false},{}
        local function resolve(actionName)
            if resolved[actionName]==nil then
                -- An error while resolving one action counts as unresolved, not a failed sync.
                local ok,keyNames,why,action=pcall(standardKey,actionName,live)
                if not ok then keyNames,why=nil,'key resolution failed: '..tostring(keyNames) end
                if not keyNames then
                    resolved[actionName]=false;unresolved[actionName]=tostring(why)
                else
                    resolved[actionName]=keyNames
                    resolvedActions[actionName]=action
                end
            end
            return resolved[actionName] or nil
        end
        local function same(a,b)
            if not a or #a~=#b then return false end
            for i,name in ipairs(b) do if a[i]~=name then return false end end
            return true
        end
        for _,binding in ipairs(plan.bindings) do
            local actionName=binding.standardAction
                or binding.holdSwapEdge and plan.holdSwap and plan.holdSwap.sourceAction
            if actionName then
                local keyNames=resolve(actionName)
                if not keyNames then
                    -- No key to inherit: this binding maps nothing until one resolves.
                    if binding.keyNames~=nil then changed[1]=true;binding.keyNames=nil end
                    binding.unresolved=true
                elseif not same(binding.keyNames,keyNames) then
                    changed[1]=true;binding.keyNames={table.unpack(keyNames)}
                end
                if keyNames then binding.unresolved=nil end
            end
        end
        -- A player key bound on one of the swap's inherited keys takes that key
        -- over: the swap steps aside on it rather than firing alongside it. Key names
        -- compare without regard to case, as the engine compares them.
        local claimed={}
        for _,binding in ipairs(plan.bindings) do
            if not binding.swap and binding.keyName then
                claimed[binding.keyName:lower()]=binding.id
            end
        end
        for _,binding in ipairs(plan.bindings) do
            if binding.swap then
                local suppressed=nil
                for _,keyName in ipairs(binding.keyNames or {}) do
                    local owner=claimed[keyName:lower()]
                    if owner then suppressed=suppressed or {};suppressed[keyName]=owner end
                end
                local previous=binding.suppressed or {}
                local differs=false
                for keyName,owner in pairs(suppressed or {}) do if previous[keyName]~=owner then differs=true end end
                for keyName in pairs(previous) do if not (suppressed and suppressed[keyName]) then differs=true end end
                if differs then
                    changed[1]=true;binding.suppressed=suppressed
                    for keyName,owner in pairs(suppressed or {}) do
                        log.info('swap steps aside on ',keyName,' for ',owner)
                    end
                end
            end
        end
        return changed[1],unresolved
    end
    -- Report each unresolved inherited key once, and again only when its reason changes.
    local function reportUnresolved(unresolved)
        local previous=api.unresolved or {}
        for actionName,why in pairs(unresolved) do
            if previous[actionName]~=why then
                log.warn('inherited key unavailable; skipping its bindings: ',actionName,' (',why,')')
            end
        end
        for actionName in pairs(previous) do
            if not unresolved[actionName] then log.info('inherited key resolved: ',actionName) end
        end
        api.unresolved=next(unresolved) and unresolved or nil
    end
    local function invalidate()
        api.generation=api.generation+1
        api.ready=false
        api.retryStep=0
        if type(Quickslots.cancel)=='function' then
            pcall(Quickslots.cancel,api.state,service)
        else api.state={selectedGroup=api.state.selectedGroup} end
        if type(service.invalidate)=='function' then pcall(service.invalidate,service) end
    end
    local function retire(clearPlan,mandatory)
        local wasCleanupPending=api.phase=='cleanup-pending'
        if not mandatory and api.ready and api.playerInput then
            local ok,why=pcall(overrides.restoreAll,overrides,api.playerInput)
            if not ok then return false,'override restoration failed: ' .. tostring(why),
                {status='failure',original=why} end
        end
        invalidate()
        api.phase='retiring'
        local errors={}
        if (mandatory or wasCleanupPending) and api.playerInput then
            local ok,why=pcall(overrides.restoreAll,overrides,api.playerInput)
            if not ok then errors[#errors+1]='override restoration: ' .. tostring(why) end
        end
        local detached,detachWhy=pcall(function() return internal(function() return context:detachAll() end) end)
        if not detached then errors[#errors+1]='mapping detach: ' .. tostring(detachWhy)
        elseif detachWhy==false then errors[#errors+1]='mapping detach incomplete' end
        local restored,complete=pcall(indicators.restoreAll,indicators)
        if not restored then errors[#errors+1]='indicator restoration: ' .. tostring(complete)
        elseif complete==false then errors[#errors+1]='indicator restoration incomplete' end
        if callbacks then
            local closed,why=callbacks:close()
            if not closed then errors[#errors+1]='callback close: ' .. tostring(why) end
        end
        api.active={}
        if #errors>0 then
            api.phase='cleanup-pending'
            return false,table.concat(errors,'; '),{status='failure',cleanup=errors}
        end
        api.phase='pending'
        api.owner=nil;api.componentPath=nil
        api.playerInput=nil;api.actions=nil;api.overrideTargets=nil;api.overrideWanted=nil
        api.missingOverride=nil
        if clearPlan then api.enabled=false;api.plan=nil end
        return true
    end
    -- An override that names several actions skips only itself; the rest still apply.
    local function resolveTargets(plan)
        local targets,selected,found,seen={},{},{},{}
        for _,action in ipairs(e.all('InputAction')) do
            if e.valid(action) then
                local name=(e.full(action) or ''):match('([^%.:/%s]+)$')
                if name and plan.overrides[name] then
                    found[name]=found[name] or {}
                    table.insert(found[name],action)
                end
                local actionPath=e.path(action)
                if actionPath and not seen[actionPath] then
                    local adopted=false
                    e.each(action.Triggers or {},function(first,second)
                        local trigger=e.unwrap(first)
                        if not e.valid(trigger) then trigger=e.unwrap(second) end
                        if e.valid(trigger) and e.path(trigger)==actionPath .. ':MCC_OverrideChord' then
                            adopted=true
                        end
                    end)
                    if adopted then targets[#targets+1]=action;seen[actionPath]=true end
                end
            end
        end
        local missing={}
        for name in pairs(plan.overrides) do
            local action,why=gameAction(found[name] or {})
            if not action then
                missing[#missing+1]=why and name..' ('..why..')' or name
            else
                local path=e.path(action)
                if not seen[path] then targets[#targets+1]=action;seen[path]=true end
                selected[path]=true
            end
        end
        table.sort(missing)
        return targets,selected,missing
    end
    local function bindOwner(live)
        if type(service.bind)=='function' then
            live.hud=ownerHud(live)
            local ok,why=service:bind(live,api.generation)
            if ok==false then log.debug('quickslot HUD pending: ',why) end
        end
    end
    -- Indicators are updated at the points where MCC knows they may be stale,
    -- never from widget hooks.
    local function updateIndicators(force)
        local ok,complete,count,expected=pcall(indicators.refresh,indicators,api.actions,api.plan,
            {revision=api.generation,force=force==true})
        if not ok then log.warn('key indicator update failed: ',complete);return false end
        if complete or (expected or count or 0)==0 then return true end
        log.debug('key indicators updated partially: ',count,'/',expected)
        return false
    end
    local function doSync(force,beforeRebuild)
        if api.phase=='stopped' then return false,'controls stopped',{status='failure'} end
        if api.phase=='cleanup-pending' then
            local cleared,why,detail=retire(false,true)
            if not cleared then return false,why,detail end
        end
        if not api.enabled or not api.plan then return false,'controls disabled',{status='pending'} end
        local callbackOwner,bridgeWhy=resolveBridge()
        if not callbackOwner then
            if api.ready or api.owner then
                local cleared,why,detail=retire(false,true)
                if not cleared then return false,why,detail end
            end
            return false,bridgeWhy,{status='pending'}
        end
        local live=stack()
        if not live then
            if api.ready or api.owner then
                local cleared,why,detail=retire(false,true)
                if not cleared then return false,why,detail end
            end
            return false,'gameplay Enhanced Input stack unavailable',{status='pending'}
        end
        if api.owner and not sameOwner(api.owner,live) then
            local cleared,why,detail=retire(false,true)
            if not cleared then return false,why,detail end
        end
        local desired=wanted(live.playerInput,api.plan.contexts)
        if not next(desired) then
            if api.ready or api.owner then
                local cleared,why,detail=retire(false,true)
                if not cleared then return false,why,detail end
            end
            return false,'native gameplay context unavailable',{status='pending'}
        end
        -- An inherited key that cannot be resolved skips only its own bindings; the rest
        -- attach, and the key is resolved again on every later sync.
        local resolved,unresolved=assignStandardKeys(api.plan,live.playerInput,live)
        reportUnresolved(unresolved)
        local standardKeyChanged=api.ready and resolved
        local targets,selected
        local contextChanged=false
        for logical,priority in pairs(desired) do
            if api.active[logical]~=priority then contextChanged=true;break end
        end
        if not contextChanged then
            for logical in pairs(api.active) do
                if desired[logical]==nil then contextChanged=true;break end
            end
        end
        local reuse=api.ready and not (api.missingOverride and contextChanged)
        if reuse then
            -- A native action unloaded or replaced since is resolved again; it never
            -- retires the rest of MCC input.
            for _,target in ipairs(api.overrideTargets or {}) do
                if not e.valid(target) then
                    log.info('override target lost; resolving overrides again')
                    reuse=false;break
                end
            end
        end
        if reuse then
            targets,selected=api.overrideTargets,api.overrideWanted
        else
            local ok,a,b,c=pcall(resolveTargets,api.plan)
            if not ok then return false,a,{status='pending',original=a} end
            targets,selected=a,b
            api.overrideTargets,api.overrideWanted=a,b
            api.missingOverride=#c>0
            -- Reported once, and again only when the skipped set changes.
            local skipped=table.concat(c,', ')
            if skipped~=reportedMissing then
                if api.missingOverride then log.warn('override actions unavailable; skipping: ',skipped)
                elseif reportedMissing then log.info('override actions available') end
                reportedMissing=skipped~='' and skipped or nil
            end
        end
        if not api.ready then
            api.phase='attaching';api.owner=live;api.playerInput=live.playerInput
            local actions=context:configure(api.plan)
            local generation=api.generation+1
            api.generation=generation
            local installed,why=callbackOwner:install(live.componentPath,actions,api.plan,function(binding,phase,event)
                if api.phase~='ready' or api.generation~=generation then return end
                local function deliver()
                    if api.phase=='ready' and api.generation==generation then
                        local ok,result=pcall(Quickslots.deliver,api.state,binding,phase,service)
                        if not ok or result==false then
                            log.warn('input callback failed: ',binding.id,' ',phase,': ',ok and 'not handled' or result)
                        end
                    end
                end
                -- A wheel change applies within the input frame, so a native slot action
                -- on the same key sees the new focus. Other work waits for the queue.
                local kind=binding.action and binding.action.type
                if (kind=='focus' or kind=='flip') and type(e.inGameThread)=='function' then
                    local onThread,current=pcall(e.inGameThread)
                    if onThread and current==true then return deliver() end
                end
                local queued,queueWhy=pcall(queue,deliver)
                if not queued or queueWhy==false then
                    log.error('input callback queue failed: ',queueWhy)
                end
            end)
            if not installed then
                local cleared,cleanupWhy=retire(false,true)
                return false,cleared and why or tostring(why) .. '; cleanup: ' .. tostring(cleanupWhy),
                    {status='failure',original=why,cleanup=cleanupWhy}
            end
            api.actions=actions;api.componentPath=live.componentPath
        elseif standardKeyChanged or beforeRebuild then
            api.actions=context:configure(api.plan)
            if not beforeRebuild and type(e.rebuild)=='function' then e.rebuild(live.playerInput) end
        end
        local remapped=false
        for logical in pairs(api.active) do
            if desired[logical]==nil or desired[logical]~=api.active[logical]
                or not context:attached(logical,live.playerInput) then
                internal(function() context:detach(logical) end)
                api.active[logical]=nil;remapped=true
            end
        end
        for logical,priority in pairs(desired) do
            if api.active[logical]==nil then
                local native=api.nativeContexts and api.nativeContexts[logical]
                internal(function() context:attach(logical,live.subsystem,priority,native) end)
                api.active[logical]=priority;remapped=true
            end
        end
        -- Changing an applied context's mappings takes effect on the next control
        -- mapping rebuild; a pending game rebuild picks the change up by itself.
        if remapped and not beforeRebuild and type(e.rebuild)=='function' then e.rebuild(live.playerInput) end
        overrides:apply(selected,live.playerInput,targets)
        if api.phase=='attaching' then
            api.phase='ready';api.ready=true
            log.info('controls attached to player input')
        end
        bindOwner(live)
        if type(Quickslots.reconcile)=='function' then pcall(Quickslots.reconcile,api.state,service) end
        updateIndicators(force)
        return true
    end
    local queuedPlan
    local operation
    -- An Apply that arrives while another operation runs is kept, and applied on the
    -- next game-thread turn once that operation has returned.
    local function operate(callback)
        local results=table.pack(operation(callback))
        if queuedPlan and not busy and api.phase~='stopped' then
            local plan=queuedPlan;queuedPlan=nil
            local ok,why=pcall(queue,function()
                local active,reason=api:apply(plan)
                if not active then log.debug('queued Apply pending: ',reason) end
            end)
            if not ok or why==false then log.error('queued Apply failed to schedule: ',why) end
        end
        return table.unpack(results,1,results.n)
    end
    operation=function(callback)
        if busy then pendingWake=true;return false,'lifecycle operation pending',{status='pending'} end
        busy=true
        local ok,active,why,detail=pcall(callback)
        busy=false
        if not ok then
            pendingWake=false
            local original=active
            if api.phase=='attaching' or api.phase=='ready' then
                local cleared,cleanupWhy=retire(false,true)
                return false,tostring(original) .. (cleared and '' or '; cleanup: ' .. tostring(cleanupWhy)),
                    {status='failure',original=original,cleanup=cleanupWhy}
            end
            return false,tostring(original),{status='failure',original=original}
        end
        if pendingWake and api.phase~='stopped' then
            pendingWake=false
            if wake then wake() end
        end
        if active then api.retryStep=0
        elseif detail and detail.status=='pending' and scheduleRetry then scheduleRetry() end
        return active,why,detail
    end
    function api:sync() return operate(function() return doSync(false) end) end
    function api:apply(plan)
        if busy then
            queuedPlan=plan
            log.info('Apply queued behind a running input operation')
            return false,'Apply queued',{status='pending'}
        end
        return operate(function()
            if api.phase=='stopped' then return false,'controls stopped',{status='failure'} end
            assert(type(plan)=='table' and type(plan.bindings)=='table','validated plan required')
            if api.ready then
                local ok,why=pcall(resolveTargets,plan)
                if not ok then return false,why,{status='failure',original=why} end
            end
            -- Activating Default is an action: retire resets to the new Default,
            -- and the next presentation publishes it if it was not yet shown.
            local defaultGroup=plan.defaultGroup
            local previousDefault=api.state.defaultGroup
            api.state.defaultGroup=defaultGroup
            local cleared,why,detail=retire(false,false)
            if not cleared then api.state.defaultGroup=previousDefault;return false,why,detail end
            api.plan,api.enabled,api.state=plan,true,{selectedGroup=api.state.selectedGroup,
                pendingGroup=defaultGroup,defaultGroup=defaultGroup}
            return doSync(true)
        end)
    end
    -- Deactivating or stopping supersedes an Apply still queued.
    function api:deactivate()
        return operate(function() queuedPlan=nil;return retire(true,false) end)
    end
    function api:updateIndicators(force)
        if busy or api.phase~='ready' then return false end
        return updateIndicators(force)
    end

    -- While enabled but not attached, a sync is retried after 100 ms, 500 ms and then
    -- every 3 s, so attaching never depends on a later game hook alone. One retry is
    -- scheduled at a time.
    local retryArmed=false
    scheduleRetry=function()
        if type(e.delay)~='function' or not api.enabled or api.phase=='stopped' or retryArmed then return end
        local step=(api.retryStep or 0)+1
        api.retryStep=step
        local ms=step==1 and 100 or step==2 and 500 or 3000
        retryArmed=true
        local ok,result=pcall(e.delay,ms,function()
            retryArmed=false
            if api.phase=='stopped' or not api.enabled or api.ready then return end
            wake()
        end)
        if not ok or result==false then
            retryArmed=false
            log.warn('lifecycle retry registration failed: ',result)
        end
    end

    wake=function(source)
        if api.phase=='stopped' or not api.enabled then return end
        if internalDepth>0 and source=='mapping' then return end
        if busy then pendingWake=true;return end
        if wakeQueued then return end
        wakeQueued=true
        local ok,why=pcall(queue,function()
            wakeQueued=false
            if api.phase=='stopped' then return end
            local active,reason=api:sync()
            if active then lastPending=nil
            elseif reason~=lastPending and reason~='gameplay Enhanced Input stack unavailable' then
                log.debug('lifecycle sync pending: ',reason)
                lastPending=reason
            end
        end)
        if not ok or why==false then
            wakeQueued=false;log.error('lifecycle wake failed: ',why)
        end
    end
    local function register(kind,name,callback)
        local method=e[kind]
        if type(method)~='function' then return end
        local ok,id,second=pcall(method,name,callback)
        if not ok or id==false or ((kind=='hook' or kind=='preHook') and
            (type(id)~='number' or id%1~=0 or type(second)~='number' or second%1~=0)) then
            log.warn('lifecycle ',kind,' registration failed: ',name,': ',id)
        elseif kind=='hook' or kind=='preHook' then
            registrations[#registrations+1]={id=id,second=second,name=name}
        end
    end
    -- Updates indicators on the next game-thread turn, once the current change
    -- has completed. Requests made before it runs share it.
    local function queueIndicators()
        if indicatorsQueued or api.phase=='stopped' then return end
        indicatorsQueued=true
        local ok,why=pcall(queue,function()
            indicatorsQueued=false
            api:updateIndicators()
        end)
        if not ok or why==false then
            indicatorsQueued=false;log.warn('indicator update failed to queue: ',why)
        end
    end
    if e.preHook then
        register('preHook',
            '/Script/EnhancedInput.EnhancedInputSubsystemInterface:RequestRebuildControlMappings',
            function(caller)
                -- Execute inline: queuing this work would miss a forced rebuild.
                -- Nested requests from configure/attach/overrides are already
                -- covered by the outer operation and must not schedule another.
                if busy or internalDepth>0 or not api.enabled or api.phase=='stopped' then return end
                local subsystem=e.unwrap(caller)
                local live=api.owner or stack()
                if not live or not e.valid(subsystem) or not e.valid(live.subsystem)
                    or e.path(subsystem)~=e.path(live.subsystem) then return end
                local active,why=operate(function() return doSync(false,true) end)
                if active then
                    log.debug('MCC mappings prepared before control mapping rebuild')
                    -- The rebuild runs after this pre-hook returns.
                    queueIndicators()
                elseif why~=lastPending then
                    log.debug('pre-rebuild sync pending: ',why)
                    lastPending=why
                end
            end)
    end
    if e.hook then
        for _,name in ipairs({
            '/Script/EnhancedInput.EnhancedInputSubsystemInterface:AddMappingContext',
            '/Script/EnhancedInput.EnhancedInputSubsystemInterface:RemoveMappingContext',
            '/Script/EnhancedInput.EnhancedInputSubsystemInterface:ClearAllMappings',
            '/Script/Engine.PlayerController:ClientRestart',
            '/Script/Engine.PlayerController:ClientRetryClientRestart',
            '/Script/Engine.Controller:OnRep_Pawn',
            '/Script/RebelInput.RebelInputMappingSubsystem:ApplyPendingKeyboardMappings',
        }) do
            local source=name:find('EnhancedInputSubsystemInterface',1,true)
                and 'mapping' or 'external'
            register('hook',name,function() wake(source) end)
        end
    end
    if e.notify then
        for _,name in ipairs({
            '/Script/Engine.PlayerController',
            '/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem',
            '/Script/EnhancedInput.EnhancedInputComponent',
            '/Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C',
            '/Game/_Dawnwalker/UI/_Unified/ActiveAbilities/WBP_AA_Quickslots.WBP_AA_Quickslots_C',
            '/Game/_Dawnwalker/UI/_Unified/HUD/Quickslots/WBP_HUD_Quickslots.WBP_HUD_Quickslots_C',
        }) do register('notify',name,wake) end
        -- Each Bindings widget owns its wheel's four key indicators, which exist
        -- once its construction has returned.
        for _,name in ipairs({
            '/Game/_Dawnwalker/UI/_Unified/ActiveAbilities/WBP_AA_Quickslots_Bindings.WBP_AA_Quickslots_Bindings_C',
            '/Game/_Dawnwalker/UI/_Unified/HUD/Quickslots/WBP_HUD_Quickslots_Bindings.WBP_HUD_Quickslots_Bindings_C',
        }) do register('notify',name,queueIndicators) end
    end
    function api:stop()
        return operate(function()
            queuedPlan=nil
            api.enabled=false
            local cleared,why,detail=retire(true,true)
            if not cleared then return false,why,detail end
            api.phase='stopped';api.enabled=false
            local remaining,errors={},{}
            for _,entry in ipairs(registrations) do
                if type(e.unhook)~='function' then
                    remaining[#remaining+1]=entry
                    errors[#errors+1]=entry.name .. ': UnregisterHook unavailable'
                else
                    local ok,result,detail=pcall(e.unhook,entry.name,entry.id,entry.second)
                    if not ok or result==false then
                        remaining[#remaining+1]=entry
                        errors[#errors+1]=entry.name .. ': ' .. tostring(ok and detail or result)
                    end
                end
            end
            registrations=remaining
            if #errors>0 then return false,table.concat(errors,'; '),{status='failure'} end
            return true
        end)
    end
    return api
end

return M
