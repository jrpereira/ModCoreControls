-- Keep quickslot glyphs aligned with the active MCC bindings and restore native actions.
local M={}
local positions={'Left','Top','Right','Bottom'}
local wheels={
    ability={'WBP_AA_Quickslots','WBP_AA_Quickslots_Bindings'},
    consumable={'WBP_HUD_Quickslots','WBP_HUD_Quickslots_Bindings'},
}

M.positions=positions
M.wheels=wheels

-- The plan binding each quickslot's key indicator shows, by binding id:
-- {ability={[slot]=id},consumable={[slot]=id}}. A grouped key shows on both
-- wheels; a later binding replaces an earlier one, and a display alias shows its
-- source binding.
function M.slots(plan)
    local mapped={ability={},consumable={}}
    for _,binding in ipairs(plan.bindings or {}) do
        local target=binding.action or {}
        if target.type=='selected' then
            mapped.ability[target.slot]=binding.id
            mapped.consumable[target.slot]=binding.id
        elseif (target.type=='ability' or target.type=='consumable') and target.slot then
            mapped[target.type][target.slot]=binding.id
        end
    end
    -- Display aliases intentionally reuse the source action.  Besides the
    -- glyph this preserves its trigger mode, unlike synthesising a text
    -- label for each grouped slot.
    for _,display in ipairs(plan.displays or {}) do
        local target=display.action or {}
        if target.slot and (target.type=='ability' or target.type=='consumable') then
            mapped[target.type][target.slot]=display.source
        end
    end
    return mapped
end

-- {ability={[slot]=true},consumable={...}}: the slots whose indicator shows an MCC
-- key set to Hold. A slot showing the game's own key is never Hold.
function M.hold(plan)
    local byId={}
    for _,binding in ipairs(plan.bindings or {}) do byId[binding.id]=binding end
    local hold={ability={},consumable={}}
    for kind,ids in pairs(M.slots(plan)) do
        for slot=1,4 do
            local binding=ids[slot] and byId[ids[slot]]
            hold[kind][slot]=binding~=nil and binding.keyName~=nil and (binding.mode==1 or binding.mode==2)
        end
    end
    return hold
end

