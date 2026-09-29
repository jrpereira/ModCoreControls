-- Dawnwalker quickslot output used by MCC input callbacks.
local M={}
local positions={'Left','Top','Right','Bottom'}

local function unwrap(value)
    if value==nil then return nil end
    local ok,result=pcall(function() return value:get() end)
    return ok and result or value
end
local function valid(value)
    local ok,result=pcall(function() return value~=nil and value:IsValid() end)
    return ok and result==true
end

function M.new(environment)
    local e=environment or {}
    local isValid=e.valid or valid
    local get=e.unwrap or unwrap
    local owner,generation,cached,presentationNeeded
    local api={}
    function api:bind(nextOwner,nextGeneration)
        if type(nextOwner)~='table' or nextGeneration==nil then return false end
        local same=owner and generation==nextGeneration
        if same then
            for _,field in ipairs({'controller','playerInput','component','subsystem','hud'}) do
                if owner[field]~=nextOwner[field] then same=false;break end
            end
        end
        if not same then
            cached=nil
            presentationNeeded=true
        end
        owner,generation=nextOwner,nextGeneration
        return true
    end
    function api:invalidate(oldGeneration)
        if oldGeneration~=nil and oldGeneration~=generation then return false end
        owner,generation,cached,presentationNeeded=nil,nil,nil,nil
        return true
    end
    function api:hud()
        if not owner then return nil end
        for _,field in ipairs({'controller','playerInput','component','subsystem'}) do
            if owner[field]~=nil and not isValid(owner[field]) then
                cached=nil
                return nil
            end
        end
        local candidate=owner.hud
        if type(e.hudForOwner)=='function' then
            local ok,resolved=pcall(e.hudForOwner,owner)
            if ok and isValid(resolved) then candidate=resolved end
        end
        candidate=get(candidate)
        if not isValid(candidate) then cached=nil;return nil end
        if cached~=candidate then presentationNeeded=true end
        cached=candidate
        return cached
    end
    function api:needsPresentation()
        self:hud()
        return presentationNeeded==true
    end
    function api:activate(kind,slot)
        local field=kind=='ability' and 'WBP_AA_Quickslots'
            or kind=='consumable' and 'WBP_HUD_Quickslots' or nil
        if not field or not positions[slot] then return false end
        local hud=self:hud();local wheel=hud and get(hud[field])
        local button=wheel and get(wheel[positions[slot]])
        if not isValid(button) then return false end
        local ok,result=pcall(function() return button:BP_OnClicked() end)
        return ok and result~=false
    end
    function api:select(group)
        if group~=1 and group~=2 then return false end
        local hud=self:hud();local switcher=hud and get(hud.QuickslotsSwitcher)
        if not isValid(switcher) then return false end
        local counted,count=pcall(function() return switcher:GetChildrenCount() end)
        if not counted or count<1 then return false end
        -- Separate-wheel layouts can leave one child in the switcher.
        if count==1 then presentationNeeded=false;return true end
        local ok,result=pcall(function() return switcher:SetActiveWidgetIndex(group-1) end)
        if ok and result~=false then presentationNeeded=false;return true end
        return false
    end
    function api:reset(group) return self:select(group or 1) end
    return api
end

local function present(state,group,service,force)
    if group~=1 and group~=2 then return false end
    if state.selectedGroup==group and state.pendingGroup==nil and not force then return true end
    local ok,result=pcall(service.select,service,group)
    if ok and result~=false then
        state.selectedGroup=group
        state.pendingGroup=nil
        return true
    end
    state.pendingGroup=group
    return false
end

function M.reconcile(state,service)
    local needed=type(service.needsPresentation)=='function' and service:needsPresentation()
    if not state.pendingGroup and not needed then return true end
    return present(state,state.pendingGroup or state.selectedGroup or 1,service,needed)
end

function M.cancel(state,service)
    state.held={}
    state.gestures={}
    state.sequence=0
    state.selectedGroup=1
    state.pendingGroup=1
    if not service then return false end
    local reset=type(service.reset)=='function' and service.reset or service.select
    local ok,result=pcall(reset,service,1)
    if ok and result~=false then state.pendingGroup=nil;return true end
    return false
end

function M.deliver(state,binding,phase,service)
    local action=binding.action
    if action.type=='ability' or action.type=='consumable' then
        return phase~='Triggered' or service:activate(action.type,action.slot)
    end
    if action.type=='selected' then
        state.gestures=state.gestures or {}
        local key=binding.id or binding
        if phase=='Started' then
            state.gestures[key]={group=state.selectedGroup or 1,fired=false}
            return true
        end
        if phase=='Completed' or phase=='Canceled' then
            state.gestures[key]=nil
            return true
        end
        if phase~='Triggered' then return true end
        local gesture=state.gestures[key]
        if not gesture then
            gesture={group=state.selectedGroup or 1,fired=false}
            state.gestures[key]=gesture
        end
        if gesture.fired then return true end
        local kind=gesture.group==1 and 'ability' or 'consumable'
        local activated=service:activate(kind,action.slot)
        if activated then gesture.fired=true end
        return activated
    end
    assert(action.type=='focus','unsupported runtime action: ' .. tostring(action.type))
    if binding.mode==0 then
        if phase~='Triggered' then return true end
        local previous=state.pendingGroup or state.selectedGroup or 1
        local target=previous==action.group and 1 or action.group
        return present(state,target,service)
    end
    if binding.mode~=2 then return true end
    state.held=state.held or {}
    if phase=='Started' then
        state.sequence=(state.sequence or 0)+1
        state.held[action.group]=state.sequence
        return present(state,action.group,service)
    end
    if phase=='Completed' or phase=='Canceled' then
        state.held[action.group]=nil
        local selected,latest=1,-1
        for group,sequence in pairs(state.held) do
            if sequence>latest then selected,latest=group,sequence end
        end
        return present(state,selected,service)
    end
    return true
end

return M
