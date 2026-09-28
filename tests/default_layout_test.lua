package.path = 'Scripts/?.lua;' .. package.path
local Layouts = require('mc.layout_templates')
local Topology = require('mc.topology')

local basic = Layouts.load('Scripts/ModCore/default.tpl')
local skill = Layouts.load('Scripts/ModCore/skill_slots.tpl')
local flexi = Layouts.load('Scripts/ModCore/flexi_slots.tpl')
assert(basic.title == 'Basic Slots' and basic.section == 'Actions & Quickslots')
assert(skill.title == 'Skill Slots' and flexi.title == 'Flexi Slots')
assert(#basic.groups == 3 and #Layouts.activeGroups(basic, 'day') == 3)
assert(basic.groups[2].initiallyVisible == 0)
assert(basic.groups[2].actions[1] == 'quickslot.ability.5')

local initial = Layouts.resolve(basic, 'day', {})
assert(#initial[1].positions == 4 and initial[1].positions[1].visible)
assert(not initial[2].positions[1].visible)
assert(initial[3].positions[4].visible)
local expanded = Layouts.resolve(basic, 'day', {ability={[5]='chosen.ability'}})
assert(expanded[2].positions[1].visible and expanded[2].positions[1].available)
assert(expanded[2].positions[1].action == 'chosen.ability')
assert(not expanded[2].positions[2].visible)

local day = Layouts.activeGroups(skill, 'day')
local night = Layouts.activeGroups(skill, 'night')
assert(#day == 3 and #night == 3)
assert(day[2].id == 'witchcraft' and night[2].id == 'vampire')
assert(day[2].key == 2 and night[2].key == 2)
local skillTopology = Topology.new({groups=day,
    dispatch=function(action) return action end})
assert(skillTopology:choose('Groups'))
assert(skillTopology:trigger('group.witchcraft'))
assert(skillTopology:trigger('slot.3') == 'quickslot.witchcraft.3')
local skillInitial = Layouts.resolve(skill, 'day', {})
assert(skillInitial[1].positions[2].visible and not skillInitial[1].positions[3].visible)
assert(skillInitial[2].positions[2].visible and not skillInitial[2].positions[3].visible)
assert(skillInitial[3].positions[4].visible)
local skillExpanded = Layouts.resolve(skill, 'night', {
    weapon={[3]='chosen.weapon'}, vampire={[4]='chosen.vampire'}})
assert(skillExpanded[1].positions[3].visible)
assert(skillExpanded[2].positions[4].visible)

local topology = Topology.new({groups=basic.groups,
    dispatch=function(action) return action end})
assert(#topology:controls('Flat') == 12)
assert(#topology:controls('Groups') == 7)
assert(topology:trigger('flat.5') == 'quickslot.ability.5')
assert(topology:choose('Groups'))
assert(topology:trigger('group.ability_extra'))
assert(topology:trigger('slot.1') == 'quickslot.ability.5')

for _, preset in ipairs(flexi.presets) do
    local grouping = Layouts.flexiGroups(flexi, preset.name)
    local total = 0
    for _, group in ipairs(grouping.groups) do total = total + group.count end
    assert(total == 12)
end
assert(#Layouts.flexiGroups(flexi, '12x1').groups == 1)
assert(#Layouts.flexiGroups(flexi, '6x2').groups == 2)
assert(#Layouts.flexiGroups(flexi, '4+2x4').groups == 3)
assert(Layouts.flexiGroups(flexi, '6x2', 'consumable, ability').order[1] == 'consumable')
assert(Layouts.flexiGroups(flexi, '6x2', 'consumable, ability').groups[1].actions[1]
    == 'quickslot.consumable.1')
local flexiTopology = Topology.new({groups=Layouts.flexiGroups(flexi, '4+2x4').groups,
    dispatch=function(action) return action end})
assert(flexiTopology:choose('Groups'))
assert(flexiTopology:trigger('group.flexi_3'))
assert(flexiTopology:trigger('slot.4') == 'quickslot.consumable.4')
assert(not pcall(Layouts.parse, 'title: Bad\nsection: Test\ngroup: bad | Bad | 1 | always | 4 | bad | 1 | One\n'))
print('MCC layouts resolve three groups, game availability, phases, and Flexi presets')
