-- Own generated Enhanced Input actions and map their keys into the game's own
-- gameplay contexts. A plan's contexts name where its keys can be used; MCC
-- never creates or applies a mapping context of its own.
local M={}
-- The game's mapping context for each logical context. IMC_Base stays applied
-- across gameplay, so keys usable everywhere go there and survive transitions
-- between open world and combat.
M.native={exploration='IMC_OW',combat='IMC_RTCombat',base='IMC_Base'}
local gameplay={'exploration','combat'}

function M.new(e,log)
    log=require('mc_log').wrap(log)
    local actions={}
    -- attached[logical]={context=<native IMC>,entries={{action,keyName},...}}
    local attached={}
    local plan,current
    local api={}
    local function action(binding)
        local id='IA_MCC_' .. binding.id:gsub('[^%w]','_')
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
    local function unmap(record)
        if e.valid(record.context) then
            for _,entry in ipairs(record.entries) do
                record.context:UnmapKey(entry[1],{KeyName=e.name(entry[2])})
            end
        end
        record.entries={}
    end
    local function covers(binding,logical)
        if binding.layer=='global' then return true end
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
        if not plan then return end
        for _,binding in ipairs(plan.bindings) do
            if usable(binding,logical) then
                local target=current[binding.id]
                -- An inherited binding carries every key the player bound to its
                -- source action; a suppressed key is left to its claimant.
                for _,keyName in ipairs(binding.keyNames or {binding.keyName}) do
                    if not (binding.suppressed and binding.suppressed[keyName]) then
                        record.context:MapKey(target,{KeyName=e.name(keyName)})
                        record.entries[#record.entries+1]={target,keyName}
                    end
                end
            end
        end
    end
    function api:configure(nextPlan)
        plan=nextPlan
        current={}
        for _,binding in ipairs(plan.bindings) do
            local target=action(binding)
            target.ValueType,target.bConsumeInput,target.bTriggerWhenPaused=0,binding.consume==true,false
            trigger(target,binding.mode)
            current[binding.id]=target
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
        if attached[logical] and attached[logical].context~=native then self:detach(logical) end
        attached[logical]=attached[logical] or {context=native,entries={}}
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
        if not record or not e.valid(record.context) or not e.valid(playerInput)
            or not playerInput.AppliedInputContexts then return false end
        local applied=false
        e.each(playerInput.AppliedInputContexts,function(candidate)
            candidate=e.unwrap(candidate)
            if e.valid(candidate) and e.path(candidate)==e.path(record.context) then applied=true end
        end)
        if not applied then return false end
        local present={}
        e.each(record.context.Mappings or {},function(entry)
            entry=e.unwrap(entry)
            local target=entry and e.unwrap(entry.Action)
            if e.valid(target) then present[e.path(target)]=true end
        end)
        for _,entry in ipairs(record.entries) do
            if not present[e.path(entry[1])] then return false end
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
