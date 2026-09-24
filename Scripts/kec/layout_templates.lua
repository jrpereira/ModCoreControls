-- Declarative action layouts. A .tpl is data; it is never executed as Lua.
local M = {}

local function trim(value) return value:match('^%s*(.-)%s*$') end

local function split(value, delimiter)
    local result, start = {}, 1
    while true do
        local at = value:find(delimiter, start, true)
        if not at then
            result[#result + 1] = trim(value:sub(start))
            return result
        end
        result[#result + 1] = trim(value:sub(start, at - 1))
        start = at + #delimiter
    end
end

local function identifier(value, where)
    assert(type(value) == 'string' and value:match('^[%a][%w_]*$'),
        where .. ': invalid identifier')
    return value
end

local function integer(value, low, high, where)
    local number = tonumber(value)
    assert(number and number % 1 == 0 and number >= low and number <= high,
        where .. ': invalid number')
    return number
end

local function parseGroup(value, seen)
    local parts = split(value, '|')
    assert(#parts == 8,
        'group requires id, label, key, phase, initial count, source, offset, slots')
    local id = identifier(parts[1], 'group id')
    assert(not seen[id], 'duplicate group: ' .. id)
    seen[id] = true
    assert(parts[2] ~= '', id .. ': label required')
    local key = integer(parts[3], 1, 3, id .. ' key')
    local phase = parts[4]
    assert(phase == 'always' or phase == 'day' or phase == 'night',
        id .. ': phase must be always, day, or night')
    local source = identifier(parts[6], id .. ' source')
    local offset = integer(parts[7], 1, 12, id .. ' offset')
    local labels, seenSlots = {}, {}
    for _, label in ipairs(split(parts[8], ',')) do
        local slot = identifier(label, id .. ' slot')
        assert(not seenSlots[slot:lower()], id .. ': duplicate slot ' .. slot)
        seenSlots[slot:lower()] = true
        labels[#labels + 1] = slot
    end
    assert(#labels > 0 and offset + #labels - 1 <= 12,
        id .. ': slots exceed source capacity')
    local initial = integer(parts[5], 0, #labels, id .. ' initial count')
    local actions = {}
    for index = 1, #labels do
        actions[index] = 'quickslot.' .. source .. '.' .. (offset + index - 1)
    end
    return {id=id, label=parts[2], key=key, phase=phase,
        initiallyVisible=initial, source=source, offset=offset,
        slotLabels=labels, actions=actions}
end

local function parsePreset(value, seen)
    local parts = split(value, '|')
    assert(#parts == 2 and parts[1] ~= '' and not seen[parts[1]],
        'preset requires a unique name and group sizes')
    seen[parts[1]] = true
    local sizes, total = {}, 0
    for _, raw in ipairs(split(parts[2], ',')) do
        local size = integer(raw, 1, 12, 'preset group size')
        sizes[#sizes + 1] = size
        total = total + size
    end
    assert(total == 12, 'preset must contain exactly 12 slots')
    return {name=parts[1], sizes=sizes}
end

function M.parse(content)
    assert(type(content) == 'string', 'layout template content required')
    local layout = {groups={}, presets={}, fixed={}}
    local fields, groupIds, presetNames = {}, {}, {}
    for line in (content:gsub('\r\n', '\n'):gsub('\r', '\n') .. '\n'):gmatch('(.-)\n') do
        line = line:gsub('%s*#.*$', '')
        if line:find('%S') then
            local key, value = line:match('^%s*([%a_]+)%s*:%s*(.-)%s*$')
            assert(key and value ~= '', 'invalid layout template line: ' .. line)
            if key == 'group' then
                layout.groups[#layout.groups + 1] = parseGroup(value, groupIds)
            elseif key == 'preset' then
                layout.presets[#layout.presets + 1] = parsePreset(value, presetNames)
            elseif key == 'title' or key == 'section' or key == 'order' then
                assert(not fields[key], 'duplicate layout template field: ' .. key)
                fields[key] = true
                layout[key] = value
            else
                error('invalid layout template field: ' .. key)
            end
        end
    end
    assert(layout.title and layout.section, 'layout requires title and section')
    assert((#layout.groups > 0) ~= (#layout.presets > 0),
        'layout requires either groups or presets')
    if #layout.groups > 0 then
        assert(not layout.order, 'order applies only to Flexi Slots')
        for _, phase in ipairs({'day', 'night'}) do
            local used, total = {}, 0
            for _, group in ipairs(layout.groups) do
                if group.phase == 'always' or group.phase == phase then
                    assert(not used[group.key], 'duplicate group key during ' .. phase)
                    used[group.key] = true
                    total = total + #group.actions
                end
            end
            assert(total == 12, 'layout needs 12 slots during ' .. phase)
            for key = 1, 3 do assert(used[key], 'layout needs three group keys') end
        end
    else
        assert(layout.order == 'ability, consumable'
            or layout.order == 'consumable, ability',
            'Flexi Slots needs ability/consumable order')
        assert(#layout.presets == 3, 'Flexi Slots needs three grouping presets')
    end
    return layout
end

function M.activeGroups(layout, phase)
    assert(type(layout) == 'table' and type(layout.groups) == 'table',
        'layout groups required')
    assert(phase == 'day' or phase == 'night', 'phase must be day or night')
    local groups = {}
    for _, group in ipairs(layout.groups) do
        if group.phase == 'always' or group.phase == phase then
            groups[#groups + 1] = group
        end
    end
    return groups
end

-- `available` comes from the game and the player's choices. Entries may be
-- action identities or {unlocked=true, action=identity} for empty open slots.
function M.resolve(layout, phase, available)
    assert(type(available) == 'table', 'game availability table required')
    local result = {}
    for _, group in ipairs(M.activeGroups(layout, phase)) do
        local source = available[group.source] or {}
        assert(type(source) == 'table', 'game source must be a table: ' .. group.source)
        local positions = {}
        for index, action in ipairs(group.actions) do
            local value = source[group.offset + index - 1]
            local unlocked = value ~= nil and value ~= false
            local selected = value
            if type(value) == 'table' then
                unlocked = value.unlocked == true
                selected = value.action
            end
            positions[index] = {id=action, label=group.slotLabels[index],
                visible=index <= group.initiallyVisible or unlocked,
                available=unlocked, action=selected}
        end
        result[#result + 1] = {id=group.id, label=group.label, key=group.key,
            positions=positions}
    end
    return result
end

function M.flexiGroups(layout, name, order)
    assert(type(layout) == 'table' and #layout.presets > 0,
        'flexible layout required')
    order = order or layout.order
    assert(order == 'ability, consumable' or order == 'consumable, ability',
        'invalid Flexi Slots order')
    for _, preset in ipairs(layout.presets) do
        if preset.name == name then
            local categories = split(order, ',')
            local sequence = {}
            for _, category in ipairs(categories) do
                local count = category == 'ability' and 8 or 4
                for slot = 1, count do
                    sequence[#sequence + 1] = 'quickslot.' .. category .. '.' .. slot
                end
            end
            local groups, first = {}, 1
            for index, size in ipairs(preset.sizes) do
                local actions = {}
                for column = 1, size do
                    actions[column] = sequence[first + column - 1]
                end
                groups[index] = {id='flexi_' .. index, label='Row ' .. index,
                    first=first, count=size, actions=actions}
                first = first + size
            end
            return {order=categories, groups=groups}
        end
    end
    error('unknown Flexi Slots preset: ' .. tostring(name))
end

function M.load(path)
    assert(type(path) == 'string' and path:match('%.tpl$'),
        'layout template path must end in .tpl')
    local file = assert(io.open(path, 'rb'))
    local content = assert(file:read('*a'))
    assert(file:close())
    return M.parse(content)
end

return M
