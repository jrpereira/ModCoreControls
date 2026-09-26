package.path = 'Scripts/?.lua;Scripts/?/init.lua;' .. package.path
local targets = require('mcc.player_actions.native_targets')
assert(#targets == 5 and targets.requiredCount == 4,
    'four directional actions are required; the combat toggle is optional')
local seen = {}
for _, name in ipairs(targets) do
    assert(type(name) == 'string' and name:match('^IA_'), 'invalid native action name')
    assert(not seen[name], 'duplicate native action target')
    seen[name] = true
end
assert(seen.IA_Quickslot_Left)
assert(seen.IA_Combat_ToggleQuickslots)
assert(not seen.IA_OW_ToggleQuickslots)
print('PASS native targets: exact MCC quickslot gate allowlist')
