-- Own generated Enhanced Input actions and per-gameplay-context mappings.
local M={}

function M.new(e)
    local contexts,actions,owners={},{},{}
    local api={}
    local contextNames={exploration='IMC_MCC_Exploration',combat='IMC_MCC_Combat'}
    local function context(name)
        assert(contextNames[name],'unsupported input context: ' .. tostring(name))
        if not e.valid(contexts[name]) then contexts[name]=e.retain('InputMappingContext',contextNames[name]) end
        return assert(e.valid(contexts[name]) and contexts[name],'mapping context unavailable: ' .. name)
    end
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
        local result=e.trigger(target,mode==1 and 'InputTriggerHold' or 'InputTriggerTap')
        assert(e.valid(result),'input trigger unavailable')
        if mode==1 then result.HoldTimeThreshold=e.threshold or .2;result.bIsOneShot=true
        else result.TapReleaseTimeThreshold=e.threshold or .2 end
        target.Triggers={result}
    end
    function api:configure(plan)
        local current={}
        for _,binding in ipairs(plan.bindings) do
            local target=action(binding)
            target.ValueType,target.bConsumeInput,target.bTriggerWhenPaused=0,false,false
            trigger(target,binding.mode)
            current[binding.id]=target
        end
        for _,logical in ipairs(plan.contexts) do
            local mapping=context(logical);mapping:UnmapAll()
            for _,binding in ipairs(plan.bindings) do
                mapping:MapKey(current[binding.id],{KeyName=e.name(binding.keyName)})
            end
        end
        self.plan,self.actions=plan,current
        return current
    end
    function api:attach(logical,subsystem,nativePriority)
        local mapping=context(logical)
        -- Keep ownership even if the native call mutates and then throws.
        owners[logical]=subsystem
        subsystem:AddMappingContext(mapping,1000+(tonumber(nativePriority) or 0),e.options)
        return true
    end
    function api:attached(logical,playerInput)
        local wanted=contexts[logical]
        if not e.valid(wanted) or not e.valid(playerInput) or not playerInput.AppliedInputContexts then return false end
        local found=false
        e.each(playerInput.AppliedInputContexts,function(candidate)
            candidate=e.unwrap(candidate)
            if e.valid(candidate) and e.path(candidate)==e.path(wanted) then found=true end
        end)
        return found
    end
    function api:detach(logical)
        local subsystem=owners[logical]
        if e.valid(subsystem) and e.valid(contexts[logical]) then
            subsystem:RemoveMappingContext(contexts[logical],e.options)
        end
        owners[logical]=nil
        return true
    end
    function api:detachAll()
        local failed={}
        for logical in pairs(owners) do
            local ok,why=pcall(self.detach,self,logical)
            if not ok then failed[#failed+1]=logical .. ': ' .. tostring(why) end
        end
        return #failed==0,table.concat(failed,'; ')
    end
    function api:hasOwners() return next(owners)~=nil end
    return api
end

return M
