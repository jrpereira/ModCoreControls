-- Convert the selected Actions map and shared menu values into native bindings.
local M={}
local keyNames=require('mc_key_names')
local supportedContexts={exploration=true,combat=true}

local function selectedMap(definition,values)
    for _,section in ipairs(definition.sections) do
        if section.id=='actions' then
            local selected=assert(values[section.selector.id],'Actions map selection missing')
            for _,map in ipairs(section.maps) do if map.value==selected then return map end end
            error('selected Actions map is unavailable')
        end
    end
    error('Actions section is unavailable')
end

local function phases(binding,mode)
    if binding.action.type=='selected' then
        return {'Started','Triggered','Completed','Canceled'}
    end
    if binding.sustained and mode==2 then return {'Started','Completed','Canceled'} end
    return {'Triggered'}
end

local function action(binding)
    local value=binding.action
    assert(type(value)=='table','runtime action missing: ' .. binding.id)
    local kind=value.type
    assert(kind=='ability' or kind=='consumable' or kind=='selected' or kind=='focus',
        'unsupported runtime action: ' .. binding.id)
    local field=kind=='focus' and 'group' or 'slot'
    local number=value[field]
    local maximum=kind=='focus' and 2 or 4
    assert(type(number)=='number' and number%1==0 and number>=1 and number<=maximum,
        'invalid runtime ' .. field .. ': ' .. binding.id)
    for name in pairs(value) do
        assert(name=='type' or name==field,'unknown runtime action field: ' .. binding.id)
    end
    assert(not binding.sustained or kind=='focus','sustained non-focus action: ' .. binding.id)
end

local function addOverrides(result,declaration)
    if declaration==nil then return end
    if type(declaration)=='string' then
        assert(declaration:match('%S'),'override action must be a non-empty string')
        result[declaration]=true
        return
    end
    assert(type(declaration)=='table','override must be an action name, descriptor, or list')
    if declaration.action~=nil then
        assert(type(declaration.action)=='string' and declaration.action:match('%S'),
            'override descriptor action must be a non-empty string')
        if declaration.value~=nil then
            assert(type(declaration.value)=='number' and declaration.value%1==0
                and keyNames.toName(declaration.value)~=nil,
                'override descriptor value must be a supported key')
        end
        for field in pairs(declaration) do
            assert(field=='action' or field=='value','unknown override field: ' .. tostring(field))
        end
        result[declaration.action]=true
        return
    end
    assert(#declaration>0,'override list must not be empty')
    for _,entry in ipairs(declaration) do addOverrides(result,entry) end
end

function M.validateOverride(declaration)
    addOverrides({},declaration)
    return true
end

function M.build(definition,values)
    local map=selectedMap(definition,values)
    local plan={map=map.id,contexts=map.contexts or {},bindings={},overrides={}}
    assert(#plan.contexts>0,'selected map has no contexts: ' .. map.id)
    local contexts={}
    for _,context in ipairs(plan.contexts) do
        assert(supportedContexts[context],'unsupported input context: ' .. tostring(context))
        assert(not contexts[context],'duplicate input context: ' .. context)
        contexts[context]=true
    end
    addOverrides(plan.overrides,map.override)
    local used={}
    for _,group in ipairs(map.groups) do
        for _,binding in ipairs(group.keys) do
            local key=assert(values[binding.key.id],binding.key.id .. ' value missing')
            local mode=assert(values[binding.trigger.id],binding.trigger.id .. ' value missing')
            assert(require('mc_menu').valid(binding.key,key),'invalid key: ' .. binding.key.id)
            assert(require('mc_menu').valid(binding.trigger,mode),'invalid trigger: ' .. binding.trigger.id)
            action(binding)
            if key~=0 then
                local name=assert(keyNames.toName(key),'unsupported key: ' .. binding.key.id)
                local identity=name .. ':' .. mode
                assert(not used[identity],'duplicate binding: ' .. tostring(used[identity]) .. ' and ' .. binding.key.id)
                used[identity]=binding.key.id
                local item={id=map.id .. '.' .. binding.id,key=key,keyName=name,mode=mode,
                    phases=phases(binding,mode),sustained=binding.sustained,
                    action=binding.action,override=binding.override}
                plan.bindings[#plan.bindings+1]=item
                addOverrides(plan.overrides,item.override)
            end
        end
    end
    return plan
end

return M
