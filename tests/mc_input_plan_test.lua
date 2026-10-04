package.path='Scripts/?.lua;'..package.path
local Menu=require('mc_menu')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
local model=Menu.new(definition,{})
local Plan=require('mc_input_plan')
local module,actions=definition.sections[1],definition.sections[2]
local defaultMap,groupedMap,globalMap=module.maps[1],actions.maps[1],actions.maps[2]
assert(module.id=='module' and #module.maps==1 and defaultMap.id=='default',
    'Default belongs to the Module section')
assert(actions.id=='actions' and groupedMap.id=='grouped' and globalMap.id=='global'
    and #actions.maps==2,'Actions has Quickslot Groups and Global')
-- The map picker only navigates: it is not a stored setting or a plan input.
assert(actions.selector.navigation and not definition.byId[actions.selector.id])

local function find(plan,id)
    for _,item in ipairs(plan.bindings) do if item.id==id then return item end end
end

local default=Plan.build(definition,model.values)
-- All maps coexist. Nothing but Default's swap is bound out of the box.
assert(table.concat(default.maps,',')=='default,grouped,global' and default.nativeSwap==nil)
assert(table.concat(default.contexts,',')=='exploration,combat')
assert(not default.holdSwap.enabled and default.holdSwap.defaultGroup==2 and default.defaultGroup==2)
assert(default.overrides.IA_Combat_ToggleQuickslots,'Default must suppress the native toggle')
assert(#default.bindings==1,'only the Default swap is bound by default')
assert(not default.overrides.IA_Quickslot_Left,'unbound slot keys must not override native slots')
local toggle=default.bindings[1]
assert(toggle.action.type=='flip' and toggle.mode==3 and toggle.consume
    and toggle.standardAction=='IA_Combat_ToggleQuickslots' and toggle.key==0,
    'the toggle must flip wheels on press, on the inherited Toggle Quickslots key')
assert(table.concat(toggle.contexts,',')=='exploration,combat',
    'swap outside of combat defaults on, so the toggle works in both contexts')
model:set(defaultMap.holdSwap.outsideCombat.id,0)
local combatOnly=Plan.build(definition,model.values)
assert(table.concat(combatOnly.bindings[1].contexts,',')=='combat',
    'swap outside of combat off must limit the toggle to combat')
model:set(defaultMap.holdSwap.outsideCombat.id,1)
model:set(defaultMap.holdSwap.enabled.id,1)
model:set(defaultMap.holdSwap.defaultWheel.id,1)
local changedDefault=Plan.build(definition,model.values)
assert(#changedDefault.bindings==2 and changedDefault.holdSwap.defaultGroup==1
    and changedDefault.defaultGroup==1,'the plan must activate the chosen Default wheel')
local press,release=changedDefault.bindings[1],changedDefault.bindings[2]
assert(press.holdSwapEdge=='press' and press.mode==3 and press.action.group==2,
    'holding must show the wheel other than the default')
assert(release.holdSwapEdge=='release' and release.mode==4,'releasing must return')
assert(changedDefault.holdSwap.sourceAction=='IA_Combat_ToggleQuickslots'
    and changedDefault.overrides.IA_Combat_ToggleQuickslots)
model:set(defaultMap.holdSwap.enabled.id,0)
model:set(defaultMap.holdSwap.defaultWheel.id,2)

-- Grouped and Global bindings are active together with Default's swap.
local activeGroup,activation=groupedMap.groups[1],groupedMap.groups[2]
assert(groupedMap.name=='Quickslot Groups' and activeGroup.name=='Active Group'
    and activation.name=='Group Activation')
local sharedOne=activeGroup.keys[1]
local secondary,primary=activation.keys[1],activation.keys[2]
-- Default Group mirrors Default's Default wheel; it is not a stored setting.
local mirror=activation.settings[1]
assert(mirror.mirror==defaultMap.holdSwap.defaultWheel and not definition.byId[mirror.id]
    and definition.mirrors[1]==mirror)
local fixedOne,fixedFive=globalMap.groups[1].keys[1],globalMap.groups[1].keys[5]
assert(#globalMap.groups==1,'Global has no Optional section')
model:set(sharedOne.key.id,49)
model:set(secondary.key.id,74)
model:set(fixedOne.key.id,50)
model:set(fixedFive.key.id,51)
local both=Plan.build(definition,model.values)
assert(#both.bindings==5,'swap, one shared slot, Group 2 and two fixed slots')
local shared=find(both,'grouped.FixedSlot1')
assert(shared.action.type=='selected' and shared.keyName=='One')
assert(table.concat(shared.phases,',')=='Started,Triggered,Completed,Canceled')
local focus=find(both,'grouped.GroupFocus2')
assert(focus.keyName=='J' and focus.standardAction==nil and focus.mode==2 and focus.phases[1]=='Started')
assert(focus.action.group==1,'Group 2 must focus the wheel other than Default')
local ability,consumable=find(both,'global.SlotAction1'),find(both,'global.SlotAction5')
assert(ability.action.type=='ability' and ability.action.slot==1 and ability.keyName=='Two')
assert(consumable.action.type=='consumable' and consumable.action.slot==1)
assert(both.overrides.IA_Quickslot_Left and both.overrides.IA_Combat_ToggleQuickslots)
model:set(secondary.key.id,0)
assert(not find(Plan.build(definition,model.values),'grouped.GroupFocus2'),
    'an unbound Group 2 key no longer inherits the Toggle Quickslots key')

-- The same key and trigger in two maps is rejected and names both rows.
model:set(fixedOne.key.id,49)
local duplicateOk,duplicateError=pcall(Plan.build,definition,model.values)
assert(not duplicateOk and duplicateError:find(fixedOne.key.id,1,true)
    and duplicateError:find(sharedOne.key.id,1,true),
    'duplicate error must identify both conflicting rows')
model:set(fixedOne.key.id,50)
local second=globalMap.groups[1].keys[2]
model:set(second.key.id,50)
assert(not pcall(Plan.build,definition,model.values),'duplicates within a map must fail too')
model:set(second.key.id,0)
assert(not pcall(model.set,model,fixedOne.key.id,3),'unsupported captured key must be rejected')
local invalidValues={}
for id,value in pairs(model.values) do invalidValues[id]=value end
invalidValues[fixedOne.key.id]=3
local valid,why=pcall(Plan.build,definition,invalidValues)
assert(not valid and why:find(fixedOne.key.id,1,true),'startup validation must identify invalid key row')
invalidValues[fixedOne.key.id]=model.values[fixedOne.key.id]
invalidValues[fixedOne.trigger.id]=99
valid,why=pcall(Plan.build,definition,invalidValues)
assert(not valid and why:find(fixedOne.trigger.id,1,true),'invalid trigger must identify row')

-- Default is the base map: Group keys follow its Default wheel.
model:set(secondary.key.id,74)
model:set(primary.key.id,75)
model:set(defaultMap.holdSwap.defaultWheel.id,1)
local relative=Plan.build(definition,model.values)
assert(relative.defaultGroup==1)
assert(find(relative,'grouped.GroupFocus1').action.group==1
    and find(relative,'grouped.GroupFocus2').action.group==2
    and find(relative,'grouped.GroupFocus2').action.wheel==nil,
    'Group 1 shows the Default wheel and Group 2 the other')
print('PASS map-driven Enhanced Input plan')
