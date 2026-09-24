-- Decode KEC's player-owned controls into the quickslot input contract.
-- Template visual settings are supplied separately by KET.
local M = {}

local function integer(values, name, minimum, maximum)
    local value = values['KEC_' .. name]
    assert(type(value) == 'number' and value % 1 == 0
        and value >= minimum and value <= maximum,
        'invalid KEC setting: ' .. name)
    return value
end

local function binding(values, prefix, modeMinimum, modeMaximum)
    return {key=integer(values, prefix .. 'Key', 0, 254),
        mode=integer(values, prefix .. 'Mode', modeMinimum, modeMaximum)}
end

function M.decode(values)
    assert(type(values) == 'table', 'KEC settings table required')
    local method = integer(values, 'AccessMethod', 0, 2)
    local result = {access=method == 0 and 1 or method == 1 and 0 or 2,
        direct={['1']={}, ['2']={}}, groups={}, shared={},
        advanced={['1']={}, ['2']={}}, assignments={flat={}, groups={}, advanced={}}}
    for index = 1, 8 do
        local prefix = 'Flat' .. index
        local group = index <= 4 and '1' or '2'
        local slot = ((index - 1) % 4) + 1
        result.direct[group][slot] = {
            key=integer(values, prefix .. 'Key', 0, 254),
            mode=values['KEC_' .. prefix .. 'Mode'] or 0,
        }
        assert(result.direct[group][slot].mode == 0 or result.direct[group][slot].mode == 1,
            'invalid KEC setting: ' .. prefix .. 'Mode')
        result.direct[group][slot].activateKey = values['KEC_' .. prefix .. 'ActivateKey'] or 0
        assert(type(result.direct[group][slot].activateKey) == 'number'
            and result.direct[group][slot].activateKey % 1 == 0
            and result.direct[group][slot].activateKey >= 0
            and result.direct[group][slot].activateKey <= 254,
            'invalid KEC setting: ' .. prefix .. 'ActivateKey')
        result.assignments.flat[index] = index
    end
    for index = 1, 2 do
        local group = tostring(index)
        local prefix = 'Group' .. index
        result.groups[group] = binding(values, prefix, index == 1 and -1 or 0, 2)
        local mode = result.groups[group].mode
        assert(mode == 0 or mode == 2 or (index == 1 and mode == -1),
            'invalid group mode: ' .. prefix)
        result.assignments.groups[group] = {}
        result.assignments.advanced[group] = {}
        for slot = 1, 4 do
            result.assignments.groups[group][slot] = (index - 1) * 4 + slot
            local advancedPrefix = 'Advanced' .. index .. 'Slot' .. slot
            result.advanced[group][slot] = binding(values, advancedPrefix, 0, 1)
            result.assignments.advanced[group][slot] = (index - 1) * 4 + slot
        end
    end
    for slot = 1, 4 do
        result.shared[slot] = binding(values, 'Shared' .. slot, 0, 1)
    end
    assert(result.groups['1'].mode ~= -1 or result.groups['1'].key == 0,
        'Default group cannot have a bound key')
    return result
end

function M.read(path)
    local file = assert(io.open(path, 'rb'), 'missing KEC config: ' .. path)
    local content = file:read('*a')
    file:close()
    local values, section = {}, nil
    for line in (content:gsub('\r\n', '\n'):gsub('\r', '\n') .. '\n'):gmatch('(.-)\n') do
        local heading = line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section = heading
        elseif section == 'Controls' then
            local key, raw = line:match('^%s*([^=;#]+)%s*=%s*([^;#]*)')
            if key then
                key = key:match('^%s*(.-)%s*$')
                assert(values[key] == nil, 'duplicate KEC config key: ' .. key)
                values[key] = assert(tonumber(raw), 'invalid KEC config value: ' .. key)
            end
        end
    end
    return M.decode(values)
end

return M
