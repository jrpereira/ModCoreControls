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

-- The name a player sees for a wheel group (1 or 2), from the Default wheel setting.
local function wheelLabel(definition,group)
    for _,map in ipairs(runtimeMaps(definition)) do
        local wheel=map.holdSwap and map.holdSwap.defaultWheel
        if wheel then
            for index,value in ipairs(wheel.values) do
                if value==group then return wheel.labels[index] end
            end
        end
    end
    return 'wheel ' .. tostring(group)
end

-- options.lenient: a key and trigger bound twice keep their first binding and the
-- later one is skipped and listed in plan.skipped, so saved controls still start.
-- Without it, as at Apply, the pair bound twice is an error naming both rows.
-- Show key outline: none, Hold keys only, or Tap and Hold keys.
M.OUTLINE={none=0,hold=1,both=2}

function M.build(definition,values,options)
    local lenient=options and options.lenient
    local plan={maps={},contexts={},bindings={},displays={},overrides={},skipped={},
        defaultGroup=defaultWheel(definition,values),keyOutline=M.OUTLINE.both}
    -- Which key hints show a rim, and whether a lone Tap fires on press; read first,
    -- as every binding depends on them.
    local instantTap=true
    for _,map in ipairs(runtimeMaps(definition)) do
        if map.instantTap then
            local value=values[map.instantTap.id]
            assert(value==0 or value==1,'invalid instant Tap setting')
            instantTap=value==1
        end
        if map.keyOutline then
            local value=assert(values[map.keyOutline.id],'key outline setting missing')
            assert(require('mc_menu').valid(map.keyOutline,value),'invalid key outline setting')
            plan.keyOutline=value
        end
    end
    local contexts,used={},{}
    -- Keys some binding uses as Hold. A Tap on such a key stays a real Tap, so the
    -- two can be told apart; any other Tap acts on press.
    local holdKeys,tapKeys={},{}
    for _,other in ipairs(runtimeMaps(definition)) do
        for _,group in ipairs(other.groups) do
            for _,binding in ipairs(group.keys) do
                local value=not binding.inactive and values[binding.setting.id]
                local trigger=type(value)=='string' and value:match('|(%a+)$')
                local name=trigger and require('mc_menu').binding(binding.setting,value)
                if name then
                    if trigger=='Hold' then holdKeys[name:lower()]=true
                    elseif trigger=='Tap' then tapKeys[name:lower()]=true end
                end
            end
        end
    end
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
                    -- A slot key left on its default control inherits the player's key for
                    -- the game's action and takes it over: the game's action is suppressed.
                    -- Other override=true keys on their default control (Swap to, on the
                    -- swap key) leave it to the native action and add no binding.
                    local inherits=not name and binding.defaultControl~=nil
                        and (binding.override~=true or binding.action.type=='selected')
                    -- One key and trigger bind one setting: the same pair on two rows is
                    -- rejected at Apply, naming both, and skipped at startup. The same key
                    -- with another trigger is a different binding. Triggers compare as the
                    -- player chose them: a sustained Hold is still Hold.
                    local duplicate
                    if name then
                        local label=setting.name:gsub('{wheel}',(wheelLabel(definition,resolved.group or 0):gsub('%%','%%%%')))
                        local key,trigger=value:match('^([^|]+)|(.+)$')
                        -- Key names compare without regard to case, as the engine does.
                        local identity=name:lower() .. '|' .. trigger
                        if used[identity] then
                            duplicate='Key ' .. key .. ' (' .. trigger .. ')'
                                .. ' is bound to both "' .. used[identity] .. '" and "' .. label
                                .. '". Choose another key or trigger for one of them.'
                            if not lenient then error(duplicate,0) end
                            plan.skipped[#plan.skipped+1]=duplicate
                        else used[identity]=label end
                    end
                    if not duplicate and (name or inherits) then
                        local override=binding.override
                        if override==true then override=binding.defaultControl end
                        -- A Tap alone on its key acts on press (Pressed trigger); with Instant
                        -- Tap off, on release or at High, whichever comes first. A Tap
                        -- sharing its key with a Hold stays a Tap. An inherited slot key acts on
                        -- press, as the game's own action does, as does the swap key set to Tap.
                        if mode==0 and (not name or resolved.type=='focus' and binding.action.wheel) then mode=3
                        elseif mode==0 and not holdKeys[name:lower()] then mode=instantTap and 3 or 4 end
                        local item={id=map.id .. '.' .. binding.id,keyName=name,mode=mode,
                            phases=phases(binding,mode),sustained=binding.sustained,
                            action=resolved,override=override,
                            standardAction=not name and binding.defaultControl or nil,
                            -- A key for a fixed wheel (Explicit Activation) always focuses
                            -- that wheel; a key relative to Default swaps.
                            direct=binding.action.type=='focus' and binding.action.group~=nil or nil,
                            -- A Hold sharing its key with a Tap starts filling its rim at Low.
                            sharesTap=mode==1 and name~=nil and tapKeys[name:lower()] or nil}
                        -- A Hold key fills its indicator's rim while held, as the game's own
                        -- hold prompts do; a Tap key's rim is full while pressed. They also
                        -- listen to these phases, only for the rim.
                        if mode==1 and name and plan.keyOutline>=M.OUTLINE.hold
                            or (mode==0 or mode==3 or mode==4) and binding.action.type~='focus'
                                and plan.keyOutline==M.OUTLINE.both then
                            item.progressPhases={'Started','Ongoing','Triggered','Completed','Canceled'}
                        end
                        plan.bindings[#plan.bindings+1]=item
                        active[binding.id]=item
                        addOverrides(plan.overrides,item.override)
                    end
                end
            end
        end
        -- The Tap vs Hold window, in seconds: Low and High. A Hold key acts at High; a Tap
        -- sharing its key acts on a release before High.
        if map.holdThreshold then
            local low,high=require('mc_menu').range(map.holdThreshold,values[map.holdThreshold.id])
            assert(low,'invalid Hold threshold setting')
            plan.holdLow,plan.holdHigh=low/1000,high/1000
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
                -- The same binding as Swap to set to Hold on this key: press shows the
                -- other wheel, release returns to Default.
                swap('hold',2,{sustained=true,phases={'Started','Completed','Canceled'},
                    action={type='focus',group=3-defaultGroup}})
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
