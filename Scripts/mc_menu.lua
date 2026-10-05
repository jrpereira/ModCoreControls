-- Shared menu definitions and state. Rendering and persistence are separate.
local M = {}
local triggers = require('mc_triggers')
local keyNames = require('mc_key_names')
local contexts={exploration=true,combat=true}

local function token(value)
    return (value:gsub('[^%w]', function(c) return ('_%02X'):format(c:byte()) end))
end

function M.define(registry, mapRegistry)
    -- mirrors repeat a map setting on another page; they are never stored.
    local result = { sections = {}, settings = {}, byId = {}, mirrors = {} }
    local mapSettings = {}
    local function setting(id, name, kind, default, values, labels)
        assert(not result.byId[id], 'duplicate setting: ' .. id)
        local item = { id=id, name=name, kind=kind, default=default, values=values, labels=labels }
        result.settings[#result.settings + 1] = item
        result.byId[id] = item
        return item
    end
    local known = {}
    for _, id in ipairs(registry.order) do
        assert(type(id)=='string' and id:match('%S') and not known[id],
            'invalid or duplicate section id: ' .. tostring(id))
        known[id] = true
        local section = { id=id, name=id:sub(1,1):upper() .. id:sub(2), maps={}, settings={} }
        result.sections[#result.sections + 1] = section
        local maps = mapRegistry.maps[id] or {}
        for _, mapId in ipairs(mapRegistry.order[id] or {}) do
            local declaration = assert(maps[mapId], 'missing ordered map: ' .. mapId)
            assert(type(declaration.name)=='string' and declaration.name:match('%S'),
                'map needs a name: ' .. mapId)
            assert(type(declaration.value)=='number' and declaration.value%1==0,
                'map needs a stable integer value: ' .. mapId)
            assert(type(declaration.contexts)=='table' and #declaration.contexts>0,
                'map needs contexts: ' .. mapId)
            local seenContexts={}
            for _,context in ipairs(declaration.contexts) do
                assert(contexts[context] and not seenContexts[context],
                    'invalid or duplicate context in ' .. mapId .. ': ' .. tostring(context))
                seenContexts[context]=true
            end
            assert(type(declaration.map)=='table','map needs groups: ' .. mapId)
            assert(#declaration.map>0 or type(declaration.settings)=='table'
                and #declaration.settings>0,'map needs groups or settings: ' .. mapId)
            require('mc_input_plan').validateOverride(declaration.override)
            section.maps[#section.maps + 1] = { id=mapId, name=declaration.name,
                value=declaration.value, declaration=declaration, groups={},
                contexts=declaration.contexts, override=declaration.override,
                settings={},holdSwap=declaration.holdSwap }
        end
        table.sort(section.maps, function(a,b) return a.value < b.value end)
        if #section.maps > 0 then
            local values, labels, used = {}, {}, {}
            for _, map in ipairs(section.maps) do
                assert(not used[map.value], 'duplicate map value in ' .. id)
                used[map.value] = true
                values[#values+1], labels[#labels+1] = map.value, map.name
            end
            -- Maps coexist. The picker only navigates between their pages, so it
            -- is neither a stored setting nor an input to the runtime plan.
            section.selector = { id='MCC_' .. token(id) .. '_Map', name='Control Map', kind='choice',
                default=values[1], values=values, labels=labels, navigation=true }
        end
        for _, map in ipairs(section.maps) do
            local declaredSettings=map.declaration.settings or {}
            local settingsById={}
            for _,source in ipairs(declaredSettings) do
                assert(type(source)=='table' and type(source.id)=='string'
                    and source.id:match('%S') and not settingsById[source.id],
                    'invalid or duplicate map setting in '..map.id)
                assert(type(source.name)=='string' and source.name:match('%S'),
                    'map setting needs a name: '..source.id)
                assert(source.kind=='key' or source.kind=='choice',
                    'unsupported map setting kind: '..source.id)
                local values,labels=source.values or {},source.labels or {}
                if source.kind=='choice' then
                    assert(#values>0 and #values==#labels,'invalid map setting choices: '..source.id)
                end
                local item=setting('MCC_'..token(id)..'_'..token(map.id)..'_'..token(source.id),
                    source.name,source.kind,source.default,values,labels)
                item.configSection='ModCoreControls.'..id
                item.configKey=map.id..'.'..token(source.id)
                assert(M.valid(item,item.default),'invalid map setting default: '..source.id)
                map.settings[#map.settings+1]=item
                settingsById[source.id]=item
            end
            mapSettings[id .. '\0' .. map.id]=settingsById
            if map.holdSwap then
                assert(type(map.holdSwap)=='table','invalid Hold Swap declaration: '..map.id)
                map.holdSwap={enabled=assert(settingsById[map.holdSwap.enabled],
                        'Hold Swap setting unavailable: '..map.id),
                    defaultWheel=assert(settingsById[map.holdSwap.defaultWheel],
                        'Hold Swap default wheel setting unavailable: '..map.id),
                    outsideCombat=map.holdSwap.outsideCombat and assert(settingsById[map.holdSwap.outsideCombat],
                        'Swap outside of combat setting unavailable: '..map.id),
                    action=assert(type(map.holdSwap.action)=='string'
                        and map.holdSwap.action:match('%S') and map.holdSwap.action,
                        'Hold Swap action unavailable: '..map.id)}
            end
            local bindingIds={}
            for _, group in ipairs(map.declaration.map) do
                assert(type(group.name)=='string' and group.name:match('%S'),
                    'group needs a name in ' .. map.id)
                assert(type(group.keys)=='table','group needs keys in ' .. map.id)
                local output = { name=group.name, keys={}, settings={} }
                for _,source in ipairs(group.settings or {}) do
                    assert(type(source)=='table' and type(source.id)=='string' and source.id:match('%S')
                        and type(source.mirror)=='table','group settings mirror a map setting: ' .. map.id)
                    local owner=mapSettings[(source.mirror.section or id) .. '\0' .. tostring(source.mirror.map)]
                    local target=assert(owner and owner[source.mirror.setting],
                        'unknown mirrored setting in ' .. map.id .. ': ' .. tostring(source.mirror.setting))
                    assert(target.kind=='choice','only choices can be mirrored: ' .. source.id)
                    local item={id='MCC_'..token(id)..'_'..token(map.id)..'_'..token(source.id),
                        name=source.name or target.name,kind='choice',default=target.default,
                        values=target.values,labels=target.labels,mirror=target}
                    assert(not result.byId[item.id],'duplicate setting: ' .. item.id)
                    for _,other in ipairs(result.mirrors) do
                        assert(other.id~=item.id,'duplicate setting: ' .. item.id)
                    end
                    result.mirrors[#result.mirrors+1]=item
                    output.settings[#output.settings+1]=item
                end
                map.groups[#map.groups+1] = output
                for _, key in ipairs(group.keys) do
                    assert(type(key.id)=='string' and key.id:match('%S') and not bindingIds[key.id],
                        'invalid or duplicate binding id in ' .. map.id .. ': ' .. tostring(key.id))
                    bindingIds[key.id]=true
                    assert(type(key.name)=='string' and key.name:match('%S'),
                        'binding needs a name: ' .. key.id)
                    assert(type(key.trigger)=='string','binding needs triggers: ' .. key.id)
                    assert(key.sustained==nil or type(key.sustained)=='boolean',
                        'invalid sustained flag: ' .. key.id)
                    assert(key.inactive==nil or type(key.inactive)=='boolean',
                        'invalid inactive flag: ' .. key.id)
                    assert(key.defaultControl==nil or type(key.defaultControl)=='string'
                        and key.defaultControl:match('%S'),
                        'invalid default control: ' .. key.id)
                    assert(key.defaultControl==nil or key.optional==true,
                        'default control requires an optional key: ' .. key.id)
                    assert(key.groupedBy==nil or type(key.groupedBy)=='string' and key.groupedBy:match('%S'),
                        'invalid groupedBy: ' .. key.id)
                    assert(key.displayAlias==nil or type(key.displayAlias)=='number'
                        and key.displayAlias%1==0 and key.displayAlias>=0xC1 and key.displayAlias<=0xC8,
                        'invalid displayAlias: ' .. key.id)
                    local action=key.action
                    assert(type(action)=='table' and
                        (action.type=='ability' or action.type=='consumable' or action.type=='selected' or action.type=='focus'),
                        'invalid action: ' .. key.id)
                    local field=action.type=='focus' and 'group' or 'slot'
                    -- A focus action names a fixed group, or the Default wheel
                    -- or the other wheel relative to it.
                    if action.type=='focus' and action.group==nil then
                        field='wheel'
                        assert(action.wheel=='default' or action.wheel=='other',
                            'invalid action wheel: ' .. key.id)
                    else
                        -- Group 3 is configuration-only until the game exposes a
                        -- third quickslot target; inactive bindings never enter
                        -- the runtime plan.
                        local limit=action.type=='focus' and 3 or 4
                        local value=action[field]
                        assert(type(value)=='number' and value%1==0 and value>=1 and value<=limit,
                            'invalid action ' .. field .. ': ' .. key.id)
                    end
                    for name in pairs(action) do
                        assert(name=='type' or name==field,'unknown action field: ' .. key.id)
                    end
                    assert(not key.sustained or action.type=='focus',
                        'sustained non-focus action: ' .. key.id)
                    -- override=true overrides the key's own defaultControl, and only
                    -- while the player binds a custom key in its place.
                    if key.override==true then
                        assert(key.defaultControl,'override=true requires defaultControl: ' .. key.id)
                    else
                        require('mc_input_plan').validateOverride(key.override)
                    end
                    local prefix = 'MCC_' .. token(id) .. '_' .. token(map.id) .. '_' .. token(key.id)
                    local modes, names, usedModes = {}, {}, {}
                    for name in key.trigger:gmatch('[^|]+') do
                        local mode=triggers.toEnhancedInput(name, key.sustained)
                        assert(not usedModes[mode],'duplicate trigger: ' .. key.id)
                        usedModes[mode]=true
                        modes[#modes+1] = mode
                        names[#names+1] = name
                    end
                    assert(#modes>0, 'key must declare a trigger')
                    local overrideDefault=type(key.override)=='table' and key.override.action
                        and key.override.value or nil
                    local binding = {
                        id=key.id,
                        key=setting(prefix .. '_Key', key.name, 'key',
                            key.default~=nil and key.default or overrideDefault or 0),
                        trigger=setting(prefix .. '_Trigger', key.name, 'choice', modes[1], modes, names),
                        optional=key.optional == true,
                        defaultControl=key.defaultControl,
                        inactive=key.inactive == true,
                        groupedBy=key.groupedBy,
                        displayAlias=key.displayAlias,
                        sustained=key.sustained == true,
                        action=key.action,
                        override=key.override,
                    }
                    assert(M.valid(binding.key,binding.key.default),
                        'unsupported default key: ' .. binding.key.id)
                    output.keys[#output.keys+1] = binding
                    for kind,item in pairs({key=binding.key,trigger=binding.trigger}) do
                        item.configSection='ModCoreControls.' .. id
                        item.configKey=map.id .. '.' .. token(key.id) .. '.' .. kind
                    end
                end
            end
            map.declaration = nil
        end
    end
    for section in pairs(mapRegistry.maps) do
        assert(known[section], 'unknown map section: ' .. tostring(section))
    end
    if type(registry.seal)=='function' then registry.seal() end
    if type(mapRegistry.seal)=='function' then mapRegistry.seal() end
    return result
end

function M.valid(setting, value)
    if type(value)~='number' or value%1~=0 then return false end
    if setting.kind=='key' then return value>=0 and value<=254 and keyNames.toName(value)~=nil end
    for _, allowed in ipairs(setting.values) do if value==allowed then return true end end
    return false
end

function M.new(definition, values)
    local self = { definition=definition, values={}, saved={} }
    for _, setting in ipairs(definition.settings) do
        local value = values and values[setting.id]
        if value == nil then value = setting.default end
        assert(M.valid(setting,value), 'invalid config value: ' .. setting.id)
        self.values[setting.id], self.saved[setting.id] = value, value
    end
    function self:set(id, value)
        assert(M.valid(assert(self.definition.byId[id], 'unknown setting: ' .. tostring(id)),value),
            'invalid setting value: ' .. tostring(id))
        self.values[id] = value
    end
    function self:dirty()
        for id,value in pairs(self.values) do if self.saved[id]~=value then return true end end
        return false
    end
    function self:apply(store)
        local committed,warning=store:save(self.values)
        assert(committed~=false,'config was not committed')
        for id,value in pairs(self.values) do self.saved[id]=value end
        return warning
    end
    return self
end

return M
