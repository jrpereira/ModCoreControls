-- Test double for UE4SSLuaEventBridge weak handles (API 6), installed as the
-- global bridge's lifetimes. alive(object) is the native lifetime; by default
-- the object's IsValid. Like the bridge, a handle whose object died stays empty.
local M={}

local function isValid(object)
    local ok,value=pcall(function() return object:IsValid() end)
    return ok and value==true
end

function M.service(alive)
    alive=alive or isValid
    local service={held=0}
    local Handle={}
    Handle.__index=Handle
    function Handle:get()
        if self.object~=nil and alive(self.object) then return self.object end
        self.object=nil
    end
    function Handle:release() self.object=nil end
    function service.weak(object)
        if object==nil or not alive(object) then return nil,'object must be a live UE4SS UObject wrapper' end
        service.held=service.held+1
        return setmetatable({object=object},Handle)
    end
    return service
end

function M.install(alive)
    local service=M.service(alive)
    local bridge=rawget(_G,'UE4SSLuaEventBridge')
    if type(bridge)~='table' then bridge={};rawset(_G,'UE4SSLuaEventBridge',bridge) end
    bridge.lifetimes=service
    return service
end

return M
