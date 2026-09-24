-- Dawnwalker quickslot delivery for KEC's control host. KET owns visuals only.
local M = {}
local names = {'Left', 'Top', 'Right', 'Bottom'}

local function unwrap(value)
    if value == nil then return nil end
    local ok, object = pcall(function() return value:get() end)
    return ok and object or value
end

local function valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function hud()
    if type(FindAllOf) ~= 'function' then return nil end
    local ok, found = pcall(FindAllOf, 'WBP_GameHUD_C')
    if not ok or type(found) ~= 'table' then return nil end
    for _, candidate in ipairs(found) do
        if valid(candidate) then
            local named, full = pcall(function() return candidate:GetFullName() end)
            if named and tostring(full):find('/Engine/Transient', 1, true) then
                return candidate
            end
        end
    end
end

function M.new()
    local service = {}

    function service:activateQuickslot(kind, slot)
        local field = kind == 'ability' and 'WBP_AA_Quickslots'
            or kind == 'consumable' and 'WBP_HUD_Quickslots' or nil
        if not field or not names[slot] then return false end
        local current = hud()
        if not current then return false end
        local wheel = unwrap(current[field])
        local button = wheel and unwrap(wheel[names[slot]])
        if not valid(button) then return false end
        return pcall(function() button:BP_OnClicked() end)
    end

    function service:selectQuickslotGroup(index)
        if index ~= 1 and index ~= 2 then return false end
        local current = hud()
        if not current then return false end
        local switcher = unwrap(current.QuickslotsSwitcher)
        if not valid(switcher) then return false end
        -- A visual template may have detached one wheel. KEC still selects
        -- the control group, but there is no second switcher child to show.
        local ok, count = pcall(function() return switcher:GetChildrenCount() end)
        if not ok then return false end
        if count < 2 then return true end
        return pcall(function() switcher:SetActiveWidgetIndex(index - 1) end)
    end

    return service
end

return M
