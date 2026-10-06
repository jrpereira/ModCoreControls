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

-- A binding that cannot be configured, or a key that cannot be mapped, skips only
-- itself; every other key still maps, and each failure is reported once.
local warnings={}
local resilient=require('mc_input_context').new(e,{
    warn=function(...) warnings[#warnings+1]=table.concat({...}) end,
    info=function()end,debug=function()end,trace=function()end,error=function()end})
local fragile=game('/Game/IMC_OW.IMC_OW')
local mapKey=fragile.MapKey
function fragile:MapKey(action,key)
    if key.KeyName=='Bad' then error('invalid key name') end
    return mapKey(self,action,key)
end
local mixedPlan={contexts={'exploration'},bindings={
    {id='good',keyName='One',mode=0},
    {id='badKey',keyNames={'Bad','Two'},mode=0},
    {id='badTrigger',keyName='Three',mode=99},
}}
actions=resilient:configure(mixedPlan)
assert(actions.good and actions.badKey and actions.badTrigger==nil,'only the broken binding is left out')
resilient:attach('exploration',nil,5,fragile)
local keys={}
for _,entry in ipairs(fragile.Mappings) do keys[#keys+1]=entry.Key.KeyName end
table.sort(keys)
assert(table.concat(keys,',')=='One,Two','a failing key must not stop the others: '..table.concat(keys,','))
assert(resilient:attached('exploration',{AppliedInputContexts={[fragile]=5},IsValid=function()return true end}),
    'skipped keys must not count as lost entries')
assert(#warnings==2,'each failure is reported: '..#warnings)
resilient:configure(mixedPlan)
assert(#warnings==2,'an unchanged failure is reported only once')
resilient:detachAll()
assert(#fragile.Mappings==0)
print('PASS a broken binding or key skips only itself')

-- After a mod restart a new Lua state finds the previous state's MCC keys still mapped;
-- it removes them instead of mapping each key a second time. Native keys stay.
local shared=game('/Game/IMC_OW.IMC_OW')
local native={Action=object('/Game/Input/IA_Native.IA_Native'),Key={KeyName='One'}}
shared.Mappings[1]=native
local restartPlan={contexts={'exploration'},bindings={{id='tap',keyName='One',mode=0},{id='old',keyName='K',mode=0}}}
local previous=require('mc_input_context').new(e)
previous:configure(restartPlan)
previous:attach('exploration',nil,5,shared)
assert(#shared.Mappings==3)
-- The new state no longer binds K, and is never told about the previous state.
local restarted=require('mc_input_context').new(e)
restarted:configure({contexts={'exploration'},bindings={{id='tap',keyName='Two',mode=0}}})
restarted:attach('exploration',nil,5,shared)
local keys={}
for _,entry in ipairs(shared.Mappings) do keys[#keys+1]=entry.Key.KeyName end
assert(#shared.Mappings==2 and shared.Mappings[1]==native and keys[2]=='Two',
    'stale MCC keys must be removed: '..table.concat(keys,','))
restarted:detachAll()
assert(#shared.Mappings==1 and shared.Mappings[1]==native,'detach leaves only native keys')
print('PASS a new Lua state removes MCC keys left by the previous one')

-- A key removed from a multi-key binding counts as detached, even though its
-- action still has another key mapped.
do
    local checked=game('/Game/IMC_OW.IMC_OW')
    local pairsContext=require('mc_input_context').new(e)
    pairsContext:configure({contexts={'exploration'},bindings={{id='swap',keyNames={'LeftAlt','Q'},mode=3}}})
    pairsContext:attach('exploration',nil,5,checked)
    local applied={AppliedInputContexts={[checked]=5},IsValid=function()return true end}
    assert(#checked.Mappings==2 and pairsContext:attached('exploration',applied))
    table.remove(checked.Mappings,2)
    assert(not pairsContext:attached('exploration',applied),'a lost key of a kept action is detected')
    pairsContext:detachAll()
end
print('PASS attachment checks each action and key pair')

-- A key name the engine does not know is skipped and reported, not mapped dead.
do
    local warned={}
    local checkedKeys=require('mc_input_context').new(e,{
        warn=function(...) warned[#warned+1]=table.concat({...}) end,
        info=function()end,debug=function()end,trace=function()end,error=function()end})
    e.validKey=function(name) if name=='Bogus' then return false end return true end
    local target=game('/Game/IMC_OW.IMC_OW')
    checkedKeys:configure({contexts={'exploration'},bindings={{id='good',keyName='J',mode=0},
        {id='bad',keyName='Bogus',mode=0}}})
    checkedKeys:attach('exploration',nil,5,target)
    e.validKey=nil
    assert(#target.Mappings==1 and target.Mappings[1].Key.KeyName=='J')
    assert(#warned==1 and warned[1]:find('bad Bogus',1,true) and warned[1]:find('unknown key name',1,true),
        tostring(warned[1]))
    checkedKeys:detachAll()
end
print('PASS unknown key names are skipped and reported')
