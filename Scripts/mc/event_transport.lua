-- Cross-mod delivery for MCC's string-identity events. Each subscriber owns
-- one UE4SS console command; the publisher sends through ModRef shared data.
local Events = require('mc.events')
local M = {}
local registryKey = 'MCC_ControlEvents_v1.subscribers'
local prefix = 'MCC_ControlEvents_v1_'
local installed
local buses = setmetatable({}, {__mode='k'})

local function hex(value)
    if value == nil then return '-' end
    assert(type(value) == 'string' and #value <= 256 and not value:find('%c'),
        'control event arguments must be short identifiers')
    return (value:gsub('.', function(char) return string.format('%02x', char:byte()) end))
end

local function unhex(value)
    if value == '-' then return nil end
    assert(#value <= 512 and #value % 2 == 0 and not value:find('[^%da-f]'),
        'invalid encoded control event argument')
    return (value:gsub('..', function(pair) return string.char(tonumber(pair, 16)) end))
end

local function members()
    local result = {}
    for command in tostring(ModRef:GetSharedVariable(registryKey) or ''):gmatch('[^\n]+') do
        if command:match('^MCC_ControlEvents_v1_[%w]+$') then
            result[#result + 1] = command
        end
    end
    return result
end

local function save(commands)
    ModRef:SetSharedVariable(registryKey, table.concat(commands, '\n'))
end

function M.subscribe(name, callback, bus)
    bus = bus or Events.shared()
    assert(ModRef and type(RegisterConsoleCommandHandler) == 'function',
        'UE4SS cross-mod event subscription unavailable')
    if not installed then
        local command = prefix .. tostring({}):gsub('%W', '')
        assert(#command <= 96, 'control event subscriber identity too long')
        local ok, why = pcall(RegisterConsoleCommandHandler, command, function()
            local accepted, problem = pcall(function()
                local payload = assert(ModRef:GetSharedVariable(command .. '.data'),
                    'missing control event payload')
                local event, a, b, c = payload:match('^([^\n]+)\n([^\n]+)\n([^\n]+)\n([^\n]+)$')
                assert(event and a and b and c, 'invalid control event payload')
                for target, count in pairs(buses) do
                    if count > 0 then target:receive(event, unhex(a), unhex(b), unhex(c)) end
                end
            end)
            if not accepted then
                print('[ModCoreControls] event receive failed: ' .. tostring(problem) .. '\n')
            end
            return true
        end)
        assert(ok and why ~= false, 'control event handler registration failed: ' .. tostring(why))
        local list = members()
        list[#list + 1] = command
        save(list)
        installed = command
    end
    local unsubscribe = bus:subscribe(name, callback)
    buses[bus] = (buses[bus] or 0) + 1
    local active = true
    return function()
        if not active then return end
        active = false
        unsubscribe()
        local remaining = (buses[bus] or 1) - 1
        buses[bus] = remaining > 0 and remaining or nil
    end
end

function M.publisher(resolveController)
    assert(type(resolveController) == 'function', 'player controller resolver required')
    return function(event, a, b, c)
        event = Events.canonical(event)
        local list = members()
        if #list == 0 then return true end
        local pc = assert(resolveController(), 'player controller unavailable for control event')
        assert(pc:IsValid(), 'control event player controller invalid')
        local player = assert(pc.Player, 'control event local player unavailable')
        local viewport = assert(player.ViewportClient, 'control event viewport unavailable')
        assert(viewport:IsValid(), 'control event viewport invalid')
        local payload = table.concat({event, hex(a), hex(b), hex(c)}, '\n')
        local live = {}
        for _, command in ipairs(list) do
            ModRef:SetSharedVariable(command .. '.data', payload)
            local ok, accepted = pcall(function()
                return viewport:ProcessConsoleExec(command, nil, pc)
            end)
            if ok and accepted == true then live[#live + 1] = command end
        end
        if #live ~= #list then save(live) end
        return true
    end
end

return M
