package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
local Menu=require('mc_menu')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
local model=Menu.new(definition,{})
local Plan=require('mc_input_plan')
local module,actions=definition.sections[1],definition.sections[2]
local defaultMap,groupedMap,globalMap=module.maps[1],actions.maps[1],actions.maps[2]
assert(module.id=='module' and #module.maps==1 and defaultMap.id=='default',
    'Default belongs to the Module section')
assert(actions.id=='actions' and groupedMap.id=='grouped' and globalMap.id=='global'
    and #actions.maps==2,'Actions has Groups and Global')
-- The map picker only navigates: it is not a stored setting or a plan input.
assert(actions.selector.navigation and not definition.byId[actions.selector.id])

local function find(plan,id)
    for _,item in ipairs(plan.bindings) do if item.id==id then return item end end
end

local default=Plan.build(definition,model.values)
-- All maps coexist. Out of the box only Default's swap is bound: the override=true
-- keys on their default control leave those keys to the native actions.
assert(table.concat(default.maps,',')=='default,grouped,global' and default.nativeSwap==nil)
assert(table.concat(default.contexts,',')=='exploration,combat')
assert(default.holdSwap.enabled and default.holdSwap.defaultGroup==2 and default.defaultGroup==2)
assert(default.overrides.IA_Combat_ToggleQuickslots,'Default must suppress the native toggle')
assert(#default.bindings==2,'Default swap press and release only')
assert(not default.overrides.IA_Quickslot_Left,'unbound slot keys must not override native slots')
for slot=1,4 do
    assert(not find(default,'grouped.QuickSlot'..slot),
        'a slot key on its default control must not bind beside the native quickslot')
end
assert(not find(default,'grouped.GroupFocus2'),
    'Group 2 on its default control must not share the swap key')
assert(not find(default,'grouped.ActivateAbilities') and not find(default,'grouped.ActivateConsumables'),
    'explicit activation keys are unbound by default')
local defaultPress,defaultRelease=default.bindings[1],default.bindings[2]
assert(defaultPress.holdSwapEdge=='press' and defaultPress.mode==3 and defaultPress.action.group==1
    and defaultRelease.holdSwapEdge=='release' and defaultRelease.mode==4
    and defaultRelease.action.group==2,'default hold swap must show Abilities and return to Consumables')
model:set(defaultMap.holdSwap.enabled.id,0)
local tapDefault=Plan.build(definition,model.values)
assert(not tapDefault.holdSwap.enabled and #tapDefault.bindings==1,'saved Off must retain tap swapping')
local toggle=tapDefault.bindings[1]
assert(toggle.action.type=='flip' and toggle.mode==3 and toggle.consume
    and toggle.standardAction=='IA_Combat_ToggleQuickslots' and toggle.keyName==nil,
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
local activeGroup,activation,explicit=groupedMap.groups[1],groupedMap.groups[2],groupedMap.groups[3]
assert(groupedMap.name=='Groups' and activeGroup.name=='Active Group'
    and activation.name=='Alternate Activation' and explicit.name=='Explicit Activation')
local sharedOne=activeGroup.keys[1]
local secondary=activation.keys[1]
local primary,activateConsumables=explicit.keys[1],explicit.keys[2]
assert(primary.id=='ActivateAbilities' and primary.action.group==1
    and activateConsumables.id=='ActivateConsumables' and activateConsumables.action.group==2)
-- Swap back to default mirrors Default's Default wheel; it is not a stored setting.
local mirror=activation.settings[1]
assert(mirror.mirror==defaultMap.holdSwap.defaultWheel and not definition.byId[mirror.id]
    and definition.mirrors[1]==mirror)
local fixedOne,fixedFive=globalMap.groups[1].keys[1],globalMap.groups[2].keys[1]
assert(#globalMap.groups==2 and globalMap.groups[1].name=='Abilities'
    and globalMap.groups[2].name=='Consumables','Global has Abilities and Consumables')
model:set(sharedOne.setting.id,'1|Tap')
model:set(secondary.setting.id,'J|Hold')
model:set(fixedOne.setting.id,'2|Tap')
model:set(fixedFive.setting.id,'3|Tap')
assert(not pcall(model.set,model,fixedOne.setting.id,'2'),'the model holds only canonical text')
assert(not pcall(model.set,model,fixedOne.setting.id,'Two|Tap'),'number keys are stored as digits')
local both=Plan.build(definition,model.values)
assert(#both.bindings==5,'tap swap, custom slot 1, Group 2 and two fixed slots')
local shared=find(both,'grouped.QuickSlot1')
assert(shared.action.type=='selected' and shared.keyName=='One' and shared.standardAction==nil)
assert(table.concat(shared.phases,',')=='Started,Triggered,Completed,Canceled')
local focus=find(both,'grouped.GroupFocus2')
assert(focus.keyName=='J' and focus.standardAction==nil and focus.mode==2 and focus.phases[1]=='Started')
assert(focus.action.group==1,'Group 2 must focus the wheel other than Default')
local ability,consumable=find(both,'global.AbilitySlot1'),find(both,'global.ConsumableSlot1')
assert(ability.action.type=='ability' and ability.action.slot==1 and ability.keyName=='Two')
assert(consumable.action.type=='consumable' and consumable.action.slot==1)
-- Quickslot 1 has a custom key, so override=true suppresses its native slot action.
assert(both.overrides.IA_Quickslot_Left and shared.override=='IA_Quickslot_Left'
    and not both.overrides.IA_Quickslot_Top and both.overrides.IA_Combat_ToggleQuickslots)
assert(focus.override=='IA_Combat_ToggleQuickslots','a custom Group 2 key overrides the toggle')
model:set(secondary.setting.id,'none')
assert(not find(Plan.build(definition,model.values),'grouped.GroupFocus2'),
    'Group 2 back on its default control adds no binding')

-- One key and trigger bind one setting: the same pair on two rows is rejected, naming
-- the key, its trigger and both rows as the player sees them.
model:set(fixedOne.setting.id,'1|Tap')
local duplicateOk,duplicateError=pcall(Plan.build,definition,model.values)
assert(not duplicateOk and duplicateError=='Key 1 (Tap) is bound to both "Quickslot 1" and "Ability Slot 1".'
    ..' Choose another key or trigger for one of them.',duplicateError)
-- At startup the first binding is kept and the later one is skipped and reported.
local lenient=Plan.build(definition,model.values,{lenient=true})
assert(find(lenient,'grouped.QuickSlot1') and not find(lenient,'global.AbilitySlot1')
    and #lenient.skipped==1 and lenient.skipped[1]:find('Key 1 (Tap) is bound to both',1,true))
-- The same key with another trigger is a different binding; both attach.
model:set(fixedOne.setting.id,'1|Hold')
local both=Plan.build(definition,model.values)
assert(find(both,'grouped.QuickSlot1') and find(both,'global.AbilitySlot1') and #both.skipped==0,
    'the same key with another trigger is a different binding')
-- The swap key is named after the wheel it shows. Its Tap acts on press, but it
-- still clashes with another Tap on the same key.
model:set(secondary.setting.id,'J|Hold')
model:set(fixedOne.setting.id,'J|Hold')
local swapClash,swapWhy=pcall(Plan.build,definition,model.values)
assert(not swapClash and swapWhy:find('"Swap to Abilities" and "Ability Slot 1"',1,true),swapWhy)
model:set(secondary.setting.id,'J|Tap')
model:set(fixedOne.setting.id,'J|Tap')
assert(not pcall(Plan.build,definition,model.values),'swap Tap and slot Tap on one key clash')
model:set(fixedOne.setting.id,'J|Hold')
assert(Plan.build(definition,model.values),'swap Tap and slot Hold on one key coexist')
model:set(secondary.setting.id,'none')
model:set(fixedOne.setting.id,'2|Tap')
local second=globalMap.groups[1].keys[2]
model:set(second.setting.id,'2|Tap')
assert(not pcall(Plan.build,definition,model.values),'duplicates within a map must fail too')
model:set(second.setting.id,'none')
local invalidValues={}
for id,value in pairs(model.values) do invalidValues[id]=value end
invalidValues[fixedOne.setting.id]='2|Push'
local valid,why=pcall(Plan.build,definition,invalidValues)
assert(not valid and why:find(fixedOne.setting.id,1,true),'startup validation must identify invalid key row')

-- Default is the base map: the swap key follows its Default wheel, explicit keys do not.
model:set(secondary.setting.id,'J|Hold')
model:set(primary.setting.id,'K|Hold')
model:set(activateConsumables.setting.id,'L|Tap')
model:set(defaultMap.holdSwap.defaultWheel.id,1)
local relative=Plan.build(definition,model.values)
assert(relative.defaultGroup==1)
assert(find(relative,'grouped.GroupFocus2').action.group==2
    and find(relative,'grouped.GroupFocus2').action.wheel==nil,
    'Swap to shows the wheel other than Default')
assert(find(relative,'grouped.ActivateAbilities').action.group==1
    and find(relative,'grouped.ActivateConsumables').action.group==2,'explicit keys name their wheel')
model:set(defaultMap.holdSwap.defaultWheel.id,2)
assert(find(Plan.build(definition,model.values),'grouped.ActivateAbilities').action.group==1,
    'explicit keys do not follow the Default wheel')
model:set(defaultMap.holdSwap.defaultWheel.id,1)
-- Explicit keys always focus their own wheel; the swap key swaps.
assert(find(relative,'grouped.ActivateAbilities').direct and find(relative,'grouped.ActivateConsumables').direct
    and not find(relative,'grouped.GroupFocus2').direct,'explicit keys never swap')
-- Explicit keys keep a real Tap; the swap key set to Tap acts on press.
local tapped=find(relative,'grouped.ActivateConsumables')
assert(tapped.mode==0 and tapped.phases[1]=='Triggered' and #tapped.phases==1,
    'an explicit key set to Tap uses a Tap trigger')
model:set(secondary.setting.id,'J|Tap')
local pressed=find(Plan.build(definition,model.values),'grouped.GroupFocus2')
assert(pressed.mode==3 and #pressed.phases==1,'the swap key set to Tap uses a Pressed trigger')
model:set(secondary.setting.id,'J|Hold')
print('PASS map-driven Enhanced Input plan')

-- Key names compare without regard to case, as the engine compares them, so a
-- hand-edited 'leftalt' still counts as the same key as 'LeftAlt'.
do
    local cased=Menu.new(definition,{})
    cased:set('MCC_actions_global_AbilitySlot1','LeftAlt|Tap')
    cased:set('MCC_actions_global_AbilitySlot2','leftalt|Tap')
    local ok,why=pcall(Plan.build,definition,cased.values)
    assert(not ok and tostring(why):find('is bound to both',1,true),'a case-only difference is the same key')
    local kept=Plan.build(definition,cased.values,{lenient=true})
    assert(find(kept,'global.AbilitySlot1') and not find(kept,'global.AbilitySlot2') and #kept.skipped==1)
end
print('PASS key names compare without regard to case')
