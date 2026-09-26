-- Normalize category action declarations without depending on the template engine.
local M = {}

local function array(value, where)
    assert(type(value) == 'table', where .. ': array required')
    local count = #value
    for key in pairs(value) do
        assert(type(key) == 'number' and key >= 1 and key <= count
            and key % 1 == 0, where .. ': array must be contiguous')
    end
    return count
end

local function groups(actions, where)
    assert(type(actions) == 'table' and next(actions), where .. ': actions required')
    if type(actions[1]) == 'table' and actions[1].slot ~= nil then
        array(actions, where)
        local result, positions, seen = {}, {}, {}
        for _, action in ipairs(actions) do
            assert(type(action.type) == 'string' and type(action.slot) == 'string',
                where .. ': action type and slot required')
            local kind = action.type:lower()
            assert(kind == 'ability' or kind == 'consumable',
                where .. ': unsupported quickslot type ' .. action.type)
            local identity = kind .. '\0' .. action.slot
            assert(not seen[identity], where .. ': duplicate quickslot action')
            seen[identity] = true
            local position = positions[kind]
            if not position then
                position = #result + 1
                positions[kind] = position
                result[position] = {name=kind == 'ability' and 'Abilities' or 'Consumables',
                    type=kind, slots=0, slotNames={}}
            end
            local group = result[position]
            group.slots = group.slots + 1
            group.slotNames[#group.slotNames + 1] = action.slot
        end
        return result
    end
    for key, group in pairs(actions) do
        assert(type(key) == 'number' or type(key) == 'string', where .. ': invalid group key')
        assert(type(group) == 'table' and type(group.name) == 'string'
            and type(group.type) == 'string' and type(group.slots) == 'number'
            and group.slots >= 1 and group.slots % 1 == 0,
            where .. ': invalid action group')
    end
    return actions
end

function M.orderedGroups(template, order, categoryActions)
    assert(type(template) == 'table', 'template required')
    local actions = groups(categoryActions or template.actions,
        tostring(template.name) .. '.actions')
    if template.actionOrder ~= nil then
        local count = array(template.actionOrder, 'actionOrder')
        if order ~= nil then
            assert(array(order, 'group order') == count, 'cannot override actionOrder')
            for index = 1, count do
                assert(order[index] == template.actionOrder[index], 'cannot override actionOrder')
            end
        end
        order = template.actionOrder
    end
    local result = {}
    if type(next(actions)) == 'number' then
        assert(order == nil, 'array actions already define order')
        array(actions, 'actions')
        for index, group in ipairs(actions) do
            result[index] = {key=tostring(index), value=group}
        end
    else
        assert(order, tostring(template.name) .. ': explicit group order required')
        array(order, 'group order')
        local used = {}
        for _, key in ipairs(order) do
            assert(type(key) == 'string' and actions[key] and not used[key],
                'invalid or duplicate group order entry')
            used[key] = true
            result[#result + 1] = {key=key, value=actions[key]}
        end
        for key in pairs(actions) do assert(used[key], 'group order missing ' .. key) end
    end
    return result
end

return M
