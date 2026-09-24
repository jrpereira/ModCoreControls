package.path = 'Scripts/?.lua;' .. package.path
local Topology = require('kec.topology')
local delivered, selected = {}, {}
local topology = Topology.new({groups={
    {id='ability', label='Abilities', actions={
        'quickslot.ability.left', 'quickslot.ability.top',
        'quickslot.ability.right', 'quickslot.ability.bottom'}},
    {id='consumable', label='Consumables', actions={
        'quickslot.consumable.left', 'quickslot.consumable.top',
        'quickslot.consumable.right', 'quickslot.consumable.bottom'}},
}, dispatch=function(action, event)
    delivered[#delivered + 1] = {action=action, event=event}
    return action
end, onGroupChanged=function(group) selected[#selected + 1] = group end})
assert(topology:layout() == 'Flat' and #topology:controls() == 8)
assert(topology:trigger('flat.5', {key='One'}) == 'quickslot.consumable.left')
assert(topology:assign('Flat', 1, 'quickslot.consumable.bottom'))
assert(topology:trigger('flat.1') == 'quickslot.consumable.bottom')
assert(topology:choose('Groups'))
assert(#topology:controls() == 6)
assert(topology:trigger('slot.1') == 'quickslot.ability.left')
assert(topology:trigger('group.consumable'))
assert(selected[1] == 'consumable' and topology:group() == 'consumable')
assert(topology:trigger('slot.1') == 'quickslot.consumable.left')
assert(topology:assign('Groups', 1, 'quickslot.ability.top', 'consumable'))
assert(topology:trigger('slot.1') == 'quickslot.ability.top')
assert(topology:snapshot().groups.consumable[1] == 'quickslot.ability.top')
assert(topology:choose('Advanced'))
assert(#topology:controls() == 16)
assert(topology:trigger('group.ability.slot.2') == 'quickslot.ability.top')
assert(topology:group() == 'ability')
assert(topology:assign('Advanced', 2, 'quickslot.consumable.right', 'ability'))
assert(topology:trigger('group.ability.slot.2') == 'quickslot.consumable.right')
assert(#delivered == 7)
print('KEC Flat, Groups, and Advanced topology passed')
