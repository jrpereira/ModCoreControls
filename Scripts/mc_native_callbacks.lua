-- Own bridge subscriptions for generated MCC Input Actions.
local M={}

function M.new(bridge,fullName)
    local active
    local api={}
    local function actionPath(action)
        local name=assert(fullName(action),'generated Input Action has no name')
        return assert(name:match('^%S+%s+(.+)$'),'unexpected Input Action name: ' .. name)
    end
    function api:close()
        if not active then return true end
        local target=active
        local called,ok,why=pcall(bridge.CloseInputComponent,target)
        if called and ok then active=nil;return true end
        return false,called and why or ok
    end
    function api:install(componentPath,actions,plan,callback)
        assert(type(callback)=='function','native callback required')
        local closed,closeWhy=self:close()
        if not closed then return false,closeWhy end
        local opened,target,why=pcall(bridge.OpenInputComponent,componentPath)
        if not opened then return false,target end
        if not target then return false,why end
        active=target
        for _,binding in ipairs(plan.bindings) do
            local action=assert(actions[binding.id],'input action missing: ' .. tostring(binding.id))
            for _,phase in ipairs(binding.phases) do
                local bound,handle,bindWhy=pcall(bridge.BindAction,target,actionPath(action),phase,function(event)
                    callback(binding,phase,event)
                end)
                if not bound or not handle then
                    local removed,removeWhy=self:close()
                    local reason=bound and bindWhy or handle
                    return false,tostring(reason) .. (removed and '' or '; cleanup: ' .. tostring(removeWhy))
                end
            end
        end
        return true
    end
    function api:hasActive() return active~=nil end
    return api
end

return M
