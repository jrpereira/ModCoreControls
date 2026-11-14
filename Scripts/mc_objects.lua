-- UE4SS object helpers shared by MCC's modules.
local M={}

-- The object behind a UE4SS reference (RemoteObject, a property value), or the value.
function M.unwrap(value)
    if value==nil then return nil end
    local ok,result=pcall(function() return value:get() end)
    return ok and result or value
end

function M.valid(value)
    local ok,result=pcall(function() return value~=nil and value:IsValid() end)
    return ok and result==true
end

-- The live player controllers, without class defaults. e: all, valid, full.
function M.controllers(e)
    local result={}
    for _,controller in ipairs(type(e.all)=='function' and e.all('BP_PlayerController_C') or {}) do
        local name=type(e.full)=='function' and e.full(controller) or ''
        if e.valid(controller) and not name:find('Default__',1,true) then result[#result+1]=controller end
    end
    return result
end

-- The Enhanced Input subsystem of a local player: the one whose outer is the player,
-- else the only one there is. e: all, valid, unwrap. options:
--   same(outer,player)  whether a subsystem's outer is the player (required);
--   property(object,name)  when given, the Outer property is read before GetOuter();
--   onlyUnknown  the only subsystem stands in only while its outer is unknown.
function M.subsystem(e,player,options)
    local match,count,only,unknown=nil,0,nil,nil
    for _,candidate in ipairs(type(e.all)=='function' and e.all('EnhancedInputLocalPlayerSubsystem') or {}) do
        if e.valid(candidate) then
            count=count+1;only=candidate
            local outer=options.property and options.property(candidate,'Outer') or nil
            if not e.valid(outer) then
                local ok,value=pcall(function() return candidate:GetOuter() end)
                outer=ok and e.unwrap(value) or nil
            end
            if e.valid(outer) then
                if options.same(outer,player) then match=candidate end
            else unknown=candidate end
        end
    end
    if match then return match end
    if count==1 then return options.onlyUnknown and unknown or only end
end

return M
