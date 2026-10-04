-- Discover the live player input stack, own MCC mappings, and retire stale callbacks.
local Context=require('mc_input_context')
local Callbacks=require('mc_native_callbacks')
local Quickslots=require('mc_quickslots')
local KeyIndicators=require('mc_key_indicators')
local Overrides=require('mc_overrides')
local Events=require('mc_events')
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
        runtimeKeys=function(live,action)
            return live.subsystem:QueryKeysMappedToAction(action)
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
        initialize=function(action)
            local library=assert(StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'))
            library:Conv_ObjectToSoftObjectReference(action)
        end,
        trigger=function(action,className) return StaticConstructObject(cls(className),action,0,0x40) end,
        options={bIgnoreAllPressedKeysUntilRelease=true,bForceImmediately=false,bNotifyUserSettings=false},
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
        mapHook=rawget(_G,'RegisterLoadMapPostHook'),
        preMapHook=rawget(_G,'RegisterLoadMapPreHook'),
        unhook=rawget(_G,'UnregisterHook'),
        delay=rawget(_G,'ExecuteWithDelay'),
    }
end

function M.new(queue,log,service,environment)
    assert(type(queue)=='function','game-thread queue required')
    log=log or function() end
    local api
    local publishControl=Events.publisher(rawget(_G,'ModRef'))
    service=service or Quickslots.new({emit=function(name,payload)
        local ok,why=pcall(publishControl,name,payload,api and api.owner)
        if not ok or why==false then
            log('control event publication failed: '..tostring(why))
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
    local wake,scheduleRetry
    local registrations={}
    local lastPending
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
        if walked==false then return {} end
        -- Keys exist only inside an applied game context; without one MCC waits.
        if next(result) then api.nativeSeen=true end
        return result
    end
    local function standardAction(actionName)
        if type(actionName)~='string' or actionName=='' then return nil end
        log('Resolving IA: '..actionName)
        local nativeAction
        if actionName=='IA_Combat_ToggleQuickslots' and type(e.resolve)=='function' then
            nativeAction=e.resolve('/Game/_Dawnwalker/Player/Input/Actions/Combat/'
                ..'IA_Combat_ToggleQuickslots.IA_Combat_ToggleQuickslots')
        end
        if not e.valid(nativeAction) then
            nativeAction=nil
            for _,candidate in ipairs(e.all('InputAction')) do
                local name=(e.full(candidate) or ''):match('([^%.:/%s]+)$')
                if e.valid(candidate) and name==actionName then
                    if nativeAction then return nil,'ambiguous standard input action: '..actionName end
                    nativeAction=candidate
                end
            end
        end
        if not e.valid(nativeAction) then
            log('IA resolution failed: '..actionName)
            return nil,'standard input action unavailable: '..actionName
        end
        log('Resolved IA: '..tostring(e.path(nativeAction)))
        return nativeAction
    end
    local function standardKey(actionName,live)
        local nativeAction,why=standardAction(actionName)
        if not nativeAction then return nil,why end
        local found={}
        if type(e.runtimeKeys)~='function' then return nil,'runtime key query unavailable: '..actionName end
        -- Query the same player's subsystem used for callback/context attachment.
        -- Raw IMC keys can be None while this query returns the resolved binding.
        log('Finding keys: '..actionName..' on '..tostring(e.path(live.subsystem)))
        local ok,keys=pcall(e.runtimeKeys,live,nativeAction)
        if not ok then return nil,'runtime key query failed: '..tostring(keys) end
        if keys==nil then return nil,'runtime key query returned nil: '..actionName end
        local queriedKeys={}
        local walked,walkWhy=e.each(keys,function(key)
            local keyName=nameString(property(key,'KeyName'))
            queriedKeys[#queriedKeys+1]=keyName or '<unreadable>'
            if keyName and keyName~='' and keyName~='None'
                and not keyName:find('^Gamepad_') then found[keyName]=true end
        end)
        if walked==false then return nil,'runtime key query array could not be read: '..tostring(walkWhy) end
        log('Keys found: '..actionName..' -> '
            ..(#queriedKeys>0 and table.concat(queriedKeys,', ') or '<none>'))
        if next(found)==nil and type(e.profileKeys)=='function' then
            local okProfile,profileKeys=pcall(e.profileKeys,live,nativeAction)
            if okProfile and profileKeys~=nil then
                local fromProfile={}
                e.each(profileKeys,function(key)
                    local keyName=nameString(property(key,'KeyName'))
                    fromProfile[#fromProfile+1]=keyName or '<unreadable>'
                    if keyName and keyName~='' and keyName~='None'
                        and not keyName:find('^Gamepad_') then found[keyName]=true end
                end)
                log('Profile keys: '..actionName..' -> '
                    ..(#fromProfile>0 and table.concat(fromProfile,', ') or '<none>'))
            elseif not okProfile then
                log('profile key query failed: '..tostring(profileKeys))
            end
        end
        local result
        for keyName in pairs(found) do
            if result and result~=keyName then
                return nil,'multiple standard keyboard bindings for ' .. actionName
            end
            result=keyName
        end
        if result then return result,nil,nativeAction end
        return nil,'standard control binding unavailable: ' .. actionName
    end
    local function assignStandardKeys(plan,playerInput,live)
        local resolved,resolvedActions,changed={},{},{false}
        local function resolve(actionName)
            if not resolved[actionName] then
                local keyName,why,action=standardKey(actionName,live)
                if not keyName then return nil,why end
                resolved[actionName]=keyName
                resolvedActions[actionName]=action
            end
            return resolved[actionName]
        end
        for _,binding in ipairs(plan.bindings) do
            local actionName=binding.standardAction
                or binding.holdSwapEdge and plan.holdSwap and plan.holdSwap.sourceAction
            if actionName then
                local keyName,why=resolve(actionName)
                if not keyName then return nil,why end
                if binding.keyName~=keyName then changed[1]=true;binding.keyName=keyName end
            end
        end
        return changed[1]
    end
    local function invalidate()
        api.generation=api.generation+1
        api.ready=false
        api.retryStep=0;api.retryToken=(api.retryToken or 0)+1
        if type(Quickslots.cancel)=='function' then
            pcall(Quickslots.cancel,api.state,service)
        else api.state={selectedGroup=api.state.selectedGroup} end
        if type(service.invalidate)=='function' then pcall(service.invalidate,service) end
    end
    local function retire(clearPlan,mandatory,resetNative)
        local wasCleanupPending=api.phase=='cleanup-pending'
        local retiredOwner=api.owner
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
        if not restored or complete==false then
            errors[#errors+1]='indicator restoration: ' .. tostring(restored and complete or complete)
        end
        if callbacks then
            local closed,why=callbacks:close()
            if not closed then errors[#errors+1]='callback close: ' .. tostring(why) end
        end
        api.active={}
        if #errors>0 then
            api.phase='cleanup-pending'
            return false,table.concat(errors,'; '),{status='failure',cleanup=errors}
        end
        api.phase=clearPlan and 'pending' or 'pending'
        api.owner=nil;api.lastOwner=resetNative and nil or (retiredOwner or api.lastOwner)
        api.componentPath=nil;api.subsystem=nil
        api.playerInput=nil;api.actions=nil;api.overrideTargets=nil;api.overrideWanted=nil
        api.missingOverride=nil;api.swapKeyName=nil
        if resetNative or clearPlan then api.nativeSeen=nil end
        if clearPlan then api.enabled=false;api.plan=nil end
        return true
    end
    local function resolveTargets(plan)
        local targets,selected,found,seen={},{},{},{}
        for _,action in ipairs(e.all('InputAction')) do
            if e.valid(action) then
                local name=(e.full(action) or ''):match('([^%.:/%s]+)$')
                if name and plan.overrides[name] then
                    assert(not found[name] or found[name]==action,
                        'ambiguous override action: ' .. name)
                    found[name]=action
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
            local action=found[name]
            if not action then
                missing[#missing+1]=name
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
            if ok==false then log('quickslot HUD pending: ' .. tostring(why)) end
        end
    end
    local function refreshIndicators(force)
        local ok,complete,count,expected=pcall(indicators.refresh,indicators,api.actions,api.plan,
            {revision=api.generation,force=force==true})
        if not ok then log('key indicator update failed: ' .. tostring(complete))
        elseif not complete and (expected or count or 0)>0 then
            log('key indicators updated partially: ' .. tostring(count) .. '/' .. tostring(expected))
        end
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
                local cleared,why,detail=retire(false,true,true)
                if not cleared then return false,why,detail end
            end
            return false,'gameplay Enhanced Input stack unavailable',{status='pending'}
        end
        if api.owner and not sameOwner(api.owner,live) then
            local cleared,why,detail=retire(false,true,true)
            if not cleared then return false,why,detail end
        end
        if not api.owner and api.lastOwner and not sameOwner(api.lastOwner,live) then
            api.nativeSeen=nil;api.lastOwner=nil
        end
        local desired=wanted(live.playerInput,api.plan.contexts)
        if not next(desired) then
            if api.ready or api.owner then
                local cleared,why,detail=retire(false,true)
                if not cleared then return false,why,detail end
            end
            return false,'native gameplay context unavailable',{status='pending'}
        end
        local standardKeyChanged=false
        local resolved,standardWhy=assignStandardKeys(api.plan,live.playerInput,live)
        if resolved==nil then return false,standardWhy,{status='pending'} end
        standardKeyChanged=api.ready and resolved
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
        if api.ready and not (api.missingOverride and contextChanged) then
            targets,selected=api.overrideTargets,api.overrideWanted
        else
            local ok,a,b,c=pcall(resolveTargets,api.plan)
            if not ok then return false,a,{status='pending',original=a} end
            targets,selected=a,b
            api.overrideTargets,api.overrideWanted=a,b
            api.missingOverride=#c>0
            if api.missingOverride then
                log('override actions unavailable; skipping: ' .. table.concat(c,', '))
            end
        end
        if not api.ready then
            api.phase='attaching';api.owner=live;api.playerInput=live.playerInput
            local actions=context:configure(api.plan)
            local generation=api.generation+1
            api.generation=generation
            local installed,why=callbackOwner:install(live.componentPath,actions,api.plan,function(binding,phase,event)
                if api.phase~='ready' or api.generation~=generation then return end
                local queued,queueWhy=pcall(queue,function()
                    if api.phase=='ready' and api.generation==generation then
                        local ok,result=pcall(Quickslots.deliver,api.state,binding,phase,service)
                        if not ok or result==false then log('input callback failed: ' .. tostring(result)) end
                    end
                end)
                if not queued or queueWhy==false then
                    log('input callback queue failed: ' .. tostring(queueWhy))
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
        for _,target in ipairs(targets or {}) do
            assert(e.valid(target),'override target owner was lost')
        end
        overrides:apply(selected,live.playerInput,targets)
        if api.phase=='attaching' then
            api.phase='ready';api.ready=true
            log('controls attached to player input')
        end
        bindOwner(live)
        if type(Quickslots.reconcile)=='function' then pcall(Quickslots.reconcile,api.state,service) end
        refreshIndicators(force)
        return true
    end
    local function operate(callback)
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
        if active then api.retryStep=0;api.retryToken=(api.retryToken or 0)+1
        elseif detail and detail.status=='pending' and scheduleRetry then scheduleRetry() end
        return active,why,detail
    end
    function api:sync() return operate(function() return doSync(false) end) end
    function api:apply(plan)
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
    function api:deactivate() return operate(function() return retire(true,false) end) end

    scheduleRetry=function()
        if type(e.delay)~='function' or not api.enabled or api.phase=='stopped' then return end
        local step=api.retryStep or 0
        if step>=2 then return end
        step=step+1;api.retryStep=step
        local token=api.retryToken or 0
        local ms=step==1 and 100 or 500
        local ok,result=pcall(e.delay,ms,function()
            if api.phase=='stopped' or not api.enabled or api.ready
                or (api.retryToken or 0)~=token then return end
            wake()
        end)
        if not ok or result==false then
            log('lifecycle retry registration failed: ' .. tostring(result))
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
                log('lifecycle sync pending: ' .. tostring(reason))
                lastPending=reason
            end
        end)
        if not ok or why==false then
            wakeQueued=false;log('lifecycle wake failed: ' .. tostring(why))
        end
    end
    local function register(kind,name,callback)
        local method=e[kind]
        if type(method)~='function' then return end
        local ok,id,second=pcall(method,name,callback)
        if not ok or id==false or ((kind=='hook' or kind=='preHook') and
            (type(id)~='number' or id%1~=0 or type(second)~='number' or second%1~=0)) then
            log('lifecycle ' .. kind .. ' registration failed: ' .. name .. ': ' .. tostring(id))
        elseif kind=='hook' or kind=='preHook' then
            registrations[#registrations+1]={id=id,second=second,name=name}
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
                    log('MCC mappings prepared before control mapping rebuild')
                elseif why~=lastPending then
                    log('pre-rebuild sync pending: '..tostring(why))
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
    end
    if e.hook then
        register('hook','/Script/UMG.PanelWidget:AddChild',function(parent)
            local name=e.full(e.unwrap(parent)) or ''
            if name:find('Quickslots',1,true) then wake() end
        end)
    end
    if type(e.mapHook)=='function' then
        local ok,id=pcall(e.mapHook,wake)
        if not ok or id==false then log('lifecycle map post-hook registration failed: ' .. tostring(id)) end
    end
    if type(e.preMapHook)=='function' then
        local ok,id=pcall(e.preMapHook,function()
            if api.phase~='stopped' then
                local cleared,why=retire(false,true,true)
                if not cleared then log('pre-map cleanup pending: ' .. tostring(why)) end
            end
        end)
        if not ok or id==false then log('lifecycle map pre-hook registration failed: ' .. tostring(id)) end
    end
    function api:stop()
        return operate(function()
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
