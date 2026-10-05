-- Convert the Module and Actions maps and shared menu values into native
-- bindings. Maps coexist; the menu's map picker only navigates between pages.
local M={}
local supportedContexts={exploration=true,combat=true}
local runtimeSections={'module','actions'}

local function runtimeMaps(definition)
    local maps={}
    for _,id in ipairs(runtimeSections) do
        local found
        for _,section in ipairs(definition.sections) do
            if section.id==id then found=section end
        end
        for _,map in ipairs(assert(found,id .. ' section is unavailable').maps) do maps[#maps+1]=map end
    end
    return maps
end

-- Module's Default wheel is in effect under every map.
local function defaultWheel(definition,values)
    for _,map in ipairs(runtimeMaps(definition)) do
        if map.holdSwap then
            local group=assert(values[map.holdSwap.defaultWheel.id],'Default wheel setting missing')
            assert(group==1 or group==2,'invalid Default wheel')
            return group
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
            assert(type(declaration.value)=='string' and declaration.value:match('^%a[%w_]*$'),
                'override descriptor value must be a key name')
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
    local plan={maps={},contexts={},bindings={},displays={},overrides={},
        defaultGroup=defaultWheel(definition,values)}
    local contexts,used={},{}
    for _,map in ipairs(runtimeMaps(definition)) do
        plan.maps[#plan.maps+1]=map.id
        assert(#(map.contexts or {})>0,'map has no contexts: ' .. map.id)
        local own={}
        for _,context in ipairs(map.contexts) do
            assert(supportedContexts[context],'unsupported input context: ' .. tostring(context))
            assert(not own[context],'duplicate input context: ' .. context)
            own[context]=true
            if not contexts[context] then
                contexts[context]=true
                plan.contexts[#plan.contexts+1]=context
            end
        end
        addOverrides(plan.overrides,map.override)
        local active={}
        for _,group in ipairs(map.groups) do
            for _,binding in ipairs(group.keys) do
                -- Keep future bindings in the menu and config without creating an
                -- Enhanced Input action before their gameplay target exists.
                if not binding.inactive then
                    local Menu=require('mc_menu')
                    local setting=binding.setting
                    local value=assert(values[setting.id],setting.id .. ' value missing')
                    assert(Menu.valid(setting,value),'invalid key: ' .. setting.id)
                    local name,mode=Menu.binding(setting,value)
                    -- An inherited key uses the trigger a bare key name would get.
                    if not name then mode=select(2,Menu.binding(setting,Menu.keybind(setting,'A'))) end
                    local resolved=resolve(binding.action,plan.defaultGroup)
                    action({id=binding.id,action=resolved,sustained=binding.sustained})
                    -- An override=true key on its default control leaves that
                    -- key to the native action and adds no binding of its own.
                    if name or (binding.defaultControl and binding.override~=true) then
                        -- The same key and trigger in two maps is rejected at Apply.
                        if name then
                            local identity=name .. ':' .. mode
                            assert(not used[identity],'duplicate binding: ' .. tostring(used[identity]) .. ' and ' .. setting.id)
                            used[identity]=setting.id
                        end
                        local override=binding.override
                        if override==true then override=name and binding.defaultControl or nil end
                        -- The swap key set to Tap acts on press (Pressed trigger), so its focus
                        -- change starts before the key is released. Explicit keys keep Tap.
                        if mode==0 and resolved.type=='focus' and binding.action.wheel then mode=3 end
                        local item={id=map.id .. '.' .. binding.id,keyName=name,mode=mode,
                            phases=phases(binding,mode),sustained=binding.sustained,
                            action=resolved,override=override,
                            standardAction=not name and binding.defaultControl or nil,
                            -- A key for a fixed wheel (Explicit Activation) always focuses
                            -- that wheel; a key relative to Default swaps.
                            direct=binding.action.type=='focus' and binding.action.group~=nil or nil}
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
            local defaultGroup=plan.defaultGroup
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
                local item={id=map.id..'.swap.'..id,swap=true,mode=mode,phases={'Triggered'},consume=true,
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
        -- A bound group key can own the HUD prompts of its slots. Point each
        -- prompt at that same generated action rather than copying a label:
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
    end
    assert(#plan.contexts>0,'maps have no contexts')
    return plan
end

return M
