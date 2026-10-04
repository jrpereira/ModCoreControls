package.path='Scripts/?.lua;'..package.path
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
