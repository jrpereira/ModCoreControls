-- Own generated Enhanced Input actions and map their keys into the game's own
-- gameplay contexts. A plan's contexts name where its keys can be used; MCC
-- never creates or applies a mapping context of its own.
local M={}
-- The game's mapping context for each logical context. IMC_Base stays applied
-- across gameplay, so keys usable everywhere go there and survive transitions
-- between open world and combat.
M.native={exploration='IMC_OW',combat='IMC_RTCombat',base='IMC_Base'}
local gameplay={'exploration','combat'}
-- The generated Input Action name for a runtime binding id. mc_menu rejects
-- declarations whose names would collide.
function M.actionName(id)
    return 'IA_MCC_' .. (id:gsub('[^%w]','_'))
end
-- Key names compare as the engine compares them: without regard to case.
local function keyId(name) return string.lower(tostring(name)) end

function M.new(e,log)
    log=require('mc_log').wrap(log)
    local Lifetimes=require('mc_lifetimes')
    local keep,live=e.keep or Lifetimes.keep,e.live or Lifetimes.live
    -- MCC's own actions are root-captured, so they never die while kept.
    local actions={}
    -- attached[logical]={context=<weak handle of the native IMC>,entries={{action,keyName},...}}
    local attached={}
    local plan,current
    -- Bindings or keys that failed, keyed by binding id or 'id key'; each is
    -- reported once, and again only when its reason changes.
    local failed={}
    local function report(id,why)
        if failed[id]~=why then log.warn('skipping input ',id,': ',why) end
        failed[id]=why
    end
    local api={}
    local function action(binding)
        local id=M.actionName(binding.id)
        if not e.valid(actions[binding.id]) then
            actions[binding.id]=e.retain('InputAction',id)
            assert(e.valid(actions[binding.id]),'Input Action unavailable: ' .. id)
            e.initialize(actions[binding.id])
        end
        return actions[binding.id]
    end
    local function trigger(target,mode)
        if mode==2 then target.Triggers={}; return end
        local className=mode==1 and 'InputTriggerHold'
            or mode==3 and 'InputTriggerPressed'
            or mode==4 and 'InputTriggerReleased'
            or mode==0 and 'InputTriggerTap' or nil
        assert(className,'unsupported input trigger mode: '..tostring(mode))
        local result=e.trigger(target,className)
        assert(e.valid(result),'input trigger unavailable')
        if mode==1 then result.HoldTimeThreshold=e.threshold or .2;result.bIsOneShot=true
        elseif mode==0 then result.TapReleaseTimeThreshold=e.threshold or .2 end
        target.Triggers={result}
    end
    -- MCC keys an earlier Lua state mapped into this context (before a mod restart or
    -- hot reload) are still there under the same actions; remove them too.
    local function purge(context)
        local stale={}
        e.each(context.Mappings or {},function(entry)
            entry=e.unwrap(entry)
            local action=entry and e.unwrap(entry.Action)
            if e.valid(action) and (e.path(action) or ''):match('[%.:/]IA_MCC_[^%.:/]*$') then
                local key=entry.Key
                stale[#stale+1]={action,key and e.unwrap(key.KeyName)}
            end
        end)
        local removed=0
        for _,entry in ipairs(stale) do
            if pcall(function() context:UnmapKey(entry[1],{KeyName=entry[2]}) end) then removed=removed+1 end
        end
        if removed>0 then log.info('removed ',removed,' stale MCC key mapping(s) from ',e.path(context)) end
    end
    -- A context that died took MCC's mappings with it.
    local function unmap(record)
        local context=live(record.context)
        if context then
            for _,entry in ipairs(record.entries) do
                context:UnmapKey(entry[1],{KeyName=e.name(entry[2])})
            end
            purge(context)
        end
        record.entries={}
    end
    local function covers(binding,logical)
        for _,name in ipairs(binding.contexts or plan.contexts) do
            if name==logical then return true end
        end
        return false
    end
    -- A binding usable in every gameplay context lives in IMC_Base while that is
    -- applied; otherwise in each of its own contexts.
    local function usable(binding,logical)
        local everywhere=covers(binding,gameplay[1]) and covers(binding,gameplay[2])
        if logical=='base' then return everywhere end
        if everywhere and attached.base then return false end
        return covers(binding,logical)
    end
    local function map(logical)
        local record=attached[logical]
        unmap(record)
        local context=live(record.context)
        if not plan or not context then return end
        for _,binding in ipairs(plan.bindings) do
            local target=current[binding.id]
            if target and usable(binding,logical) then
                -- An inherited binding carries every key the player bound to its
                -- source action; a suppressed key is left to its claimant. A key
                -- that cannot be mapped skips only itself.
                for _,keyName in ipairs(binding.keyNames or {binding.keyName}) do
                    if not (binding.suppressed and binding.suppressed[keyName]) then
                        local id=binding.id..' '..tostring(keyName)
                        local ok,why=pcall(function()
                            -- A name the engine does not know would map a dead key.
                            if type(e.validKey)=='function' then
                                local checked,known=pcall(e.validKey,keyName)
                                if checked and known==false then error('unknown key name',0) end
                            end
                            context:MapKey(target,{KeyName=e.name(keyName)})
                        end)
                        if ok then
                            record.entries[#record.entries+1]={target,keyName}
                            if failed[id] then log.info('input key mapped: ',id) end
                            failed[id]=nil
                        else
                            report(id,'key could not be mapped: '..tostring(why))
                        end
                    end
                end
            end
        end
    end
    function api:configure(nextPlan)
        plan=nextPlan
        current={}
        -- A binding whose action or trigger cannot be built is left out; the
        -- others still configure.
        for _,binding in ipairs(plan.bindings) do
            local ok,target=pcall(function()
                local target=action(binding)
                target.ValueType,target.bConsumeInput,target.bTriggerWhenPaused=0,binding.consume==true,false
                trigger(target,binding.mode)
                return target
            end)
            if ok then
                current[binding.id]=target
                if failed[binding.id] then log.info('input configured: ',binding.id) end
                failed[binding.id]=nil
            else
                report(binding.id,target)
            end
        end
        self.plan,self.actions=plan,current
        for logical in pairs(attached) do map(logical) end
        return current
    end
    -- Map the plan's keys into an applied native context. Global bindings, such
    -- as Hold Swap's edges, apply in every context MCC is attached to.
    function api:attach(logical,_,_,native)
        assert(M.native[logical],'unsupported input context: '..tostring(logical))
        assert(e.valid(native),'native mapping context unavailable: '..M.native[logical])
        -- A handle's get returns a new wrapper, so the same context is matched by path.
        if attached[logical] then
            local current=live(attached[logical].context)
            if not (current and e.path(current)==e.path(native)) then self:detach(logical) end
        end
        if not attached[logical] then
            local handle,why=keep(native)
            assert(handle,'native mapping context cannot be kept: '..tostring(why))
            attached[logical]={context=handle,entries={}}
        end
        map(logical)
        log.debug('mapped into ',M.native[logical],': ',#attached[logical].entries,' key(s)')
        -- IMC_Base takes over keys usable everywhere from the gameplay contexts.
        if logical=='base' then
            for _,other in ipairs(gameplay) do if attached[other] then map(other) end end
        end
        return true
    end
    -- True while the native context is applied and still holds every MCC entry.
    function api:attached(logical,playerInput)
        local record=attached[logical]
        local context=record and live(record.context)
        if not context or not e.valid(playerInput)
            or not playerInput.AppliedInputContexts then return false end
        local applied=false
        e.each(playerInput.AppliedInputContexts,function(candidate)
            candidate=e.unwrap(candidate)
            if e.valid(candidate) and e.path(candidate)==e.path(context) then applied=true end
        end)
        if not applied then return false end
        -- Each action and key pair must still be there. Where the engine's key names
        -- cannot be read, the action alone is checked.
        local present,pairsPresent,keysRead={},{},false
        e.each(context.Mappings or {},function(entry)
            entry=e.unwrap(entry)
            local target=entry and e.unwrap(entry.Action)
            if e.valid(target) then
                local path=e.path(target)
                present[path]=true
                local read,name=pcall(function()
                    local value=e.unwrap(e.unwrap(entry.Key).KeyName)
                    if type(value)=='string' then return value end
                    return value:ToString()
                end)
                if read and name~=nil then
                    keysRead=true
                    pairsPresent[path..'\0'..keyId(name)]=true
                end
            end
        end)
        for _,entry in ipairs(record.entries) do
            local path=e.path(entry[1])
            if not present[path] then return false end
            if keysRead and not pairsPresent[path..'\0'..keyId(entry[2])] then return false end
        end
        return true
    end
    function api:detach(logical)
        local record=attached[logical]
        if record then unmap(record) end
        attached[logical]=nil
        -- Without IMC_Base, the gameplay contexts carry every key again.
        if logical=='base' then
            for _,other in ipairs(gameplay) do if attached[other] then map(other) end end
        end
        return true
    end
    function api:detachAll()
        local failed={}
        for logical in pairs(attached) do
            local ok,why=pcall(self.detach,self,logical)
            if not ok then failed[#failed+1]=logical .. ': ' .. tostring(why) end
        end
        return #failed==0,table.concat(failed,'; ')
    end
    function api:hasOwners() return next(attached)~=nil end
    return api
end

return M
