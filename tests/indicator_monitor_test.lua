package.path='Scripts/?.lua;'..package.path
local Monitor=require('mc.player_actions.indicator_monitor')
local registry,stored={},''
local function object(path)
    local value={path=path,Icon='native-icon'}
    function value:IsValid() return true end
    function value:GetFullName() return 'Object '..self.path end
    registry[path]=value
    return value
end
local hud=object('/HUD')
local assignments=0
hud.WBP_AA_Quickslots=object('/HUD.Ability')
hud.WBP_HUD_Quickslots=object('/HUD.Consumable')
local originals={}
for _,kind in ipairs({'Ability','Consumable'}) do
    local wheel=kind=='Ability' and hud.WBP_AA_Quickslots or hud.WBP_HUD_Quickslots
    local bindingName=kind=='Ability' and 'WBP_AA_Quickslots_Bindings' or 'WBP_HUD_Quickslots_Bindings'
    local bindings=object(wheel.path..'.Bindings')
    wheel[bindingName]=bindings
    for _,side in ipairs({'Left','Top','Right','Bottom'}) do
        local indicator=object(bindings.path..'.'..side)
        local original=object('/Native.'..kind..side)
        indicator.EnhancedInputAction=original
        function indicator:SetEnhancedInputAction(action)
            assignments=assignments+1
            self.EnhancedInputAction=action
        end
        bindings[side]=indicator
        originals[indicator.path]=original
    end
end
local function make()
    return Monitor.new({valid=function(v)return v and v:IsValid()end,
        path=function(v)return v and v.path end,
        property=function(v,k)return v and v[k]end,
        same=function(a,b)return a==b end,
        resolve=function(path)return registry[path]end,
        setAction=function(widget,action)widget:SetEnhancedInputAction(action)end,
        hud=function()return hud end,
        load=function()return stored end,
        save=function(value)stored=value;return true end})
end
local actions,flat={},{actions={}}
for index=1,8 do
    local id='IA_ActionSlot'..index
    actions[id]=object('/MCC.'..id)
    flat.actions[index]={id=id,type=index<=4 and 'ability' or 'consumable',
        slot=((index-1)%4)+1}
end
local monitor=make()
local complete,count=monitor:refresh(actions,flat)
assert(complete and count==8)
assert(hud.WBP_AA_Quickslots.WBP_AA_Quickslots_Bindings.Left.EnhancedInputAction==actions.IA_ActionSlot1)
assert(hud.WBP_HUD_Quickslots.WBP_HUD_Quickslots_Bindings.Left.EnhancedInputAction==actions.IA_ActionSlot5)
assert(stored:find('/Native.AbilityLeft',1,true))
assert(assignments==8)
-- Reapplying the same action is required when its key mapping changes.
complete,count=monitor:refresh(actions,flat)
assert(complete and count==8 and assignments==16)
-- A new Lua host recovers the original actions from shared state.
monitor=make()
local grouped={actions={}}
for slot=1,4 do
    local id='IA_SharedSlot'..slot
    actions[id]=object('/MCC.'..id)
    grouped.actions[slot]={id=id,shared=true,slot=slot}
end
complete,count=monitor:refresh(actions,grouped)
assert(complete and count==8)
assert(hud.WBP_AA_Quickslots.WBP_AA_Quickslots_Bindings.Left.EnhancedInputAction==actions.IA_SharedSlot1)
assert(hud.WBP_HUD_Quickslots.WBP_HUD_Quickslots_Bindings.Left.EnhancedInputAction==actions.IA_SharedSlot1)
assert(monitor:restoreAll() and stored=='')
for path,original in pairs(originals) do
    assert(registry[path].EnhancedInputAction==original and registry[path].Icon=='native-icon')
end
print('PASS native binding indicators follow Flat/Grouped actions and restore across Lua hosts')
