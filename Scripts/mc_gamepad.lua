-- Read the actions currently assigned to each gamepad button, for display only.
-- Sources are the player's applied mapping contexts and Settings key profile.
local M={}

M.buttons={
    {'Gamepad_FaceButton_Bottom','Face Button Bottom'},
    {'Gamepad_FaceButton_Right','Face Button Right'},
    {'Gamepad_FaceButton_Left','Face Button Left'},
    {'Gamepad_FaceButton_Top','Face Button Top'},
    {'Gamepad_DPad_Up','D-Pad Up'},
    {'Gamepad_DPad_Right','D-Pad Right'},
    {'Gamepad_DPad_Down','D-Pad Down'},
    {'Gamepad_DPad_Left','D-Pad Left'},
    {'Gamepad_LeftShoulder','Left Shoulder'},
    {'Gamepad_RightShoulder','Right Shoulder'},
    {'Gamepad_LeftTrigger','Left Trigger'},
    {'Gamepad_RightTrigger','Right Trigger'},
    {'Gamepad_LeftThumbstick','Left Stick Press'},
    {'Gamepad_RightThumbstick','Right Stick Press'},
    {'Gamepad_Left2D','Left Stick'},
    {'Gamepad_Right2D','Right Stick'},
    {'Gamepad_Special_Left','Special Left'},
    {'Gamepad_Special_Right','Special Right'},
}

local function environment()
    local function unwrap(value)
        if value==nil then return nil end
        local ok,result=pcall(function() return value:get() end)
        return ok and result or value
    end
    local function valid(value)
        local ok,result=pcall(function() return value~=nil and value:IsValid() end)
        return ok and result==true
    end
    local function each(values,callback)
        if values==nil then return end
        pcall(function()
            values:ForEach(function(key,value)
                key,value=unwrap(key),unwrap(value)
                if type(key)=='number' then callback(value) else callback(key,value) end
            end)
        end)
    end
    local function all(class)
        local ok,items=pcall(FindAllOf,class)
        return ok and type(items)=='table' and items or {}
    end
    local function first(class)
        for _,item in ipairs(all(class)) do if valid(item) then return item end end
    end
    local function full(value)
        local ok,name=pcall(function() return value:GetFullName() end)
        return ok and tostring(name) or nil
    end
    return {unwrap=unwrap,valid=valid,each=each,first=first,all=all,full=full}
end

-- The local player's own input and subsystem, matched as the input host matches them:
-- the subsystem whose outer is the controller's player, or the only one there is.
local function player(e)
    if type(e.all)~='function' then return nil end
    local function property(object,name)
        local ok,value=pcall(function() return object[name] end)
        return ok and e.unwrap(value) or nil
    end
    local function same(a,b)
        if a==b then return true end
        local left,right=e.full and e.full(a),e.full and e.full(b)
        return left~=nil and left==right
    end
    for _,controller in ipairs(e.all('BP_PlayerController_C')) do
        local name=e.full and e.full(controller) or ''
        if e.valid(controller) and not name:find('Default__',1,true) then
            local playerInput,owner=property(controller,'PlayerInput'),property(controller,'Player')
            if e.valid(playerInput) and e.valid(owner) then
                local match,count,only=nil,0,nil
                for _,candidate in ipairs(e.all('EnhancedInputLocalPlayerSubsystem')) do
                    if e.valid(candidate) then
                        count=count+1;only=candidate
                        local ok,outer=pcall(function() return e.unwrap(candidate:GetOuter()) end)
                        if ok and e.valid(outer) and same(outer,owner) then match=candidate end
                    end
                end
                local subsystem=match or (count==1 and only or nil)
                if subsystem then return subsystem,playerInput end
            end
        end
    end
end

local function text(value)
    local ok,result=pcall(function() return value:ToString() end)
    result=ok and type(result)=='string' and result:match('^%s*(.-)%s*$') or nil
    return result~='' and result or nil
end

local function actionName(e,action)
    if not e.valid(action) then return nil end
    local name=text(action.ActionDescription)
    if not name then
        local mappable=e.unwrap(action.PlayerMappableKeySettings)
        name=mappable and text(mappable.DisplayName)
    end
    if not name then
        local ok,raw=pcall(function() return action:GetFName():ToString() end)
        name=ok and raw and (raw:gsub('^IA_','')) or nil
    end
    -- Menu choices are '|'-separated; keep labels to one choice.
    return name and (name:gsub('[|;\r\n]',' ')) or nil
end

-- Returns {{key,label,actions={...}}...} or nil when no player input is live.
function M.read(e)
    e=e or environment()
    -- Without a matched player, the first live objects stand in.
    local subsystem,playerInput=player(e)
    if not subsystem then
        subsystem=e.first('EnhancedInputLocalPlayerSubsystem')
        playerInput=e.first('EnhancedPlayerInput')
    end
    if not subsystem and not playerInput then return nil end
    local assigned={}
    local function add(key,action)
        local keyName=key and text(key.KeyName)
        local name=actionName(e,action)
        if not keyName or not name then return end
        local list=assigned[keyName] or {}
        assigned[keyName]=list
        for _,existing in ipairs(list) do if existing==name then return end end
        list[#list+1]=name
    end
    if playerInput then
        e.each(playerInput.AppliedInputContexts,function(context)
            if e.valid(context) then
                e.each(context.Mappings,function(entry) add(entry.Key,e.unwrap(entry.Action)) end)
            end
        end)
    end
    if subsystem then
        local ok,settings=pcall(function() return e.unwrap(subsystem:GetUserSettings()) end)
        local profile=ok and e.valid(settings)
            and e.unwrap(settings:GetCurrentKeyProfile()) or nil
        if e.valid(profile) then
            e.each(profile.PlayerMappedKeys,function(_,row)
                e.each(e.unwrap(row).Mappings,function(entry)
                    add(entry.CurrentKey,e.unwrap(entry.AssociatedInputAction))
                end)
            end)
        end
    end
    local result={}
    for _,button in ipairs(M.buttons) do
        local actions=assigned[button[1]] or {}
        table.sort(actions)
        result[#result+1]={key=button[1],label=button[2],actions=actions}
    end
    return result
end

return M
