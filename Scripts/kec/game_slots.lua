-- Snapshot the player's choices through the game's character-development APIs.
-- Call on the game thread when the loadout changes; there is no polling here.
local M = {}

local function call(object, method, ...)
    if not object then return nil end
    local found, fn = pcall(function() return object[method] end)
    if not found or type(fn) ~= 'function' then return nil end
    local ok, value = pcall(fn, object, ...)
    return ok and value or nil
end

local function live(value)
    if value == nil then return nil end
    local ok, valid = pcall(function() return value:IsValid() end)
    return ok and valid == true and value or nil
end

function M.read(quickslots, development)
    local result = {ability={}, weapon={}, witchcraft={}, vampire={}, consumable={}}
    -- EQuickslot is Left/Top/Right/Bottom = 0..3; EDayPhase is Day=1,
    -- Night=2. Together these are the game's eight ability wheel positions.
    for phase = 1, 2 do
        for slot = 0, 3 do
            local ability = live(call(quickslots, 'GetAbilityInSlot', slot, phase))
            if ability then
                result.ability[(phase - 1) * 4 + slot + 1] =
                    {unlocked=true, action=ability}
            end
        end
    end
    -- ECharacterDevelopmentAbilityType: Combat=1, Vampire=2, Magic=4.
    for _, source in ipairs({{name='weapon', kind=1},
            {name='vampire', kind=2}, {name='witchcraft', kind=4}}) do
        local limit = call(development, 'GetEquippedAbilityTypeLimit', source.kind)
        if type(limit) == 'number' and limit >= 0 then
            for slot = 0, math.min(4, math.floor(limit)) - 1 do
                result[source.name][slot + 1] = {
                    unlocked=true,
                    action=live(call(development, 'GetEquippedAbility', source.kind, slot)),
                }
            end
        end
    end
    return result
end

return M
