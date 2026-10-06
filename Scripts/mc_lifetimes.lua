-- Keep UE4SS objects past one call only as UE4SSLuaEventBridge weak handles.
-- UE4SS IsValid reads the object, so a wrapper kept across garbage collection,
-- as when a save loads from a running game, reads freed memory. A weak handle
-- checks the native lifetime first. Without weak handles nothing is kept.
local M={}

local function valid(value)
    local ok,result=pcall(function() return value~=nil and value:IsValid() end)
    return ok and result==true
end

local function service()
    local bridge=rawget(_G,'UE4SSLuaEventBridge')
    local lifetimes=type(bridge)=='table' and bridge.lifetimes or nil
    if type(lifetimes)=='table' and type(lifetimes.weak)=='function' then return lifetimes end
end

-- A handle for a fresh live object (a hook argument, a lookup result or a value
-- read in this call), or nil and why.
function M.keep(object)
    if not valid(object) then return nil,'object is not live' end
    local lifetimes=service()
    if not lifetimes then return nil,'UE4SSLuaEventBridge weak handles unavailable' end
    local ok,handle,why=pcall(lifetimes.weak,object)
    if ok and handle~=nil then return handle end
    return nil,tostring(ok and (why or 'weak handle unavailable') or handle)
end

-- The live object behind a handle, or nil once it died.
function M.live(handle)
    if handle==nil then return nil end
    local ok,object=pcall(function() return handle:get() end)
    if ok and valid(object) then return object end
end

return M
