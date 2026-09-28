local function read(path)
    local file = assert(io.open(path, 'rb'))
    local content = assert(file:read('*a'))
    assert(file:close())
    return content
end

local styles = assert(loadfile('Scripts/ModCore/control_styles.lua'))()
assert(#styles == 2 and styles[1].id == 'grouped' and styles[2].id == 'flat')

local grouped, flat = styles[1], styles[2]
local selectors, shared = grouped.sections[1].controls, grouped.sections[2].controls
assert(selectors[1].actionGroup == 'ability' and selectors[2].actionGroup == 'consumable')
assert(#shared == 4)

local flatControls = flat.sections[1].controls
local expected = {
    'quickslot.ability.left', 'quickslot.ability.top',
    'quickslot.ability.right', 'quickslot.ability.bottom',
    'quickslot.consumable.left', 'quickslot.consumable.top',
    'quickslot.consumable.right', 'quickslot.consumable.bottom',
}
assert(#flatControls == #expected)
for index, action in ipairs(expected) do assert(flatControls[index].action == action) end

local config, menu = read('config.ini'), read('mod_settings.ini')
assert(loadfile('tools/generate_menu.lua'))()
assert(read('config.ini') == config, 'control styles changed generated defaults')
assert(read('mod_settings.ini') == menu, 'control styles changed generated menu metadata')

print('PASS control styles: descriptive Lua reproduces the menu and defaults')
