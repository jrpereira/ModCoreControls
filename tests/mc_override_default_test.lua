package.path='Scripts/?.lua;'..package.path

-- Fresh declarations per case: mc_maps seals itself once a definition is built.
local function define(change)
    for _,name in ipairs({'mc_maps','mc_sections','mc_menu','mc_input_plan'}) do package.loaded[name]=nil end
    local maps=require('mc_maps')
    change(maps.maps.actions)
    local Menu=require('mc_menu')
    return Menu.define(require('mc_sections'),maps),Menu,require('mc_input_plan')
end

local function find(plan,id)
    for _,item in ipairs(plan.bindings) do if item.id==id then return item end end
end

-- Quickslot 1 inherits IA_Quickslot_Left; override=true suppresses that native
-- action only while the player binds a custom key in its place.
local definition,Menu,Plan=define(function(actions) actions.grouped.map[1].keys[1].override=true end)
local slot=definition.sections[2].maps[1].groups[1].keys[1]
assert(slot.id=='QuickSlot1' and slot.defaultControl=='IA_Quickslot_Left' and slot.override==true)
local model=Menu.new(definition,{})

local inherited=Plan.build(definition,model.values)
assert(not inherited.overrides.IA_Quickslot_Left,'an inherited key must leave the native action alone')
local item=find(inherited,'grouped.QuickSlot1')
assert(item and item.override==nil and item.standardAction=='IA_Quickslot_Left')

model:set(slot.key.id,70)
local custom=Plan.build(definition,model.values)
assert(custom.overrides.IA_Quickslot_Left,'a custom key must override its default control')
item=find(custom,'grouped.QuickSlot1')
assert(item.keyName=='F' and item.override=='IA_Quickslot_Left' and item.standardAction==nil)
-- Other inherited slots and Default's hold-swap override are unaffected.
assert(not custom.overrides.IA_Quickslot_Top and custom.overrides.IA_Combat_ToggleQuickslots)

model:set(slot.key.id,0)
assert(not Plan.build(definition,model.values).overrides.IA_Quickslot_Left,
    'returning to the default key must drop the override')

-- The hold-swap action and an override=true key on the same native action share one entry.
definition,Menu,Plan=define(function(actions) actions.grouped.map[2].keys[1].override=true end)
local group=definition.sections[2].maps[1].groups[2].keys[1]
assert(group.id=='GroupFocus2' and group.defaultControl=='IA_Combat_ToggleQuickslots')
model=Menu.new(definition,{})
model:set(group.key.id,71)
local shared=Plan.build(definition,model.values)
assert(shared.overrides.IA_Combat_ToggleQuickslots==true
    and find(shared,'grouped.GroupFocus2').override=='IA_Combat_ToggleQuickslots')

-- override=true needs a defaultControl, and maps cannot use it.
assert(not pcall(define,function(actions) actions.grouped.map[2].keys[2].override=true end),
    'override=true without defaultControl must be rejected')
assert(not pcall(define,function(actions) actions.grouped.override=true end),
    'a map-level override=true must be rejected')

print('PASS override=true follows a custom binding of the default control')
