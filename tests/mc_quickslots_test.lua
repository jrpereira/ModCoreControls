package.path='Scripts/?.lua;'..package.path
local Quickslots=require('mc_quickslots')
local calls={}
local service={
    activate=function(_,kind,slot)calls[#calls+1]=kind..':'..slot;return true end,
    select=function(_,group)calls[#calls+1]='group:'..group;return true end,
}
local state={selectedGroup=1}
assert(Quickslots.deliver(state,{action={type='selected',slot=2},mode=0},'Triggered',service))
assert(calls[#calls]=='ability:2')
local focus={action={type='focus',group=2},mode=0}
Quickslots.deliver(state,focus,'Triggered',service)
assert(state.selectedGroup==2 and calls[#calls]=='group:2')
Quickslots.deliver(state,{action={type='selected',slot=2},mode=0},'Triggered',service)
assert(calls[#calls]=='consumable:2')
Quickslots.deliver(state,focus,'Triggered',service)
assert(state.selectedGroup==1)
local hold={action={type='focus',group=2},mode=2}
Quickslots.deliver(state,hold,'Started',service)
assert(state.selectedGroup==2)
Quickslots.deliver(state,hold,'Canceled',service)
assert(state.selectedGroup==1 and calls[#calls]=='group:1')
local failing={
    select=function()return false end,
    activate=function()return true end,
}
assert(not Quickslots.deliver(state,focus,'Triggered',failing))
assert(state.selectedGroup==1 and state.pendingGroup==2)
assert(Quickslots.reconcile(state,service))
assert(state.selectedGroup==2 and state.pendingGroup==nil)
local chosen={id='selected.1',mode=2,action={type='selected',slot=1}}
assert(Quickslots.deliver(state,chosen,'Started',service))
assert(Quickslots.deliver(state,focus,'Triggered',service))
assert(state.selectedGroup==1)
assert(Quickslots.deliver(state,chosen,'Triggered',service))
assert(calls[#calls]=='consumable:1','selected slot must use press-start focus')
local previous=#calls
assert(Quickslots.deliver(state,chosen,'Triggered',service) and #calls==previous)
assert(Quickslots.deliver(state,chosen,'Completed',service))
assert(Quickslots.cancel(state,service))
assert(state.selectedGroup==1 and next(state.gestures)==nil and next(state.held)==nil)

local function object()
    local value={valid=true}
    function value:IsValid()return self.valid end
    return value
end
local stale,owned=object(),object()
for _,hud in ipairs({stale,owned}) do
    hud.QuickslotsSwitcher=object()
    function hud.QuickslotsSwitcher:GetChildrenCount()return 2 end
    function hud.QuickslotsSwitcher:SetActiveWidgetIndex(index)self.index=index end
    hud.WBP_AA_Quickslots={Left=object()}
    function hud.WBP_AA_Quickslots.Left:BP_OnClicked()self.clicks=(self.clicks or 0)+1 end
end
FindAllOf=function()error('owner-bound service must not enumerate HUDs') end
local bound=Quickslots.new()
assert(bound:bind({hud=owned},10))
assert(bound:activate('ability',1))
assert(owned.WBP_AA_Quickslots.Left.clicks==1 and not stale.WBP_AA_Quickslots.Left.clicks)
assert(bound:reset(1) and owned.QuickslotsSwitcher.index==0)
owned.QuickslotsSwitcher.GetChildrenCount=function()return 1 end
assert(bound:select(2),'separate-wheel presentation has no second switcher child')
assert(bound:invalidate(10) and not bound:activate('ability',1))
assert(bound:bind({hud=owned},11))
owned.valid=false
assert(bound:hud()==nil and not bound:select(2))
local pending={selectedGroup=2,held={[2]=1}}
assert(not Quickslots.cancel(pending,bound))
assert(pending.selectedGroup==1 and pending.pendingGroup==1)
local replacement=object()
replacement.QuickslotsSwitcher=object()
function replacement.QuickslotsSwitcher:GetChildrenCount()return 2 end
function replacement.QuickslotsSwitcher:SetActiveWidgetIndex(index)self.index=index end
assert(bound:bind({hud=replacement},12))
assert(Quickslots.reconcile(pending,bound))
assert(pending.pendingGroup==nil and replacement.QuickslotsSwitcher.index==0)
replacement.QuickslotsSwitcher.index=1
local recreated=object()
recreated.QuickslotsSwitcher=object()
function recreated.QuickslotsSwitcher:GetChildrenCount()return 2 end
function recreated.QuickslotsSwitcher:SetActiveWidgetIndex(index)self.index=index end
local live={hud=replacement}
assert(bound:bind(live,13))
assert(Quickslots.reconcile(pending,bound))
live.hud=recreated
assert(Quickslots.reconcile(pending,bound))
assert(recreated.QuickslotsSwitcher.index==0,'recreated HUD needs focus presentation')
print('PASS quickslot callback routing and wheel focus')
