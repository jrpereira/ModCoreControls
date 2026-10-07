package.path = 'Scripts/?.lua;Scripts/vendor/?.lua;' .. package.path

local registry = require('mc_sections')
local count = 0
for name, section in pairs(registry.sections) do
    assert(section.description == '' and next(section.sets) == nil, name)
    count = count + 1
end
assert(count == 4)
for index, name in ipairs({ 'module', 'actions', 'movement', 'system' }) do
    assert(registry.sections[name] and registry.order[index] == name)
end
local added = registry.addSection('flight', 'Flying controls')
assert(added == registry.sections.flight and added.description == 'Flying controls')
added.sets.example = {}
assert(next(registry.sections.movement.sets) == nil)
assert(not pcall(registry.addSection, 'flight', 'Duplicate'))
assert(registry.sections.flight == added)
assert(not pcall(registry.addSection, '', 'Invalid'))
assert(not pcall(registry.addSection, 'invalid', false))

local trigger = require('mc_triggers').toEnhancedInput
assert(trigger('Tap', false) == 0)
assert(trigger('Tap', true) == 0)
assert(trigger('Hold', false) == 1)
assert(trigger('Hold', true) == 2)
assert(trigger('Hold') == 1)
assert(not pcall(trigger, 'Tap|Hold', true))
assert(not pcall(trigger, 'Hold', 'false'))

local maps = require('mc_maps')
assert(type(maps.addSectionMap) == 'function')
-- Groups list typed settings; a keybind's own arguments sit in params.
local function keys(group)
    local result = {}
    for _, entry in ipairs(group.settings) do
        if entry.type == 'keybind' then result[#result + 1] = entry end
    end
    return result
end
for section, sectionMaps in pairs(maps.maps) do
    assert(registry.sections[section])
    for _, mapId in ipairs(maps.order[section]) do
        local definition = assert(sectionMaps[mapId])
        assert(definition.id == mapId)
        for _, setting in ipairs(definition.settings or {}) do
            assert(setting.type == 'picker' and #setting.params.values == #setting.params.labels)
        end
        local ids = {}
        for _, group in ipairs(definition.map) do
            for _, key in ipairs(keys(group)) do
                assert(key.id and not ids[key.id], 'missing or duplicate key ID')
                ids[key.id] = true
                for choice in key.params.trigger:gmatch('[^|]+') do
                    assert(type(trigger(choice, key.params.sustained)) == 'number')
                end
            end
        end
    end
end
-- Default holds module-wide settings, so it lives in the Module section.
assert(maps.maps.module.default and maps.maps.actions.default == nil)
local actions = maps.maps.actions
assert(#actions.global.map == 2, 'Global has Abilities and Consumables')
local abilities, consumables = keys(actions.global.map[1]), keys(actions.global.map[2])
assert(actions.global.map[1].name == 'Abilities' and #abilities == 4
    and abilities[1].id == 'AbilitySlot1' and abilities[1].params.action.type == 'ability')
assert(actions.global.map[2].name == 'Consumables' and #consumables == 4
    and consumables[1].id == 'ConsumableSlot1' and consumables[1].params.action.type == 'consumable')
-- Groups: Active Group holds the shared slots; Alternate Activation has the
-- swap key, then mirrors Default's Default wheel; Explicit Activation has a key per wheel.
local grouped = actions.grouped
assert(grouped.name == 'Groups' and #grouped.map == 3)
local slots = keys(grouped.map[1])
assert(grouped.map[1].name == 'Active Group' and #slots == 4 and slots[1].params.action.type == 'selected')
local activation = grouped.map[2]
local focus = keys(activation)
assert(activation.name == 'Alternate Activation' and #focus == 1)
local mirror = activation.settings[2]
assert(mirror.type == 'mirror' and mirror.params.map == 'default' and mirror.params.setting == 'DefaultWheel'
    and mirror.name == 'Swap back to default')
assert(focus[1].id == 'GroupFocus2' and focus[1].params.action.wheel == 'other'
    and focus[1].name == 'Swap to {wheel}', 'the swap key keeps its config ID')
local explicit = keys(grouped.map[3])
assert(grouped.map[3].name == 'Explicit Activation' and #explicit == 2
    and explicit[1].id == 'ActivateAbilities' and explicit[1].params.action.group == 1
    and explicit[2].id == 'ActivateConsumables' and explicit[2].params.action.group == 2
    and explicit[1].params.optional and explicit[1].default == 0 and not explicit[1].params.defaultControl)
assert(abilities[1] ~= slots[1])
-- Nothing is bound by default. Optional keys name the game control they inherit
-- while unbound: the slot keys their quickslot, Group 2 the Toggle Quickslots key.
-- Each overrides that control only while the player binds a custom key.
assert(focus[1].params.override == true and focus[1].params.optional
    and focus[1].params.defaultControl == 'IA_Combat_ToggleQuickslots')
assert(explicit[2].params.defaultControl == nil)
assert(actions.grouped.override == nil and actions.global.override == nil)
for slot, arrow in ipairs({ 'Left', 'Top', 'Right', 'Bottom' }) do
    local key = slots[slot]
    assert(key.id == 'QuickSlot' .. slot and key.params.optional
        and key.params.defaultControl == 'IA_Quickslot_' .. arrow and key.params.override == true)
end
for _, mapId in ipairs({'grouped', 'global'}) do
    for _, group in ipairs(actions[mapId].map) do
        for _, key in ipairs(keys(group)) do
            assert((key.default or 0) == 0, 'key must default to Unbound: ' .. key.id)
            -- Only the slot keys override, and only their own default control.
            assert(key.params.override == nil or (key.params.override == true and key.params.defaultControl),
                'key must not override a native action: ' .. key.id)
        end
    end
end
assert(actions.advanced == nil, 'Advanced was removed')
local flight = maps.addSectionMap('flight', { id='direct', name='Direct', value=0, map={} })
assert(flight == maps.maps.flight.direct and maps.order.flight[1] == 'direct')
assert(not pcall(maps.addSectionMap, 'flight', flight))
assert(not pcall(maps.addSectionMap, '', { id='bad' }))
assert(not pcall(maps.addSectionMap, 'flight', { name='Missing ID' }))

print('PASS initial sections, trigger conversion, and actions maps')
