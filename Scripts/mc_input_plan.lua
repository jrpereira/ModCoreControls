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

-- Default is the base map: its Default wheel is in effect under every map.
local function defaultWheel(definition,values)
    for _,section in ipairs(definition.sections) do
        if section.id=='actions' then
            for _,map in ipairs(section.maps) do
                if map.holdSwap then
                    local group=assert(values[map.holdSwap.defaultWheel.id],'Default wheel setting missing')
                    assert(group==1 or group==2,'invalid Default wheel')
                    return group
                end
            end
        end
    end
    error('Default wheel setting is unavailable')
end

local function phases(binding,mode)
    if binding.action.type=='selected' then
        return {'Started','Triggered','Completed','Canceled'}
    end
    if binding.sustained and mode==2 then return {'Started','Completed','Canceled'} end
    return {'Triggered'}
end

-- Resolve a focus action relative to the Default wheel into a fixed group.
local function resolve(value,defaultGroup)
    if value.type~='focus' or value.wheel==nil then return value end
    return {type='focus',group=value.wheel=='default' and defaultGroup or 3-defaultGroup}
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
    local plan={map=map.id,contexts=map.contexts or {},bindings={},displays={},overrides={},
        defaultGroup=defaultWheel(definition,values)}
    assert(#plan.contexts>0,'selected map has no contexts: ' .. map.id)
    local contexts={}
    for _,context in ipairs(plan.contexts) do
        assert(supportedContexts[context],'unsupported input context: ' .. tostring(context))
        assert(not contexts[context],'duplicate input context: ' .. context)
        contexts[context]=true
    end
    addOverrides(plan.overrides,map.override)
    local used,active={},{}
    for _,group in ipairs(map.groups) do
        for _,binding in ipairs(group.keys) do
            -- Keep future bindings in the menu and config without creating an
            -- Enhanced Input action before their gameplay target exists.
            if not binding.inactive then
                local key=assert(values[binding.key.id],binding.key.id .. ' value missing')
                local mode=assert(values[binding.trigger.id],binding.trigger.id .. ' value missing')
                assert(require('mc_menu').valid(binding.key,key),'invalid key: ' .. binding.key.id)
                assert(require('mc_menu').valid(binding.trigger,mode),'invalid trigger: ' .. binding.trigger.id)
                local resolved=resolve(binding.action,plan.defaultGroup)
                action({id=binding.id,action=resolved,sustained=binding.sustained})
                if key~=0 or binding.defaultControl then
                    local name=key~=0 and assert(keyNames.toName(key),
                        'unsupported key: ' .. binding.key.id) or nil
                    if name then
                        local identity=name .. ':' .. mode
                        assert(not used[identity],'duplicate binding: ' .. tostring(used[identity]) .. ' and ' .. binding.key.id)
                        used[identity]=binding.key.id
                    end
                    local item={id=map.id .. '.' .. binding.id,key=key,keyName=name,mode=mode,
                        phases=phases(binding,mode),sustained=binding.sustained,
                        action=resolved,override=binding.override,
                        standardAction=key==0 and binding.defaultControl or nil}
                    plan.bindings[#plan.bindings+1]=item
                    active[binding.id]=item
                    addOverrides(plan.overrides,item.override)
                end
            end
        end
    end
    if map.holdSwap then
        local enabled=assert(values[map.holdSwap.enabled.id],'Hold Swap setting missing')
        assert(enabled==0 or enabled==1,'invalid Hold Swap setting')
        local defaultGroup=assert(values[map.holdSwap.defaultWheel.id],
            'Default wheel setting missing')
        assert(defaultGroup==1 or defaultGroup==2,'invalid Default wheel')
        local outside=1
        if map.holdSwap.outsideCombat then
            outside=assert(values[map.holdSwap.outsideCombat.id],'Swap outside of combat setting missing')
            assert(outside==0 or outside==1,'invalid Swap outside of combat setting')
        end
        plan.holdSwap={enabled=enabled==1,defaultGroup=defaultGroup,
            sourceAction=map.holdSwap.action}
        -- MCC owns the swap on the player's Toggle Quickslots key and suppresses
        -- the game's toggle. Its contexts say where the swap can be used.
        local where=outside==1 and {'exploration','combat'} or {'combat'}
        local function swap(id,mode,extra)
            local item={id=map.id..'.swap.'..id,key=0,mode=mode,phases={'Triggered'},consume=true,
                contexts=where,standardAction=map.holdSwap.action}
            for field,value in pairs(extra) do item[field]=value end
            plan.bindings[#plan.bindings+1]=item
        end
        if enabled==1 then
            -- Hold shows the other wheel; release returns to the previous one.
            swap('press',3,{holdSwapEdge='press',action={type='focus',group=3-defaultGroup}})
            swap('release',4,{holdSwapEdge='release',action={type='focus',group=defaultGroup}})
        else
            swap('toggle',3,{action={type='flip'}})
        end
        addOverrides(plan.overrides,map.holdSwap.action)
    end
    -- A bound Advanced Group owns the four HUD prompts in its section.  Point
    -- each prompt at that same generated action rather than copying a label:
    -- CommonUI therefore receives the actual key *and* its Tap/Hold trigger.
    for _,group in ipairs(map.groups) do
        for _,binding in ipairs(group.keys) do
            local source=binding.groupedBy and active[binding.groupedBy]
            if source then
                plan.displays[#plan.displays+1]={id=map.id .. '.' .. binding.id,
                    alias=binding.displayAlias,source=source.id,action=binding.action}
            end
        end
    end
    return plan
end

return M
