-- Decode MCC's player-owned controls into the quickslot input contract.
-- MCT supplies visual settings separately.
local M = {}

local function integer(values, name, minimum, maximum, default)
    local value = values['MCC_' .. name]
    if value == nil then value = default end
    assert(type(value) == 'number' and value % 1 == 0
        and value >= minimum and value <= maximum,
        'invalid MCC setting: ' .. name)
    return value
end

local function binding(values, prefix, modeMinimum, modeMaximum, defaultKey, defaultMode)
    return {key=integer(values, prefix .. 'Key', 0, 254, defaultKey),
        mode=integer(values, prefix .. 'Mode', modeMinimum, modeMaximum, defaultMode)}
end

function M.decode(values)
    assert(type(values) == 'table', 'MCC settings table required')
    local method = integer(values, 'AccessMethod', 0, 1)
    local result = {access=method == 1 and 0 or 1,
        direct={['1']={}, ['2']={}}, groups={}, shared={},
        assignments={flat={}, groups={}}}
    for index = 1, 8 do
        local prefix = 'Flat' .. index
        local group = index <= 4 and '1' or '2'
        local slot = ((index - 1) % 4) + 1
        result.direct[group][slot] = {
            key=integer(values, prefix .. 'Key', 0, 254),
            mode=values['MCC_' .. prefix .. 'Mode'] or 0,
        }
        assert(result.direct[group][slot].mode == 0 or result.direct[group][slot].mode == 1,
            'invalid MCC setting: ' .. prefix .. 'Mode')
        result.assignments.flat[index] = index
    end
    for index = 1, 2 do
        local group = tostring(index)
        local prefix = 'Group' .. index
        if index == 1 then
            result.groups[group] = binding(values, prefix, -2, 2)
        else
            result.groups[group] = {key=integer(values, prefix .. 'Key', 0, 254), mode=2}
        end
        local mode = result.groups[group].mode
        assert(mode == 2 or (index == 1 and mode == -2),
            'invalid group mode: ' .. prefix)
        result.assignments.groups[group] = {}
        for slot = 1, 4 do
            result.assignments.groups[group][slot] = (index - 1) * 4 + slot
        end
    end
    for slot = 1, 4 do
        result.shared[slot] = binding(values, 'Shared' .. slot, 0, 1)
    end
    return result
end

function M.read(path)
    local file = assert(io.open(path, 'rb'), 'missing MCC config: ' .. path)
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
                assert(values[key] == nil, 'duplicate MCC config key: ' .. key)
                values[key] = assert(tonumber(raw), 'invalid MCC config value: ' .. key)
            end
        end
    end
    return M.decode(values)
end

return M
