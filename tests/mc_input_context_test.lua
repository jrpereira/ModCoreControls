package.path='Scripts/?.lua;'..package.path
local created,mapped={},{}
local function object(path)
    local value={path=path,Triggers={}}
    function value:IsValid() return true end
    function value:UnmapAll() mapped[self]={} end
    function value:MapKey(action,key) mapped[self]=mapped[self] or {};mapped[self][#mapped[self]+1]={action,key} end
    return value
end
local e={
    valid=function(value)return value and value:IsValid()end,
    retain=function(kind,name) local v=object(kind..'.'..name);created[kind..'.'..name]=v;return v end,
    initialize=function()end,
    trigger=function(_,name)return object(name)end,
    name=function(value)return value end,
    unwrap=function(value)return value end,
    path=function(value)return value.path end,
    each=function(values,callback)for key,value in pairs(values)do callback(key,value)end end,
    options={},
}
local context=require('mc_input_context').new(e)
local plan={contexts={'exploration','combat'},bindings={
    {id='tap',keyName='One',mode=0},
    {id='hold',keyName='LeftAlt',mode=2},
}}
local actions=context:configure(plan)
assert(actions.tap.Triggers[1].path=='InputTriggerTap')
assert(#actions.hold.Triggers==0)
assert(#mapped[created['InputMappingContext.IMC_MCC_Exploration']]==2)
local input={AppliedInputContexts={}}
function input:IsValid()return true end
local subsystem=object('Subsystem')
function subsystem:AddMappingContext(mapping,priority)self.added={mapping,priority};input.AppliedInputContexts[mapping]=priority end
function subsystem:RemoveMappingContext(mapping)self.removed=mapping;input.AppliedInputContexts[mapping]=nil end
context:attach('exploration',subsystem,7)
assert(subsystem.added[2]==1007 and context:attached('exploration',input))
context:detachAll()
assert(subsystem.removed==created['InputMappingContext.IMC_MCC_Exploration'])
print('PASS Enhanced Input context configuration and lifecycle')
