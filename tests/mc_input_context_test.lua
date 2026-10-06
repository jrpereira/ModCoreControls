package.path='Scripts/?.lua;'..package.path
local created,mapped={},{}
local function object(path)
    local value={path=path,Triggers={}}
    function value:IsValid() return true end
    function value:UnmapAll() mapped[self]={} end
    function value:MapKey(action,key)
        mapped[self]=mapped[self] or {}
        local entry={action,key,Triggers={}}
        mapped[self][#mapped[self]+1]=entry
        return entry
    end
    return value
end
local e={
    valid=function(value)return value and value:IsValid()end,
    retain=function(kind,name) local v=object(kind..'.'..name);created[kind..'.'..name]=v;return v end,
    initialize=function()end,
    trigger=function(_,name)local v=object(name);v.full=name..' /Test/'..name;return v end,
    name=function(value)return value end,
    unwrap=function(value)return value end,
    path=function(value)return value.path end,
    each=function(values,callback)
        for key,value in pairs(values) do
            if type(key)=='number' then callback(value,key) else callback(key,value) end
        end
        return true
    end,
    full=function(value)return value.full or value.path end,
    options={},
}
local context=require('mc_input_context').new(e)
-- The game's own contexts; MCC maps into them and removes only its own keys.
local function game(path)
    local value=object(path);value.Mappings={}
    function value:MapKey(action,key)self.Mappings[#self.Mappings+1]={Action=action,Key=key}end
    function value:UnmapKey(action,key)
        for index=#self.Mappings,1,-1 do
            local entry=self.Mappings[index]
            if entry.Action==action and entry.Key.KeyName==key.KeyName then table.remove(self.Mappings,index) end
        end
    end
    return value
end
local world,combat=game('/Game/IMC_OW.IMC_OW'),game('/Game/IMC_RTCombat.IMC_RTCombat')
local nativeEntry={Action=object('IA_Native'),Key={KeyName='One'}}
world.Mappings[1]=nativeEntry
local input={AppliedInputContexts={[world]=5}}
function input:IsValid()return true end
local plan={contexts={'exploration','combat'},bindings={
    {id='tap',keyName='One',mode=0},
    {id='hold',keyName='LeftAlt',mode=2},
}}
local actions=context:configure(plan)
assert(actions.tap.Triggers[1].path=='InputTriggerTap')
assert(#actions.hold.Triggers==0)
assert(#world.Mappings==1,'configure alone must not map keys')
context:attach('exploration',nil,5,world)
assert(#world.Mappings==3 and world.Mappings[2].Action==actions.tap and world.Mappings[3].Action==actions.hold)
assert(context:attached('exploration',input),'mapped and applied context must count as attached')
world.Mappings[3]=nil
assert(not context:attached('exploration',input),'a lost MCC entry must count as detached')
context:attach('exploration',nil,5,world)
assert(#world.Mappings==3,'reattaching must restore MCC entries without duplicates')
plan.bindings[1].keyName='Two'
context:configure(plan)
local tapKey
for _,entry in ipairs(world.Mappings) do if entry.Action==actions.tap then tapKey=entry.Key.KeyName end end
assert(#world.Mappings==3 and tapKey=='Two',
    'reconfiguring must replace MCC keys in attached contexts')
context:detachAll()
assert(#world.Mappings==1 and world.Mappings[1]==nativeEntry,'detach must remove only MCC keys')
for name in pairs(created) do
    assert(not name:find('InputMappingContext',1,true),'MCC created a mapping context: '..name)
end

-- Hold Swap's edges map into every context they declare, beyond the plan's own.
local holdPlan={contexts={'exploration'},holdSwap={enabled=true},bindings={
    {id='press',keyName='LeftAlt',mode=3,consume=true,contexts={'exploration','combat'}},
    {id='release',keyName='LeftAlt',mode=4,consume=true,contexts={'exploration','combat'}},
}}
actions=context:configure(holdPlan)
assert(actions.press.bConsumeInput and actions.release.bConsumeInput)
assert(actions.press.Triggers[1].path=='InputTriggerPressed')
assert(actions.release.Triggers[1].path=='InputTriggerReleased')
context:attach('exploration',nil,5,world)
context:attach('combat',nil,1,combat)
assert(#world.Mappings==3 and #combat.Mappings==2,'global edges must map into each attached context')
context:detachAll()
assert(#world.Mappings==1 and #combat.Mappings==0)
-- Keys usable in every gameplay context live in IMC_Base, which stays applied
-- across open world and combat; narrower keys stay in their own context.
local base=game('/Game/IMC_Base.IMC_Base')
local basePlan={contexts={'exploration','combat'},bindings={
    {id='slot',keyName='One',mode=0},
    {id='swap',keyName='LeftAlt',mode=3,contexts={'combat'}},
}}
actions=context:configure(basePlan)
context:attach('exploration',nil,5,world)
context:attach('combat',nil,1,combat)
assert(#world.Mappings==2 and #combat.Mappings==2,'without IMC_Base each context carries its keys')
context:attach('base',nil,0,base)
assert(#base.Mappings==1 and base.Mappings[1].Action==actions.slot,'IMC_Base must take the everywhere key')
assert(#world.Mappings==1 and world.Mappings[1]==nativeEntry,'open world must drop keys IMC_Base carries')
assert(#combat.Mappings==1 and combat.Mappings[1].Action==actions.swap,'combat keeps its combat-only key')
context:detach('base')
assert(#base.Mappings==0 and #world.Mappings==2 and #combat.Mappings==2,
    'losing IMC_Base must return its keys to the gameplay contexts')
context:detachAll()
assert(#world.Mappings==1 and #combat.Mappings==0 and #base.Mappings==0)
print('PASS Enhanced Input context configuration and lifecycle')
