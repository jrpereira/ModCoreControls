package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Quickslots=require('mc_quickslots')
local Events=require('mc_events')
local calls={}
local events={}
local service={
    activate=function(_,kind,slot)calls[#calls+1]=kind..':'..slot;return true end,
    select=function(_,group)calls[#calls+1]='group:'..group;return true end,
    emit=function(_,name,payload)events[#events+1]={name=name,payload=payload} end,
}
local state={selectedGroup=1,defaultGroup=1}
assert(Quickslots.deliver(state,{action={type='selected',slot=2},mode=0},'Triggered',service))
assert(calls[#calls]=='ability:2')
local focus={action={type='focus',group=2},mode=0}
Quickslots.deliver(state,focus,'Triggered',service)
assert(state.selectedGroup==2 and calls[#calls]=='group:2')
assert(events[1].name=='controls.group.focus' and events[1].payload.group.from==1
    and events[1].payload.group.to==2)
assert(Events.format(events[1].name,events[1].payload)
    =='controls.group.focus {"group":{"from":1,"to":2}}')
Quickslots.deliver(state,{action={type='selected',slot=2},mode=0},'Triggered',service)
assert(calls[#calls]=='consumable:2')
Quickslots.deliver(state,focus,'Triggered',service)
assert(state.selectedGroup==1)
assert(events[2].payload.group.from==2 and events[2].payload.group.to==1)
-- With a key on each wheel, tapping a group key always focuses its own wheel.
do
    local directEvents={}
    local directService={select=function() return true end,
        emit=function(_,name,payload) directEvents[#directEvents+1]=payload end}
    local direct={selectedGroup=1,defaultGroup=1}
    local directOne={action={type='focus',group=1},mode=0,direct=true}
    local directTwo={action={type='focus',group=2},mode=0,direct=true}
    Quickslots.deliver(direct,directTwo,'Triggered',directService)
    assert(direct.selectedGroup==2)
    Quickslots.deliver(direct,directTwo,'Triggered',directService)
    assert(direct.selectedGroup==2,'a direct group key never swaps away from its own wheel')
    Quickslots.deliver(direct,directOne,'Triggered',directService)
    Quickslots.deliver(direct,directOne,'Triggered',directService)
    assert(direct.selectedGroup==1 and #directEvents==2,'only real focus changes are published')
    -- A tapped group key fires on press (Pressed, mode 3) with the same tap behavior.
    local pressedTwo={action={type='focus',group=2},mode=3,direct=true}
    assert(Quickslots.deliver(direct,pressedTwo,'Triggered',directService) and direct.selectedGroup==2)
    local swapping={action={type='focus',group=2},mode=3}
    Quickslots.deliver(direct,swapping,'Triggered',directService)
    assert(direct.selectedGroup==1,'a single pressed group key still swaps back')
end
local hold={action={type='focus',group=2},mode=2}
Quickslots.deliver(state,hold,'Started',service)
assert(state.selectedGroup==2)
Quickslots.deliver(state,hold,'Canceled',service)
assert(state.selectedGroup==1 and calls[#calls]=='group:1')
assert(events[3].payload.group.from==1 and events[3].payload.group.to==2
    and events[4].payload.group.from==2 and events[4].payload.group.to==1)
-- Hold: press shows the key's wheel and release returns to Default.
Quickslots.deliver(state,hold,'Started',service)
assert(state.selectedGroup==2)
Quickslots.deliver(state,hold,'Completed',service)
assert(state.selectedGroup==1 and calls[#calls]=='group:1','release returns to Default')
table.remove(events);table.remove(events)
local failing={
    select=function()return false end,
    activate=function()return true end,
}
assert(not Quickslots.deliver(state,focus,'Triggered',failing))
assert(state.selectedGroup==1 and state.pendingGroup==2)
assert(#events==4,'failed focus change emitted an event')
assert(Quickslots.reconcile(state,service))
assert(state.selectedGroup==2 and state.pendingGroup==nil)
assert(events[5].payload.group.from==1 and events[5].payload.group.to==2,
    'delayed focus success did not emit its transition')
local chosen={id='selected.1',mode=2,action={type='selected',slot=1}}
assert(Quickslots.deliver(state,chosen,'Started',service))
assert(Quickslots.deliver(state,focus,'Triggered',service))
assert(state.selectedGroup==1)
assert(Quickslots.deliver(state,chosen,'Triggered',service))
assert(calls[#calls]=='consumable:1','selected slot must use press-start focus')
local previous=#calls
assert(Quickslots.deliver(state,chosen,'Triggered',service) and #calls==previous)
assert(Quickslots.deliver(state,chosen,'Completed',service))
state.defaultGroup=2
local published=#events
assert(Quickslots.cancel(state,service))
assert(state.selectedGroup==2 and calls[#calls]=='group:2'
    and next(state.gestures)==nil)
assert(#events==published+1 and events[#events].payload.group.from==1
    and events[#events].payload.group.to==2,'cancel must publish its reset to Default')

-- Default activation is an action: the first one publishes without a source group.
local fresh,freshEvents={pendingGroup=1,defaultGroup=1},{}
local freshService={select=function()return true end,
    emit=function(_,name,payload)freshEvents[#freshEvents+1]={name=name,payload=payload} end}
assert(Quickslots.deliver(fresh,{action={type='selected',slot=1},mode=0},'Triggered',freshService)==false,
    'unknown focus must not pick a wheel')
assert(Quickslots.reconcile(fresh,freshService))
assert(fresh.selectedGroup==1 and #freshEvents==1 and freshEvents[1].payload.group.from==nil
    and freshEvents[1].payload.group.to==1)
assert(Events.format(freshEvents[1].name,freshEvents[1].payload)
    =='controls.group.focus {"group":{"to":1}}')
assert(Quickslots.reconcile(fresh,freshService) and #freshEvents==1)
assert(Quickslots.reconcile({},freshService) and #freshEvents==1,'no Default, no activation')
assert(Quickslots.cancel({},freshService) and #freshEvents==1)
local stuck={selectedGroup=1,defaultGroup=2}
assert(not Quickslots.cancel(stuck,{select=function()return false end,emit=freshService.emit}))
assert(stuck.selectedGroup==1 and stuck.pendingGroup==2 and #freshEvents==1,
    'failed reset keeps the published group and leaves Default pending')
assert(Quickslots.reconcile(stuck,freshService) and stuck.selectedGroup==2
    and freshEvents[2].payload.group.from==1 and freshEvents[2].payload.group.to==2)

local function object()
    local value={valid=true}
    function value:IsValid()return self.valid end
    -- WBP_GameHUD's own wheel setter; other objects never receive it.
    value['Set AA Quickslots Showed']=function(self,show,userInput)
        assert(userInput==false,'MCC swaps are not reported as user input')
        self.showsAbilities=show
    end
    return value
end
local stale,owned=object(),object()
for _,hud in ipairs({stale,owned}) do
    hud.WBP_AA_Quickslots={Left=object()}
    function hud.WBP_AA_Quickslots.Left:BP_OnClicked()self.clicks=(self.clicks or 0)+1 end
end
FindAllOf=function()error('owner-bound service must not enumerate HUDs') end
local bound=Quickslots.new()
assert(bound:bind({hud=owned},10))
assert(bound:activate('ability',1))
assert(owned.WBP_AA_Quickslots.Left.clicks==1 and not stale.WBP_AA_Quickslots.Left.clicks)
assert(bound:reset(1) and owned.showsAbilities==true)
assert(bound:select(2) and owned.showsAbilities==false,'select sets the game\'s active wheel')

assert(bound:invalidate(10) and not bound:activate('ability',1))
assert(bound:bind({hud=owned},11))
owned.valid=false
assert(bound:hud()==nil and not bound:select(2))
local pending={selectedGroup=2,defaultGroup=2}
assert(not Quickslots.cancel(pending,bound))
assert(pending.selectedGroup==2 and pending.pendingGroup==2)
local replacement=object()
assert(bound:bind({hud=replacement},12))
assert(Quickslots.reconcile(pending,bound))
assert(pending.pendingGroup==nil and replacement.showsAbilities==false)
replacement.showsAbilities=true
local recreated=object()
local live={hud=replacement}
assert(bound:bind(live,13))
assert(Quickslots.reconcile(pending,bound))
-- The host binds every sync; the service keeps handles, not the owner table.
assert(bound:bind({hud=recreated},13))
assert(Quickslots.reconcile(pending,bound))
assert(recreated.showsAbilities==false,'recreated HUD needs focus presentation')

-- Hold to Swap is a sustained Hold: press shows the other wheel, release Default.
local swapState={selectedGroup=1,defaultGroup=1}
local swapService={}
function swapService:select(group) self.selected=group;return true end
function swapService:emit() return true end
local swapHold={mode=2,swap=true,sustained=true,action={type='focus',group=2}}
assert(Quickslots.deliver(swapState,swapHold,'Started',swapService) and swapState.selectedGroup==2)
assert(Quickslots.deliver(swapState,swapHold,'Completed',swapService) and swapState.selectedGroup==1,
    'Hold to Swap release must return to Default')
print('PASS quickslot callback routing and wheel focus')

-- Focus is the game's own active wheel, wherever the wheels sit; MCC never touches
-- the wheels or the switcher.
do
    local hud=object()
    hud.WBP_AA_Quickslots=setmetatable({},{__index=function(_,key)error('wheel read: '..key)end})
    hud.WBP_HUD_Quickslots=hud.WBP_AA_Quickslots
    hud.QuickslotsSwitcher=setmetatable({},{__index=function(_,key)error('switcher read: '..key)end})
    local service=Quickslots.new()
    assert(service:bind({hud=hud},11))
    assert(service:select(2) and hud.showsAbilities==false)
    assert(service:select(1) and hud.showsAbilities==true)
    -- Without the game's setter the wheel cannot change: Default stays pending.
    hud['Set AA Quickslots Showed']=function() error('unavailable') end
    assert(not service:select(2) and hud.showsAbilities==true)
    assert(service:invalidate(11))
end
print('PASS focus selects through the game\'s setter only')
