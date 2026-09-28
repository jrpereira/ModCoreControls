-- Native binding indicators follow MCC's generated actions. Preserve the
-- original action so detach and Lua reload can restore the game's HUD.
local M = {}
local sides = {'Left', 'Top', 'Right', 'Bottom'}
local wheels = {
    ability = {'WBP_AA_Quickslots', 'WBP_AA_Quickslots_Bindings'},
    consumable = {'WBP_HUD_Quickslots', 'WBP_HUD_Quickslots_Bindings'},
}

function M.new(e)
    local records = {}
    local stored = e.load and e.load() or nil
    for line in tostring(stored or ''):gmatch('[^\n]+') do
        local widget, original, assigned = line:match('^([^\t]+)\t([^\t]*)\t([^\t]+)$')
        if widget then records[widget] = {original=original~='' and original or nil,
            assigned=assigned} end
    end
    local function save()
        if not e.save then return true end
        local lines = {}
        for widget, record in pairs(records) do
            lines[#lines+1] = widget..'\t'..(record.original or '')..'\t'..record.assigned
        end
        table.sort(lines)
        return e.save(table.concat(lines, '\n')) ~= false
    end
    local api = {}
    function api:set(widget, action)
        if not e.valid(widget) or not e.valid(action) then return false end
        local current = e.property(widget, 'EnhancedInputAction')
        local widgetPath, actionPath = e.path(widget), e.path(action)
        if not widgetPath or not actionPath then return false end
        local record = records[widgetPath]
        if e.valid(current) and e.same(current, action) then
            -- Set again when only the key mapping changed; CommonUI refreshes
            -- its glyph from the assigned action on this call.
            if not record then return true end
            local ok, result = pcall(e.setAction, widget, action)
            return ok and result ~= false
        end
        local previous = record and record.assigned or nil
        if not record then
            record = {original=e.valid(current) and e.path(current) or nil}
            records[widgetPath] = record
        end
        record.assigned = actionPath
        if not save() then
            if previous then record.assigned=previous else records[widgetPath]=nil end
            return false
        end
        local ok, result = pcall(e.setAction, widget, action)
        return ok and result ~= false
    end
    function api:refresh(actions, plan)
        if type(actions)~='table' or type(plan)~='table' then return false,0 end
        local mapped={ability={},consumable={}}
        for _, definition in ipairs(plan.actions or {}) do
            local action=actions[definition.id]
            if definition.shared then
                mapped.ability[definition.slot]=action
                mapped.consumable[definition.slot]=action
            elseif definition.slot and mapped[definition.type] then
                mapped[definition.type][definition.slot]=action
            end
        end
        local hud=e.hud()
        if not e.valid(hud) then return false,0 end
        local count=0
        for kind, fields in pairs(wheels) do
            local wheel=e.property(hud, fields[1])
            local bindings=e.property(wheel, fields[2])
            for slot, side in ipairs(sides) do
                local widget=e.property(bindings, side)
                if self:set(widget, mapped[kind][slot]) then count=count+1 end
            end
        end
        return count==8,count
    end
    function api:restoreAll()
        local remaining={}
        for widgetPath,record in pairs(records) do
            local widget=e.resolve(widgetPath)
            if e.valid(widget) then
                local current=e.property(widget,'EnhancedInputAction')
                if e.valid(current) and e.path(current)==record.assigned then
                    local original=record.original and e.resolve(record.original) or nil
                    if record.original and not e.valid(original) then
                        remaining[widgetPath]=record
                    else
                        local ok,result=pcall(e.setAction,widget,original)
                        if not ok or result==false then remaining[widgetPath]=record end
                    end
                end
            end
        end
        records=remaining
        return save() and next(remaining)==nil
    end
    return api
end
return M
