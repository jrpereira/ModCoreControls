package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
local opened,closed,bindings=0,0,{}
local bridge={}
function bridge.OpenInputComponent(path) opened=opened+1;assert(path=='Component');return opened end
function bridge.CloseInputComponent() closed=closed+1;return true end
function bridge.BindAction(target,action,phase,callback)
    bindings[#bindings+1]={target=target,action=action,phase=phase,callback=callback}
    return #bindings
end
local function object(id) return {GetFullName=function() return 'InputAction /Engine/Transient.'..id end} end
local owner=require('mc_native_callbacks').new(bridge,function(value)return value:GetFullName()end)
local plan={bindings={
    {id='tap',phases={'Triggered'}},
    {id='hold',phases={'Started','Completed','Canceled'}},
}}
local delivered={}
assert(owner:install('Component',{tap=object('Tap'),hold=object('Hold')},plan,function(binding,phase)
    delivered[#delivered+1]=binding.id..':'..phase
end))
assert(#bindings==4 and bindings[2].phase=='Started' and bindings[4].phase=='Canceled')
bindings[2].callback({})
assert(delivered[1]=='hold:Started')
assert(owner:close() and closed==1)

local failed=0
function bridge.BindAction()
    failed=failed+1
    if failed==2 then return nil,'injected failure' end
    return failed
end
local ok,why=owner:install('Component',{tap=object('Tap'),hold=object('Hold')},plan,function()end)
assert(not ok and why:find('injected failure',1,true) and closed==2)
print('PASS native callback ownership and rollback')

-- A Hold key also listens to its rim phases; each phase is bound once.
do
    function bridge.BindAction(target,action,phase,callback)
        bindings[#bindings+1]={target=target,action=action,phase=phase,callback=callback}
        return #bindings
    end
    local first=#bindings
    assert(owner:install('Component',{rim=object('Rim')},{bindings={
        {id='rim',phases={'Triggered'},progressPhases={'Started','Ongoing','Triggered','Completed','Canceled'}},
    }},function() end))
    local phases={}
    for index=first+1,#bindings do phases[#phases+1]=bindings[index].phase end
    assert(table.concat(phases,',')=='Triggered,Started,Ongoing,Completed,Canceled',table.concat(phases,','))
    assert(owner:close())
end
print('PASS a Hold key binds its rim phases once each')
