package.path = 'Scripts/?.lua;' .. package.path
-- Use the production host factory; replace only its Unreal boundary.
local registry,created={},{}
local function object(kind,path)
 local o={kind=kind,path=path,valid=true,Triggers={}}
 function o:IsValid()return self.valid end
 function o:GetFullName()return self.kind..' '..self.path end
 function o:IsA(class)return self.kind==class.kindName end
 function o:HasAnyInternalFlags(mask)assert(mask==0x40000000);return self.rooted==true end
 registry[path]=o;return o
end
local chordClass={kindName='InputTriggerChordAction'}
registry['/Script/EnhancedInput.InputTriggerChordAction']=chordClass
FindAllOf=function()return {}end
StaticFindObject=function(path)return registry[path]end
FName=function(name)return name end
local honorRoot=true
StaticConstructObject=function(class,outer,name,flags)
 assert(class==chordClass and flags==0xC0,'gate must request transient and rooted flags')
 local path=outer.path..':'..name
 assert(not registry[path],'must reuse a detached named gate')
 local o=object(class.kindName,path);o.rooted=honorRoot;created[#created+1]=o;return o
end
RegisterHook=function()end
NotifyOnNewObject=function()end
local hostEnv
package.loaded['mc.player_actions.runtime']=function(env)hostEnv=env;return {}end
local Host=require('mc.player_actions.ue4ss_host')
Host.new(function(fn)fn()end,function()end)
local retain=hostEnv.constructGate
local native={}
for _,name in ipairs({'Left','Top','Right','Bottom','CombatToggle','OWToggle'})do
 native[#native+1]=object('InputAction','/Game/Native.'..name)
end
local foreign=object('InputTriggerHold','/Game/Native.Left:OriginalHold')
native[1].Triggers={foreign}
local inactive=object('InputAction','/Engine/Transient.Inactive')
local rebuilds,failRebuild=0,false
local Gates=require('mc.player_actions.action_gates')
local function manager(factory)
 return Gates({marker='MCC_NativeActionGate',valid=function(v)return v and v.valid end,
  path=function(v)return v.path end,same=function(a,b)return a==b end,
  each=function(values,fn)for i,v in ipairs(values)do fn(i,v)end end,
  actions=function()return native end,retainInactive=function()return inactive end,
  construct=factory,chord=function(g)return g.ChordAction end,
  setChord=function(g,a)g.ChordAction=a end,setTriggers=function(a,t)a.Triggers=t end,
  rebuild=function()if failRebuild then error('injected rebuild failure')end;rebuilds=rebuilds+1;return true end})
end
local gates=manager(retain)
gates:update(function()return true end)
assert(#created==6 and rebuilds==1)
for i,action in ipairs(native)do
 local g=action.Triggers[#action.Triggers]
 assert(g==created[i] and g.rooted and g.ChordAction==inactive)
end
for _=1,3 do gates:update(function()return true end)end
assert(#created==6 and rebuilds==1,'repeated updates must reuse gates without rebuilding')
gates:restoreAll()
assert(#native[1].Triggers==1 and native[1].Triggers[1]==foreign)
for i=2,#native do assert(#native[i].Triggers==0)end
-- Model collection independently of action arrays; actual Unreal GC still
-- requires live acceptance. Rooted detached gates must survive this boundary.
for _,g in ipairs(created)do if not g.rooted then g.valid=false end end
for _,g in ipairs(created)do assert(g.valid)end
Host.new(function(fn)fn()end,function()end)
gates=manager(hostEnv.constructGate)
gates:update(function()return true end)
assert(#created==6 and native[1].Triggers[2]==created[1],'new Lua host must reuse engine pool')
failRebuild=true
local ok=pcall(function()gates:restoreAll()end);assert(not ok)
for _,g in ipairs(created)do assert(g.valid and g.rooted)end
assert(#native[1].Triggers==1 and native[1].Triggers[1]==foreign)
failRebuild=false;gates:restoreAll();gates:update(function()return true end)
assert(#created==6,'failed removal rebuild must not free/reconstruct gates')
created[1].rooted=false
local ok,why=pcall(function()gates:update(function()return true end)end)
assert(not ok and tostring(why):find('not rooted',1,true) and #created==6,
 'an attached existing gate must still have its ownership checked')
created[1].rooted=true;gates:restoreAll()
honorRoot=false
local extra=object('InputAction','/Game/Test.Unrooted')
local ok,why=pcall(retain,extra,'MCC_NativeActionGate')
assert(not ok and tostring(why):find('not rooted',1,true),'verify actual root state, not requested flags')
local collision=object('InputAction','/Game/Test.Collision')
object('InputTriggerHold',collision.path..':MCC_NativeActionGate').rooted=true
local count=#created
local ok,why=pcall(retain,collision,'MCC_NativeActionGate')
assert(not ok and tostring(why):find('unexpected object',1,true) and #created==count)
local failedWalk=manager(retain)
local saved=hostEnv.each
-- The manager must fail before writing trigger arrays when Unreal enumeration
-- reports a partial/failed traversal.
local guarded=Gates({marker='MCC_NativeActionGate',valid=function(v)return v and v.valid end,
 path=function(v)return v.path end,same=function(a,b)return a==b end,
 each=function(values,fn)if values[1]then fn(1,values[1])end;return false end,
 actions=function()return native end,retainInactive=function()return inactive end,
 construct=retain,chord=function(g)return g.ChordAction end,
 setChord=function(g,a)g.ChordAction=a end,setTriggers=function()error('must not write')end,
 rebuild=function()error('must not rebuild')end})
local ok,why=pcall(function()guarded:update(function()return true end)end)
assert(not ok and tostring(why):find('cannot inspect native action triggers',1,true))
print('PASS native gate ownership: root checks, reuse after detach/reload, restoration retry, unrooted/collision rejection')
