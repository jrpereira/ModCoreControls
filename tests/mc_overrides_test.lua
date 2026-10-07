package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local registry,created={},{}
local function object(kind,path)
    local value={kind=kind,path=path,valid=true,Triggers={}}
    function value:IsValid()return self.valid end
    registry[path]=value;return value
end
local first=object('InputAction','/Game/Input.IA_First')
local second=object('InputAction','/Game/Input.IA_Second')
local foreign=object('InputTriggerHold','/Game/Input.IA_First:Foreign')
first.Triggers={foreign}
local inactive=object('InputAction','/Engine/Transient.IA_MCC_OverrideInactive')
local rebuilds=0
local manager=require('mc_overrides').new({
    marker='MCC_OverrideChord',valid=function(value)return value and value.valid end,
    path=function(value)return value.path end,unwrap=function(value)return value end,
    same=function(a,b)return a==b end,
    each=function(values,callback)for i,value in ipairs(values)do callback(value,i)end;return true end,
    actions=function()return {first,second}end,inactive=function()return inactive end,
    construct=function(action,marker)
        local path=action.path..':'..marker
        if registry[path] then return registry[path] end
        local gate=object('InputTriggerChordAction',path);gate.rooted=true
        created[#created+1]=gate;return gate
    end,
    chord=function(gate)return gate.ChordAction end,
    setChord=function(gate,action)gate.ChordAction=action end,
    setTriggers=function(action,triggers)action.Triggers=triggers end,
    rebuild=function()rebuilds=rebuilds+1;return true end,
})
assert(manager:apply({[first.path]=true,[second.path]=true},{}))
assert(#created==2 and rebuilds==1 and #first.Triggers==2 and first.Triggers[1]==foreign)
assert(created[1].ChordAction==inactive and created[2].ChordAction==inactive)
assert(manager:apply({[first.path]=true,[second.path]=true},{}))
assert(#created==2 and rebuilds==1,'existing override chords must be reused without a rebuild')
assert(manager:apply({[second.path]=true},{}))
assert(#first.Triggers==1 and first.Triggers[1]==foreign and #second.Triggers==1)
assert(manager:restoreAll({}))
assert(#first.Triggers==1 and first.Triggers[1]==foreign and #second.Triggers==0)
assert(#created==2 and created[1].rooted and created[2].rooted)
local failed=false
local rollback=require('mc_overrides').new({
    marker='MCC_OverrideChord',valid=function(value)return value and value.valid end,
    path=function(value)return value.path end,unwrap=function(value)return value end,
    same=function(a,b)return a==b end,
    each=function(values,callback)for i,value in ipairs(values)do callback(value,i)end;return true end,
    actions=function()return {first}end,inactive=function()return inactive end,
    construct=function()return created[1]end,
    chord=function(gate)return gate.ChordAction end,
    setChord=function(gate,action)gate.ChordAction=action end,
    setTriggers=function(action,triggers)action.Triggers=triggers end,
    rebuild=function()if not failed then failed=true;error('injected rebuild failure')end;return true end,
})
assert(not pcall(rollback.apply,rollback,{[first.path]=true},{}))
assert(#first.Triggers==1 and first.Triggers[1]==foreign,'failed override must restore native triggers')
print('PASS native override chord ownership, reuse, and restoration')
