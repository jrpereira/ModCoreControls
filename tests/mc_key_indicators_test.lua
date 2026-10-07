package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
local function object(path)
    local value={path=path,valid=true}
    function value:IsValid()return self.valid end
    return value
end
local resolved={}
local function keep(value)resolved[value.path]=value;return value end
local original={}
local hud=keep(object('/Engine/Transient.HUD'))
local abilityWheel=keep(object('/Engine/Transient.AbilityWheel'))
local abilityBindings=keep(object('/Engine/Transient.AbilityBindings'))
local consumableWheel=keep(object('/Engine/Transient.ConsumableWheel'))
local consumableBindings=keep(object('/Engine/Transient.ConsumableBindings'))
hud.WBP_AA_Quickslots=abilityWheel
hud.WBP_HUD_Quickslots=consumableWheel
abilityWheel.WBP_AA_Quickslots_Bindings=abilityBindings
consumableWheel.WBP_HUD_Quickslots_Bindings=consumableBindings
local positions={'Left','Top','Right','Bottom'}
for _,kind in ipairs({'ability','consumable'}) do
    local bindings=kind=='ability' and abilityBindings or consumableBindings
    for slot,position in ipairs(positions) do
        local native=keep(object('/Game/Native.'..kind..slot))
        local widget=keep(object('/Engine/Transient.'..kind..position))
        widget.EnhancedInputAction=native;bindings[position]=widget
        original[widget]=native
    end
end
local stored,setCount=nil,0
local monitor=require('mc_key_indicators').new({
    valid=function(value)return value and value.valid end,
    path=function(value)return value.path end,
    property=function(value,name)return value and value[name] or nil end,
    resolve=function(path)return resolved[path] end,
    setAction=function(widget,action)widget.EnhancedInputAction=action;setCount=setCount+1;return true end,
    hud=function()return hud end,
    load=function()return stored end,
    save=function(value)stored=value;return true end,
})
local groupedActions,groupedPlan={}, {bindings={}}
for slot=1,4 do
    local id='grouped.slot'..slot
    groupedActions[id]=keep(object('/Engine/Transient.Grouped'..slot))
    groupedPlan.bindings[#groupedPlan.bindings+1]={id=id,action={type='selected',slot=slot}}
end
local complete,count=monitor:refresh(groupedActions,groupedPlan)
assert(complete and count==8 and setCount==8)
assert(abilityBindings.Left.EnhancedInputAction==consumableBindings.Left.EnhancedInputAction)
local globalActions,globalPlan={}, {bindings={}}
for index,kind in ipairs({'ability','consumable'}) do
    for slot=1,4 do
        local id='global.'..kind..slot
        globalActions[id]=keep(object('/Engine/Transient.Global'..kind..slot))
        globalPlan.bindings[#globalPlan.bindings+1]={id=id,action={type=kind,slot=slot}}
    end
end
assert(monitor:refresh(globalActions,globalPlan))
assert(setCount==16 and abilityBindings.Left.EnhancedInputAction~=consumableBindings.Left.EnhancedInputAction)
assert(monitor:restoreAll())
for widget,native in pairs(original) do assert(widget.EnhancedInputAction==native) end
assert(stored=='')
local groupAction=keep(object('/Engine/Transient.AdvancedGroup2'))
local aliasPlan={bindings={},displays={}}
for slot=1,4 do
    aliasPlan.displays[#aliasPlan.displays+1]={source='advanced.group2',action={type='consumable',slot=slot}}
end
assert(monitor:refresh({['advanced.group2']=groupAction},aliasPlan))
for _,position in ipairs(positions) do
    assert(consumableBindings[position].EnhancedInputAction==groupAction,
        'grouped slot display must reuse the group input action')
end
assert(monitor:restoreAll())
local failPath,forceWrites=nil,0
local recovering=require('mc_key_indicators').new({
    valid=function(value)return value and value.valid end,
    path=function(value)return value.path end,
    property=function(value,name)return value and value[name] or nil end,
    resolve=function(path)return resolved[path] end,
    setAction=function(widget,action)
        if action and action.path==failPath then return false end
        widget.EnhancedInputAction=action
        forceWrites=forceWrites+1
        return true
    end,
    hud=function()return hud end,
    load=function()return stored end,
    save=function(value)stored=value;return true end,
})
assert(recovering:refresh(groupedActions,groupedPlan,{revision=1}))
local before=forceWrites
local complete,completed,expected=recovering:refresh(groupedActions,groupedPlan,{revision=1})
assert(complete and completed==8 and expected==8 and forceWrites==before)
assert(recovering:refresh(groupedActions,groupedPlan,{revision=1,force=true}))
assert(forceWrites==before+8)
failPath=globalActions['global.ability1'].path
complete=recovering:refresh(globalActions,globalPlan,{revision=2})
assert(not complete and abilityBindings.Left.EnhancedInputAction==groupedActions['grouped.slot1'])
assert(recovering:restoreAll())
assert(abilityBindings.Left.EnhancedInputAction==original[abilityBindings.Left])
failPath=nil
assert(recovering:refresh(groupedActions,groupedPlan,{revision=3}))
local partial={bindings={{id='grouped.slot1',action={type='selected',slot=1}}}}
complete,completed,expected=recovering:refresh(groupedActions,partial,{revision=4})
assert(complete and completed==2 and expected==2)
assert(abilityBindings.Top.EnhancedInputAction==original[abilityBindings.Top])
assert(consumableBindings.Top.EnhancedInputAction==original[consumableBindings.Top])
assert(recovering:restoreAll())
local journalFail=true
local writes=0
local journalMonitor=require('mc_key_indicators').new({
    valid=function(value)return value and value.valid end,
    path=function(value)return value.path end,
    property=function(value,name)return value and value[name] or nil end,
    resolve=function(path)return resolved[path] end,
    setAction=function(widget,action)
        widget.EnhancedInputAction=action;writes=writes+1;return true
    end,
    hud=function()return hud end,
    load=function()return '' end,
    save=function()
        if journalFail then return false end
        return true
    end,
})
local beforeFailure=abilityBindings.Left.EnhancedInputAction
assert(not journalMonitor:refresh(groupedActions,groupedPlan))
assert(writes==0 and abilityBindings.Left.EnhancedInputAction==beforeFailure)
journalFail=false
assert(journalMonitor:refresh(groupedActions,groupedPlan))
assert(journalMonitor:restoreAll())
print('PASS MCC key indicator update and restoration')
