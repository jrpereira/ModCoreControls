package.path='Scripts/?.lua;'..package.path
local Service=require('mc.player_actions.quickslot_service')
local calls={}
local function valid(object)
    object.IsValid=function() return true end
    return object
end
local ability=valid({BP_OnClicked=function() calls[#calls+1]='ability' end})
local consumable=valid({BP_OnClicked=function() calls[#calls+1]='consumable' end})
local count=2
local switcher=valid({GetChildrenCount=function() return count end,
    SetActiveWidgetIndex=function(_,index) calls[#calls+1]='wheel:'..index end})
local hud=valid({GetFullName=function() return 'WBP_GameHUD_C /Engine/Transient.GameHUD' end,
    WBP_AA_Quickslots={Left=ability}, WBP_HUD_Quickslots={Left=consumable},
    QuickslotsSwitcher=switcher})
FindAllOf=function(class) return class=='WBP_GameHUD_C' and {hud} or {} end
local service=Service.new()
assert(service:selectQuickslotGroup(2))
assert(service:activateQuickslot('consumable',1))
count=1
assert(service:selectQuickslotGroup(1))
assert(service:activateQuickslot('ability',1))
assert(table.concat(calls,',')=='wheel:1,consumable,ability',
    'detached wheel selection must not address a missing switcher child')
print('MCC quickslot service routes native two-group controls with or without a detached wheel')
