-- Converts a selected quickslots template and its persisted menu values into
-- stable Enhanced Input action identities. This is deliberately independent
-- of UE4SS so it can be validated without a running game.
local V = require('mc.quickslot_groups')
local M = {}

local function binding(value, where)
    assert(type(value) == 'table', where .. ': binding is required')
    assert(type(value.key) == 'number' and value.key >= 0 and value.key <= 254
        and value.key % 1 == 0, where .. ': invalid key')
    assert(value.mode == 0 or value.mode == 1 or value.mode == 2 or value.mode == -2,
        where .. ': invalid mode')
    return {key = value.key, mode = value.mode}
end

-- Stable MCC action identities for the bridge and input context.
function M.build(template, settings, category)
    assert(type(template) == 'table' and template.category == 'player.quickslots',
        'quickslots template required')
    assert(type(settings) == 'table', 'quickslots settings required')
    local ordered = V.orderedGroups(template, nil, category and category.actions)
    local access = settings.access
    assert(access == 0 or access == 1, 'unsupported quickslots access method')
    local result = {access = access, actions = {}}

    if access == 0 then
        assert(type(settings.direct) == 'table', 'direct quickslots bindings required')
        local primary = settings.PrimaryWheel == 1
            and 'ability' or 'consumable'
        local first, second
        for _, item in ipairs(ordered) do
            assert(item.value.type == 'ability' or item.value.type == 'consumable',
                'unsupported direct quickslot action type: ' .. tostring(item.value.type))
            if item.value.type == primary then first = item else second = item end
        end
        assert(first and second, 'direct quickslots require ability and consumable action groups')
        local number = 0
        for _, item in ipairs({first, second}) do
            local slots = assert(settings.direct[item.key], 'missing direct bindings for ' .. item.key)
            for slot = 1, item.value.slots do
                number = number + 1
                result.actions[#result.actions + 1] = {
                    id = 'IA_ActionSlot' .. number,
                    group = item.key,
                    type = item.value.type,
                    slot = slot,
                    controlIndex = number,
                    contexts = item.value.contexts or (category and category.contexts) or template.contexts,
                    binding = binding(slots[slot], item.key .. ' slot ' .. slot),
                }
            end
        end
        result.actions[#result.actions + 1] = {
            id = 'IA_SlotFlatPreview', preview = true,
            groupIndex = 2, type = second.value.type,
            contexts = (category and category.contexts) or template.contexts,
            binding = binding(settings.preview or {key=0,mode=2}, 'Flat preview'),
        }
        assert(result.actions[#result.actions].binding.mode == 0
            or result.actions[#result.actions].binding.mode == 2,
            'Flat preview mode must be Tap or Hold')
    else
        assert(type(settings.groups) == 'table', 'group quickslots bindings required')
        assert(type(settings.shared) == 'table', 'shared quickslots bindings required')
        local maxSlots = 0
        for index, item in ipairs(ordered) do
            maxSlots = math.max(maxSlots, item.value.slots)
            local selector = binding(settings.groups[item.key], item.key .. ' group binding')
            assert(selector.mode == 2 or (index == 1 and selector.mode == -2)
                or (index == 2 and selector.mode == 0),
                'unsupported group selector mode')
            result.actions[#result.actions + 1] = {
                id = 'IA_GroupSlot' .. index,
                group = item.key,
                type = item.value.type,
                groupIndex = index,
                contexts = item.value.contexts or (category and category.contexts) or template.contexts,
                binding = selector,
            }
        end
        for slot = 1, maxSlots do
            result.actions[#result.actions + 1] = {
                id = 'IA_SharedSlot' .. slot,
                shared = true,
                slot = slot,
                contexts = (category and category.contexts) or template.contexts,
                binding = binding(settings.shared[slot], 'shared slot ' .. slot),
            }
        end
    end
    if access == 0 then
        local used = {}
        for _, definition in ipairs(result.actions) do
            local binding = definition.binding
            if binding.mode >= 0 and binding.key ~= 0 then
                local identity = tostring(binding.key) .. ':' .. tostring(binding.mode)
                if used[identity] then
                    error('duplicate Flat binding: ' .. used[identity] .. ' and ' .. definition.id)
                end
                used[identity] = definition.id
            end
        end
    end
    return result
end

return M
