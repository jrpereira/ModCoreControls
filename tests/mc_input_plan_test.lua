package.path='Scripts/?.lua;'..package.path
local Menu=require('mc_menu')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
local model=Menu.new(definition,{})
local Plan=require('mc_input_plan')

local default=Plan.build(definition,model.values)
-- Default owns the swap on the player's Toggle Quickslots key and suppresses the
-- game's toggle; it never drives or rewrites the native action.
assert(default.map=='default' and default.nativeSwap==nil)
assert(not default.holdSwap.enabled and default.holdSwap.defaultGroup==2 and default.defaultGroup==2)
assert(default.overrides.IA_Combat_ToggleQuickslots,'Default must suppress the native toggle')
assert(#default.bindings==1,'Hold Swap off must generate one toggle')
local toggle=default.bindings[1]
assert(toggle.action.type=='flip' and toggle.mode==3 and toggle.consume
    and toggle.standardAction=='IA_Combat_ToggleQuickslots' and toggle.key==0,
    'the toggle must flip wheels on press, on the inherited Toggle Quickslots key')
assert(table.concat(toggle.contexts,',')=='exploration,combat',
    'swap outside of combat defaults on, so the toggle works in both contexts')
local defaultMap=definition.sections[1].maps[1]
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

model:set(definition.sections[1].selector.id,1)
local grouped=Plan.build(definition,model.values)
assert(grouped.map=='grouped')
assert(grouped.contexts[1]=='exploration' and grouped.contexts[2]=='combat')
assert(#grouped.bindings==5,'Secondary and four shared keys should be active by default')
assert(grouped.bindings[1].action.type=='selected' and grouped.bindings[1].keyName=='One')
assert(table.concat(grouped.bindings[1].phases,',')=='Started,Triggered,Completed,Canceled')
assert(grouped.bindings[5].action.type=='focus' and grouped.bindings[5].keyName==nil
    and grouped.bindings[5].standardAction=='IA_Combat_ToggleQuickslots',
    'Secondary inherits the native toggle key by default')
assert(grouped.bindings[5].mode==2 and grouped.bindings[5].phases[1]=='Started')
assert(grouped.defaultGroup==2 and grouped.bindings[5].action.group==1,
    'Group 2 must focus the wheel other than Default')
-- MCC focus actions select wheels itself; the native toggle stays unblocked.
assert(not grouped.overrides.IA_Combat_ToggleQuickslots)
assert(not grouped.overrides.IA_OW_ToggleQuickslots)
assert(grouped.overrides.IA_Quickslot_Left)
local secondary=definition.sections[1].maps[2].groups[2].keys[1]
model:set(secondary.key.id,74)
local custom=Plan.build(definition,model.values)
assert(#custom.bindings==5 and custom.bindings[5].keyName=='J'
    and custom.bindings[5].standardAction==nil
    and not custom.overrides.IA_Combat_ToggleQuickslots,
    'a custom Secondary key replaces the inherited toggle key')
model:set(secondary.key.id,0)

model:set(definition.sections[1].selector.id,2)
local globalPlan=Plan.build(definition,model.values)
assert(globalPlan.map=='global' and #globalPlan.bindings==8)
assert(globalPlan.bindings[1].action.type=='ability' and globalPlan.bindings[1].action.slot==1)
assert(globalPlan.bindings[5].action.type=='consumable' and globalPlan.bindings[5].action.slot==1)
assert(globalPlan.bindings[8].keyName=='Eight')
assert(not globalPlan.overrides.IA_Combat_ToggleQuickslots
    and not globalPlan.overrides.IA_OW_ToggleQuickslots
    and globalPlan.overrides.IA_Quickslot_Left)

local first=definition.sections[1].maps[3].groups[1].keys[1]
local second=definition.sections[1].maps[3].groups[1].keys[2]
model:set(second.key.id,model.values[first.key.id])
assert(not pcall(Plan.build,definition,model.values),'duplicate active bindings must fail')
local duplicateError
local duplicateOk
duplicateOk,duplicateError=pcall(Plan.build,definition,model.values)
assert(not duplicateOk and duplicateError:find(second.key.id,1,true),
    'duplicate error must identify the conflicting row')
model:set(second.key.id,model.saved[second.key.id])
assert(not pcall(model.set,model,first.key.id,3),'unsupported captured key must be rejected')
local invalidValues={}
for id,value in pairs(model.values) do invalidValues[id]=value end
invalidValues[first.key.id]=3
local valid,why=pcall(Plan.build,definition,invalidValues)
assert(not valid and why:find(first.key.id,1,true),'startup validation must identify invalid key row')
invalidValues[first.key.id]=model.values[first.key.id]
invalidValues[first.trigger.id]=99
valid,why=pcall(Plan.build,definition,invalidValues)
assert(not valid and why:find(first.trigger.id,1,true),'invalid trigger must identify row')

model:set(definition.sections[1].selector.id,3)
local advanced=Plan.build(definition,model.values)
assert(advanced.map=='advanced' and #advanced.bindings==9,
    'Advanced must activate eight slots and the inherited secondary group')
assert(advanced.bindings[1].action.type=='ability' and advanced.bindings[6].action.type=='consumable')
assert(advanced.bindings[5].action.group==2 and advanced.bindings[5].keyName==nil
    and advanced.bindings[5].standardAction=='IA_Combat_ToggleQuickslots')
local advancedMap=definition.sections[1].maps[4]
local future=advancedMap.groups[3].keys[2]
model:set(future.key.id,49)
assert(#Plan.build(definition,model.values).bindings==9,
    'configured future slots must not create runtime bindings')
local group=advancedMap.groups[2].keys[1]
model:set(group.key.id,164)
local withGroup=Plan.build(definition,model.values)
local groupBinding
for _,binding in ipairs(withGroup.bindings) do
    if binding.action.type=='focus' then groupBinding=binding end
end
assert(#withGroup.bindings==9 and groupBinding and groupBinding.action.group==2)
assert(groupBinding.keyName=='LeftAlt' and groupBinding.standardAction==nil,
    'a custom optional key must stop inheriting its standard control')
assert(#withGroup.displays==4 and withGroup.displays[1].source==groupBinding.id
    and withGroup.displays[1].alias==0xC5 and withGroup.displays[1].action.type=='consumable',
    'a bound Advanced group must mirror its action, key, and trigger to its four slot displays')

assert(not withGroup.holdSwap,'Grouped, Global and Advanced must not add Hold Swap')
-- Default is the base map: its Default wheel is in effect under every map.
assert(withGroup.defaultGroup==2,'Advanced must use the Default wheel setting')
model:set(defaultMap.holdSwap.defaultWheel.id,1)
assert(Plan.build(definition,model.values).defaultGroup==1,'Advanced must follow the Default wheel')
model:set(definition.sections[1].selector.id,1)
local relative=Plan.build(definition,model.values)
assert(relative.defaultGroup==1,'Grouped must use the Default wheel setting')
for _,item in ipairs(relative.bindings) do
    if item.id=='grouped.GroupFocus2' then
        assert(item.action.group==2 and item.action.wheel==nil,'Group 2 must follow the Default wheel')
    end
end
print('PASS map-driven Enhanced Input plan')