function M.new(e)
    local records={}
    local stored=type(e.load)=='function' and e.load() or nil
    for line in tostring(stored or ''):gmatch('[^\n]+') do
        local widget,original,assigned,pending=line:match('^([^\t]+)\t([^\t]*)\t([^\t]*)\t([^\t]*)$')
        if not widget then widget,original,assigned=line:match('^([^\t]+)\t([^\t]*)\t([^\t]+)$') end
        if widget then
            records[widget]={original=original~='' and original or nil,
                assigned=assigned~='' and assigned or nil,
                pending=pending and pending~='' and pending or nil}
        end
    end
    local function save()
        if type(e.save)~='function' then return true end
        local lines={}
        for widget,record in pairs(records) do
            lines[#lines+1]=widget .. '\t' .. (record.original or '') .. '\t'
                .. (record.assigned or '') .. '\t' .. (record.pending or '')
        end
        table.sort(lines)
        local ok,result=pcall(e.save,table.concat(lines,'\n'))
        return ok and result~=false
    end
    local function currentPath(widget)
        local current=e.property(widget,'EnhancedInputAction')
        return e.valid(current) and e.path(current) or nil
    end
    local function setAction(widget,action)
        local ok,result=pcall(e.setAction,widget,action)
        return ok and result~=false
    end
    local api={}
    local displayRims
    -- Indicators whose rim is forced on, by widget path: the MCC action they show.
    local rimShown={}
    -- A Tap key shows its rim like a Hold key does; every other indicator shows the
    -- game's own display. Set again when an indicator shows another action, as
    -- assigning an action can reset it.
    displayRims=function(plan)
        if type(e.setHoldDisplay)~='function' then return end
        local byId={}
        for _,binding in ipairs(plan.bindings or {}) do byId[binding.id]=binding end
        local hud=e.hud()
        if not e.valid(hud) then return end
        for kind,ids in pairs(M.slots(plan)) do
            local fields=wheels[kind]
            local wheel=e.property(hud,fields[1])
            local bindings=wheel and e.property(wheel,fields[2])
            for slot,position in ipairs(positions) do
                local widget=bindings and e.property(bindings,position)
                local path=widget and e.valid(widget) and e.path(widget)
                if path then
                    local binding=ids[slot] and byId[ids[slot]]
                    local both=plan.keyOutline==nil or plan.keyOutline==2
                    -- A key that is not Hold: Tap, or acting on press.
                    local tap=both and binding~=nil and (binding.keyName~=nil or binding.standardAction~=nil)
                        and (binding.mode==0 or binding.mode==3)
                    local shown=tap and currentPath(widget) or nil
                    if rimShown[path]~=shown and (tap or rimShown[path]~=nil) then
                        if pcall(e.setHoldDisplay,widget,tap) then rimShown[path]=shown end
                    end
                end
            end
        end
    end
    -- The indicators showing a binding, resolved when its hold starts.
    local progressTargets={}
    -- Fills the Hold rim of every indicator showing bindingId: value from 0 to 1.
    -- group (1 abilities, 2 consumables), when given, limits the fill to that wheel:
    -- a Groups key acts on the focused wheel only.
    function api:progress(plan,bindingId,value,group)
        if type(e.setProgress)~='function' or type(plan)~='table' then return false end
        local targets=progressTargets[bindingId]
        if not targets or value==0 then
            targets={}
            local hud=e.hud()
            if e.valid(hud) then
                for kind,ids in pairs(M.slots(plan)) do
                    local fields=wheels[kind]
                    local wheel=e.property(hud,fields[1])
                    local bindings=wheel and e.property(wheel,fields[2])
                    for slot=1,4 do
                        local widget=ids[slot]==bindingId and bindings and e.property(bindings,positions[slot])
                        if widget and e.valid(widget) then
                            targets[#targets+1]={widget=widget,group=kind=='ability' and 1 or 2}
                        end
                    end
                end
            end
            progressTargets[bindingId]=targets
        end
        local done=false
        for _,target in ipairs(targets) do
            local widget=target.widget or target
            if (group==nil or target.group==nil or target.group==group)
                and e.valid(widget) and pcall(e.setProgress,widget,value) then done=true end
        end
        return done
    end
    function api:refresh(actions,plan,opts)
        if type(actions)~='table' or type(plan)~='table' then return false,0,0 end
        opts=opts or {}
        local mapped={ability={},consumable={}}
        for kind,ids in pairs(M.slots(plan)) do
            for slot=1,4 do mapped[kind][slot]=ids[slot] and actions[ids[slot]] end
        end
        local hud=e.hud()
        if not e.valid(hud) then return false,0,0 end
        local completed,expected=0,0
        local complete=true
        local assignments,restorations={},{}
        local journalDirty=false
        for kind,fields in pairs(wheels) do
            local wheel=e.property(hud,fields[1])
            local bindings=e.property(wheel,fields[2])
            for slot,position in ipairs(positions) do
                local widget=e.property(bindings,position)
                local action=mapped[kind][slot]
                if action then
                    expected=expected+1
                    if not e.valid(widget) or not e.valid(action) then complete=false
                    else
                        local widgetPath,actionPath=e.path(widget),e.path(action)
                        if not widgetPath or not actionPath then complete=false
                        else
                            local current=currentPath(widget)
                            local record=records[widgetPath]
                            if record and current~=record.assigned and current~=record.pending then
                                records[widgetPath]=nil;record=nil;journalDirty=true
                            end
                            if current==actionPath and not opts.force then
                                if record and record.pending then
                                    record.assigned=actionPath;record.pending=nil;journalDirty=true
                                end
                                completed=completed+1
                            else
                                if not record then
                                    record={original=current,assigned=current}
                                    records[widgetPath]=record
                                end
                                record.pending=actionPath
                                journalDirty=true
                                assignments[#assignments+1]={widget=widget,action=action,record=record}
                            end
                        end
                    end
                elseif e.valid(widget) then
                    local widgetPath=e.path(widget)
                    local record=widgetPath and records[widgetPath]
                    if record then
                        local current=currentPath(widget)
                        if current==record.assigned or current==record.pending then
                            local original=record.original and e.resolve(record.original) or nil
                            if record.original and not e.valid(original) then complete=false
                            else restorations[#restorations+1]={widget=widget,original=original,path=widgetPath} end
                        else
                            records[widgetPath]=nil
                            journalDirty=true
                        end
                    end
                end
            end
        end
        if journalDirty and not save() then return false,completed,expected end
        for _,entry in ipairs(assignments) do
            if setAction(entry.widget,entry.action) then
                entry.record.assigned=entry.record.pending
                entry.record.pending=nil
                completed=completed+1
                journalDirty=true
            else complete=false end
        end
        for _,entry in ipairs(restorations) do
            if setAction(entry.widget,entry.original) then
                records[entry.path]=nil
                journalDirty=true
            else complete=false end
        end
        if journalDirty and not save() then complete=false end
        displayRims(plan)
        return complete and completed==expected,completed,expected
    end
    function api:restoreAll()
        -- Released indicators show the game's own rim display again.
        pcall(displayRims,{bindings={}})
        local remaining={}
        for widgetPath,record in pairs(records) do
            local widget=e.resolve(widgetPath)
            if e.valid(widget) then
                local current=currentPath(widget)
                if current==record.assigned or current==record.pending then
                    local original=record.original and e.resolve(record.original) or nil
                    if record.original and not e.valid(original) then remaining[widgetPath]=record
                    elseif not setAction(widget,original) then remaining[widgetPath]=record end
                end
            end
        end
        records=remaining
        local persisted=save()
        return persisted and next(remaining)==nil,next(remaining)~=nil
    end
    return api
end

return M
