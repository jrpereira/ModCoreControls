-- Keep quickslot glyphs aligned with the active MCC bindings and restore native actions.
local M={}
local positions={'Left','Top','Right','Bottom'}
local wheels={
    ability={'WBP_AA_Quickslots','WBP_AA_Quickslots_Bindings'},
    consumable={'WBP_HUD_Quickslots','WBP_HUD_Quickslots_Bindings'},
}

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
    function api:set(widget,action,force)
        if not e.valid(widget) or not e.valid(action) then return false end
        local widgetPath,actionPath=e.path(widget),e.path(action)
        if not widgetPath or not actionPath then return false end
        local record=records[widgetPath]
        local current=currentPath(widget)
        if record and current~=record.assigned and current~=record.pending then
            records[widgetPath]=nil;record=nil
        end
        if current==actionPath and not force then
            if record and record.pending then
                record.assigned=actionPath;record.pending=nil
                return save()
            end
            return true
        end
        if not record then
            record={original=current,assigned=current}
            records[widgetPath]=record
        end
        record.pending=actionPath
        if not save() then return false end
        if not setAction(widget,action) then return false end
        record.assigned=actionPath;record.pending=nil
        return save()
    end
    function api:refresh(actions,plan,opts)
        if type(actions)~='table' or type(plan)~='table' then return false,0,0 end
        opts=opts or {}
        local mapped={ability={},consumable={}}
        for _,binding in ipairs(plan.bindings or {}) do
            local action=actions[binding.id]
            local target=binding.action or {}
            if target.type=='selected' then
                mapped.ability[target.slot]=action
                mapped.consumable[target.slot]=action
            elseif (target.type=='ability' or target.type=='consumable') and target.slot then
                mapped[target.type][target.slot]=action
            end
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
        return complete and completed==expected,completed,expected
    end
    function api:restoreAll()
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
