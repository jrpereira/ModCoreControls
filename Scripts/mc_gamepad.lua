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
    local function first(class)
        local ok,items=pcall(FindAllOf,class)
        if not ok or type(items)~='table' then return nil end
        for _,item in ipairs(items) do if valid(item) then return item end end
    end
    return {unwrap=unwrap,valid=valid,each=each,first=first}
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
    local subsystem=e.first('EnhancedInputLocalPlayerSubsystem')
    local playerInput=e.first('EnhancedPlayerInput')
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
