local function read(path)
    local file = assert(io.open(path, 'rb'))
    local content = assert(file:read('*a'))
    assert(file:close())
    return content
end

local function optional(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local content = assert(file:read('*a'))
    assert(file:close())
    return content
end

local config = optional('config.ini')
assert(loadfile('tools/generate_menu.lua'))()
local generated = read('mod_settings.ini')
assert(generated:find('[Mod]',1,true))
assert(generated:find('Id=ModCoreControls',1,true))
assert(generated:find('Name=Controls',1,true))
assert(not generated:find('[Setting.',1,true))
assert(not generated:find('[Category.',1,true))
assert(optional('config.ini') == config, 'menu generation must not create or overwrite player choices')
assert(loadfile('tools/generate_menu.lua'))()
assert(read('mod_settings.ini') == generated, 'menu generation must be deterministic')
print('PASS minimal DMM manifest generation preserves config.ini')
