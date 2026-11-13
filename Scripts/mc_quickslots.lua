-- Dawnwalker quickslot output used by MCC input callbacks.
local Events=require('mc_events')
local Lifetimes=require('mc_lifetimes')
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

-- The owner and its HUD outlive the call that found them,
-- so they are kept as weak handles: a save load frees them while bound.
local fields={'controller','playerInput','component','subsystem','hud'}

function M.new(environment)
    local e=environment or {}
    local isValid=e.valid or valid
    local get=e.unwrap or unwrap
    local keep,live=e.keep or Lifetimes.keep,e.live or Lifetimes.live
    local owner,generation,cached,presentationNeeded
    -- A handle's get returns a new wrapper, so the same object is matched by path.
    local path=e.path or function(object)
        local ok,name=pcall(function() return object:GetFullName() end)
        return ok and name or nil
    end
    local function sameObject(a,b)
        if a==b then return true end
        if not (isValid(a) and isValid(b)) then return false end
        local left=path(a)
        return left~=nil and left==path(b)
    end
    local api={}
    function api:bind(nextOwner,nextGeneration)
        if type(nextOwner)~='table' or nextGeneration==nil then return false end
        local same=owner and generation==nextGeneration
        if same then
            for _,field in ipairs(fields) do
                if not sameObject(live(owner[field]),get(nextOwner[field])) then same=false;break end
            end
        end
        if not same then
            cached=nil
            presentationNeeded=true
        end
        local kept={}
        for _,field in ipairs(fields) do
            if nextOwner[field]~=nil then
                kept[field]=keep(nextOwner[field])
                if kept[field]==nil then owner=nil;return false end
            end
        end
        owner,generation=kept,nextGeneration
        return true
    end
    function api:invalidate(oldGeneration)
        if oldGeneration~=nil and oldGeneration~=generation then return false end
        owner,generation,cached,presentationNeeded=nil,nil,nil,nil
        return true
    end
    function api:hud()
        if not owner then return nil end
        local current={}
        for _,field in ipairs(fields) do
            if owner[field]~=nil then
                current[field]=live(owner[field])
                if current[field]==nil and field~='hud' then
                    cached=nil
                    return nil
                end
            end
        end
        local candidate=current.hud
        if type(e.hudForOwner)=='function' then
            local ok,resolved=pcall(e.hudForOwner,current)
            if ok and isValid(resolved) then candidate=resolved end
        end
        candidate=get(candidate)
        if not isValid(candidate) then cached=nil;return nil end
        if not sameObject(live(cached),candidate) then
            presentationNeeded=true
            cached=keep(candidate)
        end
        return candidate
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
    -- The game's active wheel, the one its slot keys fire, is set by the HUD's own
    -- Set AA Quickslots Showed, as the game's toggle does. Routing follows that state
    -- wherever the wheels sit; the setter also selects the native switcher's page.
    function api:select(group)
        if group~=1 and group~=2 then return false end
        local hud=self:hud()
        if not isValid(hud) then return false end
        local ok=pcall(function() return hud['Set AA Quickslots Showed'](hud,group==1,false) end)
        if ok then presentationNeeded=false end
        return ok
    end
    function api:reset(group) return self:select(group or 1) end
    function api:emit(name,payload)
        if type(e.emit)~='function' then return true end
        local ok,result=pcall(e.emit,name,payload)
        return ok and result~=false
    end
    return api
end

-- selectedGroup is the group last activated and published; nil until the first
-- activation. Every change of it is published, so consumers never assume a focus.
local function publish(state,group,service)
    local previous=state.selectedGroup
    state.selectedGroup=group
    if previous~=group and type(service.emit)=='function' then
        pcall(service.emit,service,Events.focus,{group={from=previous,to=group}})
    end
end

local function present(state,group,service,force)
    if group~=1 and group~=2 then return false end
    if state.selectedGroup==group and state.pendingGroup==nil and not force then return true end
    local ok,result=pcall(service.select,service,group)
    if ok and result~=false then
        state.pendingGroup=nil
        publish(state,group,service)
        return true
    end
    state.pendingGroup=group
    return false
end

function M.reconcile(state,service)
    local needed=type(service.needsPresentation)=='function' and service:needsPresentation()
    local group=state.pendingGroup or state.selectedGroup
    if group==nil or (not state.pendingGroup and not needed) then return true end
    return present(state,group,service,needed)
end

-- Focus the other wheel, as the game's own toggle would.
function M.flip(state,service)
    local current=state.pendingGroup or state.selectedGroup or state.defaultGroup
    if current==nil then return false end
    return present(state,current==1 and 2 or 1,service)
end

-- Return the native wheel to Default. A failed reset keeps the last published
-- group and leaves Default pending for the next presentation.
function M.cancel(state,service)
    state.gestures={}
    local defaultGroup=state.defaultGroup
    if defaultGroup==nil then return true end
    state.pendingGroup=defaultGroup
    if not service then return false end
    local reset=type(service.reset)=='function' and service.reset or service.select
    local ok,result=pcall(reset,service,defaultGroup)
    if ok and result~=false then
        state.pendingGroup=nil
        publish(state,defaultGroup,service)
        return true
    end
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
            state.gestures[key]={group=state.selectedGroup,fired=false}
            return true
        end
        if phase=='Completed' or phase=='Canceled' then
            state.gestures[key]=nil
            return true
        end
        if phase~='Triggered' then return true end
        local gesture=state.gestures[key]
        if not gesture or gesture.group==nil then
            gesture={group=state.selectedGroup,fired=false}
            state.gestures[key]=gesture
        end
        if gesture.fired then return true end
        if gesture.group==nil then return false end
        local kind=gesture.group==1 and 'ability' or 'consumable'
        local activated=service:activate(kind,action.slot)
        if activated then gesture.fired=true end
        return activated
    end
    if action.type=='flip' then
        return phase~='Triggered' or M.flip(state,service)
    end
    assert(action.type=='focus','unsupported runtime action: ' .. tostring(action.type))
    -- Tap: a group key set to Tap fires on press (mode 3) or, declared directly, on release.
    if binding.mode==0 or binding.mode==3 then
        if phase~='Triggered' then return true end
        -- With a key on each wheel, each key focuses its own wheel.
        if binding.direct then return present(state,action.group,service) end
        -- With one group key, tapping it while its group is focused returns to
        -- Default, or to the other wheel when that group is Default.
        local previous=state.pendingGroup or state.selectedGroup
        local default=state.defaultGroup~=action.group and state.defaultGroup or 3-action.group
        local target=previous==action.group and default or action.group
        return present(state,target,service)
    end
    if binding.mode~=2 then return true end
    -- Hold: press shows the key's wheel, release returns to Default.
    if phase=='Started' then return present(state,action.group,service) end
    if phase=='Completed' or phase=='Canceled' then
        if state.defaultGroup==nil then return true end
        return present(state,state.defaultGroup,service)
    end
    return true
end

return M
