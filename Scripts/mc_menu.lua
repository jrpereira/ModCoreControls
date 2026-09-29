-- Shared menu definitions and state. Rendering and persistence are separate.
local M = {}
local triggers = require('mc_triggers')
local keyNames = require('mc_key_names')
local contexts={exploration=true,combat=true}

local function token(value)
    return (value:gsub('[^%w]', function(c) return ('_%02X'):format(c:byte()) end))
end

function M.define(registry, mapRegistry)
    local result = { sections = {}, settings = {}, byId = {} }
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
        local section = { id=id, name=id:sub(1,1):upper() .. id:sub(2), maps={} }
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
            assert(type(declaration.map)=='table' and #declaration.map>0,
                'map needs groups: ' .. mapId)
            require('mc_input_plan').validateOverride(declaration.override)
            section.maps[#section.maps + 1] = { id=mapId, name=declaration.name,
                value=declaration.value, declaration=declaration, groups={},
                contexts=declaration.contexts, override=declaration.override }
        end
        table.sort(section.maps, function(a,b) return a.value < b.value end)
        if #section.maps > 0 then
            local values, labels, used = {}, {}, {}
            for _, map in ipairs(section.maps) do
                assert(not used[map.value], 'duplicate map value in ' .. id)
                used[map.value] = true
                values[#values+1], labels[#labels+1] = map.value, map.name
            end
            section.selector = setting('MCC_' .. token(id) .. '_Map', 'Control Map', 'choice', values[1], values, labels)
            section.selector.configSection='ModCoreControls.' .. id
            section.selector.configKey='map'
            section.selector.storedValues={}
            for _, map in ipairs(section.maps) do section.selector.storedValues[map.value]=map.id end
        end
        for _, map in ipairs(section.maps) do
            local bindingIds={}
            for _, group in ipairs(map.declaration.map) do
                assert(type(group.name)=='string' and group.name:match('%S'),
                    'group needs a name in ' .. map.id)
                assert(type(group.keys)=='table','group needs keys in ' .. map.id)
                local output = { name=group.name, keys={} }
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
                    local action=key.action
                    assert(type(action)=='table' and
                        (action.type=='ability' or action.type=='consumable' or action.type=='selected' or action.type=='focus'),
                        'invalid action: ' .. key.id)
                    local field=action.type=='focus' and 'group' or 'slot'
                    local limit=action.type=='focus' and 2 or 4
                    local value=action[field]
                    assert(type(value)=='number' and value%1==0 and value>=1 and value<=limit,
                        'invalid action ' .. field .. ': ' .. key.id)
                    for name in pairs(action) do
                        assert(name=='type' or name==field,'unknown action field: ' .. key.id)
                    end
                    assert(not key.sustained or action.type=='focus',
                        'sustained non-focus action: ' .. key.id)
                    require('mc_input_plan').validateOverride(key.override)
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
