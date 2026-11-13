package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
local Events=require('mc_events')
local values={}
local shared={
    GetSharedVariable=function(_,key)return values[key]end,
    SetSharedVariable=function(_,key,value)values[key]=value end,
}
local handlers,calls={},{}
local api={ModRef=shared,RegisterConsoleCommandHandler=function(name,callback)
    handlers[name]=callback;return true
end}
local state=Events.subscribe(api,Events.focus)
local viewport={ProcessConsoleExec=function(_,command,_,controller)
    calls[#calls+1]={command=command,controller=controller}
    return handlers[command]()
end}
local owner={controller={},player={ViewportClient=viewport}}
local publish=Events.publisher(shared)
assert(publish(Events.focus,{group={from=1,to=2}},owner))
assert(state.revision==1 and state.payload.group.from==1 and state.payload.group.to==2)
assert(Events.format(Events.focus,state.payload)
    =='controls.group.focus {"group":{"from":1,"to":2}}')
assert(publish(Events.focus,{group={from=2,to=1}},owner))
assert(state.revision==2 and state.payload.group.to==1 and #calls==2)
assert(not pcall(publish,Events.focus,{group={from=1,to=1}},owner))
assert(publish(Events.focus,{group={to=2}},owner))
assert(values['MCC.Controls.GroupFocus.v1.data']=='3 - 2')
assert(state.revision==3 and state.payload.group.from==nil and state.payload.group.to==2)
assert(Events.format(Events.focus,{group={to=2}})=='controls.group.focus {"group":{"to":2}}')
assert(not pcall(publish,Events.focus,{group={from=3,to=2}},owner))
print('PASS ModCore event publication and subscription')

-- A delivery failure goes to the caller's logger, never straight to print, so it
-- follows that mod's log_level.txt.
do
    local printed={}
    local realPrint=print
    print=function(...) printed[#printed+1]=table.concat({...}) end
    local logged={}
    local logging={ModRef=shared,log=function(message) logged[#logged+1]=message end,
        RegisterConsoleCommandHandler=function(name,callback) handlers[name]=callback;return true end}
    Events.subscribe(logging,Events.focus)
    values['MCC.Controls.GroupFocus.v1.data']='malformed'
    assert(handlers['MCC_Controls_GroupFocus_v1']()==true)
    print=realPrint
    assert(#logged==1 and logged[1]:find('event delivery failed: controls.group.focus',1,true),
        'the failure goes to the caller logger')
    assert(#printed==0,'nothing is printed directly')
    -- Without a logger the failure is still written, as a WARN through mc_log.
    local written={}
    package.loaded.mc_log=nil
    local Log=require('mc_log')
    local new=Log.new
    Log.new=function(options) options.write=function(line) written[#written+1]=line end;return new(options) end
    -- Subscribing while the stored event is unreadable reports it rather than failing.
    local late=Events.subscribe({ModRef=shared,RegisterConsoleCommandHandler=logging.RegisterConsoleCommandHandler},
        Events.focus)
    handlers['MCC_Controls_GroupFocus_v1']()
    Log.new=new
    assert(#written==2 and written[1]:find('^%[ModCore Events%] WARN event delivery failed'),tostring(written[1]))
    -- The next valid event still arrives.
    values['MCC.Controls.GroupFocus.v1.data']='4 1 2'
    handlers['MCC_Controls_GroupFocus_v1']()
    assert(late.revision==4 and late.payload.group.to==2)
end
print('PASS event delivery failures use the leveled logger')

-- Global slots: one flag per quickslot, wheel 1 abilities, wheel 2 consumables.
do
    local global=Events.subscribe(api,Events.global)
    local slots={{true,false,false,true},{false,false,true,false}}
    assert(publish(Events.global,{global=slots},owner))
    assert(values['MCC.Controls.SlotsGlobal.v1.data']=='1 10010010')
    assert(global.revision==1 and global.payload.global[1][4]==true and global.payload.global[2][3]==true
        and global.payload.global[2][1]==false)
    assert(Events.format(Events.global,{global=slots})
        =='controls.slots.global {"global":[[true,false,false,true],[false,false,true,false]]}')
    assert(not pcall(publish,Events.global,{global={{1,0,0,0},{}}},owner),'flags are booleans')
    assert(not pcall(publish,Events.global,{global={{}}},owner),'both wheels are required')
    -- The hub keeps the current set in state.controls.global, empty before any event.
    local state,received={},{}
    local hub=Events.hub(api,state,function(event) received[#received+1]=event end)
    assert(state.controls.global[1][1]==false and state.controls.global[2][4]==false)
    -- A template that attaches later reads the stored set at once.
    hub:register({events={[Events.global]=function() end}})
    assert(state.controls.global[1][1]==true and state.controls.global[1][2]==false)
    assert(received[1].name==Events.global and received[1].revision==1 and received[1].global[2][3]==true)
    assert(publish(Events.global,{global={{false,false,false,false},{true,true,true,true}}},owner))
    assert(#received==2 and state.controls.global[1][1]==false and state.controls.global[2][2]==true)
    assert(state.events[Events.global].revision==2)
    -- Focus state is untouched by the slots event.
    assert(state.revision==nil)
    hub:stop()
    values['MCC.Controls.SlotsGlobal.v1.data']='3 1001001'
    local late=Events.subscribe({ModRef=shared,RegisterConsoleCommandHandler=function() return true end,
        log=function() end},Events.global)
    assert(late.revision==0 and late.payload.global[1][1]==false,'a short bit string is skipped, not fatal')
end
print('PASS global slots event')
