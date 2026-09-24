package.path = 'Scripts/?.lua;' .. package.path
local Game = require('kec.game_slots')
local Layouts = require('kec.layout_templates')
local function object(name)
    return {name=name, IsValid=function() return true end}
end
local quickslots = {GetAbilityInSlot=function(_, slot, phase)
    if phase == 1 and slot == 0 then return object('day-left') end
    if phase == 2 and slot == 0 then return object('night-left') end
end}
local development = {
    GetEquippedAbilityTypeLimit=function(_, kind)
        return kind == 1 and 3 or kind == 2 and 4 or 2
    end,
    GetEquippedAbility=function(_, kind, slot)
        if kind == 1 and slot == 0 then return object('weapon-one') end
    end,
}
local available = Game.read(quickslots, development)
assert(available.ability[1].action.name == 'day-left')
assert(available.ability[5].action.name == 'night-left')
assert(available.weapon[3].unlocked and available.weapon[3].action == nil)
assert(available.weapon[4] == nil and available.witchcraft[3] == nil)
local basic = Layouts.resolve(Layouts.load('templates/default.tpl'), 'day', available)
assert(basic[2].positions[1].visible and basic[2].positions[1].available)
assert(not basic[2].positions[2].visible)
local skill = Layouts.resolve(Layouts.load('templates/skill_slots.tpl'), 'day', available)
assert(skill[1].positions[3].visible and skill[1].positions[3].available)
assert(not skill[1].positions[4].visible)
print('Game slot snapshot follows current ability assignments and skill limits')
