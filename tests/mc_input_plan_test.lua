package.path='Scripts/?.lua;'..package.path
local Menu=require('mc_menu')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
local model=Menu.new(definition,{})
local Plan=require('mc_input_plan')

local grouped=Plan.build(definition,model.values)
assert(grouped.map=='grouped')
assert(grouped.contexts[1]=='exploration' and grouped.contexts[2]=='combat')
assert(#grouped.bindings==5,'Alternative and four shared keys should be active by default')
assert(grouped.bindings[1].action.type=='focus' and grouped.bindings[1].keyName=='LeftAlt')
assert(grouped.bindings[1].mode==2 and grouped.bindings[1].phases[1]=='Started')
assert(grouped.bindings[2].action.type=='selected' and grouped.bindings[2].keyName=='One')
assert(table.concat(grouped.bindings[2].phases,',')=='Started,Triggered,Completed,Canceled')
assert(grouped.overrides.IA_Combat_ToggleQuickslots)
assert(grouped.overrides.IA_Quickslot_Left)
local alternative=definition.sections[1].maps[1].groups[1].keys[1]
model:set(alternative.key.id,0)
local mapOnly=Plan.build(definition,model.values)
assert(#mapOnly.bindings==4 and mapOnly.overrides.IA_Combat_ToggleQuickslots,
    'map-level override must remain when its key-level binding is disabled')

model:set(definition.sections[1].selector.id,1)
local flat=Plan.build(definition,model.values)
assert(flat.map=='flat' and #flat.bindings==9)
assert(flat.bindings[1].action.type=='ability' and flat.bindings[1].action.slot==1)
assert(flat.bindings[5].action.type=='consumable' and flat.bindings[5].action.slot==1)
assert(flat.bindings[8].keyName=='Eight')
assert(flat.bindings[9].keyName=='LeftAlt' and flat.overrides.IA_Combat_ToggleQuickslots)

local first=definition.sections[1].maps[2].groups[1].keys[1]
local second=definition.sections[1].maps[2].groups[1].keys[2]
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
print('PASS map-driven Enhanced Input plan')
