-- An underline on each quickslot key indicator whose key is set to Hold.
--
-- A key indicator is a leaf widget, so its mark is a sibling in the key's own
-- overlay: an 85x85 box holding a black bar, named MCC_HoldMark_<wheel>_<position>.
-- The box copies its key's placement (slot padding and alignment, render transform
-- and pivot, visibility, render opacity), so it sits, scales, hides and fades with
-- the key under any layout. Placement is copied on every refresh and whenever ModCore
-- Templates reports a layout pass (place). Marks found by name from an earlier Lua
-- state are reused or removed.
local KeyIndicators=require('mc_key_indicators')
local M={}
-- Layout units of the key's 85x85 box: the bar is 51 wide, centred, 11 thick, black at 80%
-- opacity, and its bottom edge sits 15 above the box's bottom.
M.box=85
M.bar={width=51,thickness=11,bottom=15,opacity=.8}
M.prefix='MCC_HoldMark_'

function M.name(kind,position) return M.prefix..kind..'_'..position end

-- e: valid, path, property(object,name), hud(), parent(widget), find(parent,name),
-- create(parent,name), placement(key), apply(mark,placement), remove(mark), log
function M.new(e)
    local log=e.log or {debug=function() end,warn=function() end}
    -- name -> {mark=,keyPath=,applied=<placement signature>}
    local marks={}
    -- The HUD whose overlays were last searched for marks left by an earlier state.
    local swept
    local function signature(placement)
        local parts={}
        for _,field in ipairs({'padLeft','padTop','padRight','padBottom','horizontal','vertical',
            'x','y','scaleX','scaleY','shearX','shearY','angle','pivotX','pivotY','visibility','opacity'}) do
            parts[#parts+1]=tostring(placement[field])
        end
        return table.concat(parts,' ')
    end
    local function place(record,key)
        local ok,placement=pcall(e.placement,key)
        if not ok or type(placement)~='table' then
            log.debug('hold mark placement unreadable: ',placement)
            return false
        end
        local value=signature(placement)
        if value==record.applied then return true end
        local applied,why=pcall(e.apply,record.mark,placement)
        if not applied then log.debug('hold mark placement failed: ',why);record.applied=nil;return false end
        record.applied=value
        return true
    end
    local function remove(mark)
        if e.valid(mark) then
            local ok,why=pcall(e.remove,mark)
            if not ok then log.debug('hold mark removal failed: ',why) end
        end
    end
    -- Each live key indicator: kind ('ability' or 'consumable'), slot, position, key.
    local function keys(hud)
        local found={}
        for kind,fields in pairs(KeyIndicators.wheels) do
            local wheel=e.property(hud,fields[1])
            local bindings=wheel and e.property(wheel,fields[2])
            for slot,position in ipairs(KeyIndicators.positions) do
                local key=bindings and e.property(bindings,position)
                if e.valid(key) then
                    found[#found+1]={kind=kind,slot=slot,position=position,key=key}
                end
            end
        end
        return found
    end
    local api={}
    -- Adds, keeps or removes each slot's mark for plan (nil: no slot is Hold) and
    -- copies its key's placement.
    function api:refresh(plan)
        local hold=plan and KeyIndicators.hold(plan) or {ability={},consumable={}}
        local hud=e.hud()
        local seen={}
        if e.valid(hud) then
            local hudPath=e.path(hud)
            local sweep=hudPath~=swept
            for _,entry in ipairs(keys(hud)) do
                local id=M.name(entry.kind,entry.position)
                local keyPath=e.path(entry.key)
                local record=marks[id]
                if record and not (e.valid(record.mark) and record.keyPath==keyPath) then
                    remove(record.mark);marks[id]=nil;record=nil
                end
                local wanted=hold[entry.kind][entry.slot]
                -- An overlay is searched for a mark by name only when one is needed
                -- and not tracked, or once per HUD for marks of an earlier state.
                local parent=((record==nil and wanted) or sweep) and e.parent(entry.key) or nil
                local existing=parent and e.valid(parent) and e.find(parent,id) or nil
                if wanted then
                    if not record then
                        local mark=existing
                        if not e.valid(mark) then
                            local ok,result=pcall(e.create,parent,id)
                            if ok then mark=result else log.warn('hold mark unavailable: ',id,': ',result) end
                        end
                        if e.valid(mark) then
                            record={mark=mark,keyPath=keyPath}
                            marks[id]=record
                        end
                    end
                    if record then
                        seen[id]=true
                        place(record,entry.key)
                    end
                else
                    if record then remove(record.mark);marks[id]=nil end
                    if existing and not (record and existing==record.mark) then remove(existing) end
                end
            end
            swept=hudPath
        end
        -- Marks of keys no longer on the HUD.
        for id,record in pairs(marks) do
            if not seen[id] then remove(record.mark);marks[id]=nil end
        end
        return true
    end
    -- Copies each mark's key placement again, after a layout pass moved keys.
    function api:place()
        local hud=e.hud()
        if not e.valid(hud) then return false end
        for _,entry in ipairs(keys(hud)) do
            local record=marks[M.name(entry.kind,entry.position)]
            if record and e.valid(record.mark) and record.keyPath==e.path(entry.key) then
                place(record,entry.key)
            end
        end
        return true
    end
    -- Removes every mark, also those of an earlier state on the current HUD.
    function api:clear()
        swept=nil
        return self:refresh(nil)
    end
    return api
end

return M
