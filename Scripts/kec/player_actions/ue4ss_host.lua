local Runtime=require('kec.player_actions.runtime')
local Dispatch=require('kec.player_actions.dispatch')
local Delivery=require('kec.player_actions.delivery')
local targets=require('kec.player_actions.native_targets')
local keyCodes=require('kec.player_actions.key_codes')
local Events=require('kec.events')
local M={}
local function unwrap(v) if v==nil then return end local ok,x=pcall(function()return v:get()end);return ok and x or v end
local function valid(v)local ok,x=pcall(function()return v~=nil and v:IsValid()end);return ok and x==true end
local function full(v)local ok,x=pcall(function()return v:GetFullName()end);return ok and tostring(x)or nil end
local function path(v)local n=full(v);return n and(n:match('^%S+%s+(.+)$')or n)or nil end
local function each(v,fn)if type(v)=='table'then for k,x in pairs(v)do fn(k,x)end;return true end;return pcall(function()v:ForEach(function(k,x)fn(k,unwrap(x))end)end)end
local function find(class,pred)local ok,all=pcall(FindAllOf,class);if not ok or type(all)~='table'then return end;for _,v in ipairs(all)do if valid(v)and not(full(v)or''):find('Default__',1,true)and(not pred or pred(v))then return v end end end
local function prop(o,n)local ok,v=pcall(function()return o[n]end);return ok and unwrap(v)or nil end
function M.new(queue,log,category,events)
 events=events or Events.shared()
 if type(FindAllOf)~='function'or type(StaticFindObject)~='function'or type(StaticConstructObject)~='function'or FName==nil then return{events=events,
  subscribe=function(_,name,callback)return events:subscribe(name,callback)end,
  deactivate=function()return true end,apply=function()return false,'Enhanced Input runtime unavailable'end}end
 local playerInput=nil
 local function bridgeApi()
  local bridge=rawget(_G,'UE4SSLuaEventBridge')
  if type(bridge)~='table' or type(bridge.GetCapabilities)~='function' then
   return nil,'UE4SSLuaEventBridge unavailable'
  end
  local ok,caps=pcall(bridge.GetCapabilities)
  if not ok or type(caps)~='table' or caps.enhanced_input~=true or caps.explicit_target~=true
      or caps.detailed_errors~=true or tonumber(caps.api or 0)<4
      or tonumber(bridge.API_VERSION or 0)<4 then
   return nil,'UE4SSLuaEventBridge lacks the required Enhanced Input API 4'
  end
  if tostring(caps.target_ue4ss_commit or '')~='97b7e501' then
   return nil,'UE4SSLuaEventBridge targets an incompatible UE4SS build'
  end
  if type(bridge.OpenInputComponent)~='function' or type(bridge.BindAction)~='function'
      or type(bridge.CloseInputComponent)~='function' then
   return nil,'UE4SSLuaEventBridge action binding API unavailable'
  end
  return bridge
 end
 local function cls(n)return assert(StaticFindObject('/Script/EnhancedInput.'..n),'missing Enhanced Input class: '..n)end
 local function retain(kind,name)
  local outer;if kind=='InputAction'then outer=assert(StaticFindObject('/Engine/Transient.IMC_QuickslotsForever'),'missing persistent quickslots context')else local engine=assert(find('Engine'),'Engine unavailable');outer=assert(engine:GetOuter(),'Transient outer unavailable')end
  local o=StaticFindObject(path(outer)..(kind=='InputAction'and':'or'.')..name);if not valid(o)then o=StaticConstructObject(cls(kind),outer,FName(name),0xC0)end;return o
 end
 -- Native gates are a bounded, named pool (one per allowlisted action).
 -- Keep them rooted for the process lifetime, including while detached. The
 -- engine reference in a patched native asset is not our sole lifetime owner.
 local function retainGate(action,name)
  local gateClass=cls('InputTriggerChordAction')
  local gatePath=assert(path(action),'native gate owner unavailable')..':'..name
  local gate=StaticFindObject(gatePath)
  if not valid(gate)then
   -- RF_Transient | RF_MarkAsRootSet. The resulting internal RootSet bit is
   -- checked below; a Lua userdata reference alone does not retain a UObject.
   gate=StaticConstructObject(gateClass,action,FName(name),0xC0)
  end
  assert(valid(gate),'native gate construction failed: '..gatePath)
  assert(gate:IsA(gateClass),'unexpected object at native gate path: '..gatePath)
  assert(gate:HasAnyInternalFlags(0x40000000),
   'native gate is not rooted; restart the game before enabling controls: '..gatePath)
  return gate
 end
 local input={valid=valid,retain=retain,initializeIdentity=function(a)assert(StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')):Conv_ObjectToSoftObjectReference(a)end,retainTrigger=function(a,n)return StaticConstructObject(cls(n),a,0,0x40)end,key=keyCodes.toName,name=FName}
 local byName={};for _,a in ipairs(FindAllOf('InputAction')or{})do local n=full(a)and full(a):match('([^%.:/%s]+)$');if valid(a)and n then byName[n]=a end end
 local runtime=Runtime({category=category,nativeTargets=targets,resolve=function(n)return byName[n]end,valid=valid,path=path,unwrap=unwrap,same=function(a,b)return path(a)==path(b)end,each=each,retainInactive=function()local a=retain('InputAction','IA_KET_NativeActionGate');a.Triggers={};return a end,constructGate=retainGate,chord=function(t)return unwrap(t.ChordAction)end,setChord=function(t,a)t.ChordAction=a end,setTriggers=function(a,v)a.Triggers=v end,rebuild=function()local lib=assert(StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'),'EnhancedInputLibrary unavailable');each(playerInput.AppliedInputContexts,function(c)c=unwrap(c);if valid(c)then lib:RequestRebuildControlMappingsUsingContext(c,false)end end);return true end,input=input})
 local api,internal={},false
 api.events=events
 function api:subscribe(name,callback) return self.events:subscribe(name,callback) end
 local function contextName(kind)
  return kind=='RTCombat' and 'combat' or kind=='OW' and 'openworld' or kind
 end
 local function internalCall(fn)
  internal=true
  local result=table.pack(pcall(fn))
  internal=false
  if not result[1]then error(result[2],0)end
  return table.unpack(result,2,result.n)
 end
 local contextNames={combat={native='IMC_RTCombat.',kind='RTCombat'},openworld={native='IMC_OW.',kind='OW'}}
 local function gameplayInput()
  -- A stale controller can survive a map transition. Prefer the controller
  -- whose player input and pawn input component are both ready.
  local seen,firstInput,firstComponent={},nil,nil
  for _,class in ipairs({'BP_PlayerController_C','PlayerController'})do
   local ok,all=pcall(FindAllOf,class)
   if ok and type(all)=='table'then
    for _,pc in ipairs(all)do
     local name=full(pc)or''
     if valid(pc)and name:find('BP_PlayerController_C',1,true)
         and not name:find('Default__',1,true)and not seen[name]then
      seen[name]=true
      local input=prop(pc,'PlayerInput')
      local pawn=prop(pc,'AcknowledgedPawn') or prop(pc,'Pawn')
      local component=pawn and prop(pawn,'InputComponent')or nil
      if valid(input)and valid(component)then
       playerInput=input
       return input,component,pc
      end
      firstInput,firstComponent=firstInput or input,firstComponent or component
     end
    end
   end
  end
  playerInput=firstInput
  return firstInput,firstComponent,nil
 end
 local function playerSubsystem(pc)
  local ok,all=pcall(FindAllOf,'EnhancedInputLocalPlayerSubsystem')
  if not ok or type(all)~='table'then return nil end
  local localPlayer=pc and prop(pc,'Player')or nil
  local ownerPath=valid(localPlayer)and (full(localPlayer)or''):find('LocalPlayer',1,true)
      and path(localPlayer)or nil
  local only,count,ownerFound=nil,0,false
  for _,sub in ipairs(all)do
   if valid(sub)then
    count=count+1;only=sub
    local outer=prop(sub,'Outer')
    if not valid(outer)then
     local found,value=pcall(function()return sub:GetOuter()end)
     if found then outer=unwrap(value)end
    end
    if ownerPath and valid(outer)then
     ownerFound=true
     if path(outer)==ownerPath then return sub end
    end
   end
  end
  -- In single-player there is only one local-player subsystem. Do not choose
  -- arbitrarily when multiple local players are present.
  return count==1 and not ownerFound and only or nil
 end
 local function targets()
  local wanted,out={},{}
  if not api.template then return out end
  if category and type(category.contexts)=='table' then
   for _,logical in ipairs(category.contexts)do if contextNames[logical]then wanted[logical]=true end end
  elseif category and type(category.actions)=='table' then
   for _,action in pairs(category.actions)do
    if type(action)=='table' then
     for _,logical in ipairs(action.contexts or {})do if contextNames[logical]then wanted[logical]=true end end
    end
   end
  else
   for _,logical in ipairs(api.template.contexts or {})do if contextNames[logical]then wanted[logical]=true end end
  end
  each(playerInput.AppliedInputContexts,function(context,priority)
   local name=full(unwrap(context))or''
   for logical,spec in pairs(contextNames)do if wanted[logical] and name:find(spec.native,1,true)then out[spec.kind]=tonumber(priority)end end
  end)
  return out
 end
 local function deliver(definition,phase,generation)
  local queued,why=pcall(queue,function()
   if generation~=api.generation or not api.ready then return end
   local service=api.service
   if type(service)~='table' then return end
   local ok,result=pcall(Delivery.deliver,api.template,api,definition,phase,service)
   if not ok or result==false then log('Quickslots action dispatch failed: '..tostring(result)) end
  end)
  if not queued then log('Quickslots game-thread dispatch failed: '..tostring(why)) end
 end
 function api:deactivate(kind)
  self.active=self.active or {}
  if kind then
   internalCall(function()runtime:deactivate(kind)end)
   if self.active[kind] then self.events:emit('ControlContextDetached',contextName(kind)) end
   self.active[kind]=nil
  else
   for activeKind in pairs(self.active)do
    internalCall(function()runtime:deactivate(activeKind)end)
    self.events:emit('ControlContextDetached',contextName(activeKind))
   end
   self.active={}
  end
  if next(self.active)~=nil then return true end
  self.generation=(self.generation or 0)+1
  self.bound,self.ready=false,false
  if self.dispatcher then
   local closed,why=self.dispatcher:close()
   if not closed then log('Quickslots bridge close failed: '..tostring(why));return false,why end
   self.dispatcher=nil
   self.componentPath=nil
  end
  return true
 end
 function api:activate(kind,nativePriority,sub,component)
  local template,settings=self.template,self.settings
  if not template then return false,'no selected quickslots template' end
  if not self.bound then
   if self.dispatcher then
    local closed,closeWhy=self.dispatcher:close()
    if not closed then return false,closeWhy end
    self.dispatcher=nil
   end
   local bridge,bridgeWhy=bridgeApi()
   if not bridge then return false,bridgeWhy end
   local ok,actions,plan=pcall(function()return runtime:prepare(template,settings)end)
   if not ok then return false,actions end
   local dispatcher=Dispatch({bridge=bridge,fullName=full,componentPath=path})
   self.dispatcher=dispatcher
   local generation=(self.generation or 0)+1
   self.generation=generation
   local bound,bindWhy=dispatcher:bind(component,actions,plan,function(definition,phase)
    deliver(definition,phase,generation)
   end)
   if not bound then
    local closed,closeWhy=dispatcher:close()
    if closed then self.dispatcher=nil end
    return false,closed and bindWhy or tostring(bindWhy)..'; cleanup: '..tostring(closeWhy)
   end
   self.dispatcher,self.bound,self.ready,self.componentPath=dispatcher,true,false,path(component)
   self.groupTypes={}
   self.groupModes={}
   for _,definition in ipairs(plan.actions)do
    if definition.groupIndex and not definition.slot then
     self.groupTypes[definition.groupIndex]=definition.type
     self.groupModes[definition.groupIndex]=definition.binding.mode
    end
   end
   local preferred=(settings.access==1 or settings.PrimaryWheel==1)
       and 'ability' or 'consumable'
   for index,kind in pairs(self.groupTypes)do
    if kind==preferred then self.defaultGroup,self.selectedGroup=index,index end
   end
   for index,mode in pairs(self.groupModes)do
    if mode==-1 or mode==-2 then self.defaultGroup,self.selectedGroup=index,index;break end
   end
   self.defaultUnbound=(self.groupModes[self.defaultGroup]==-1 or self.groupModes[self.defaultGroup]==-2)
  end
  local committed,why=pcall(function()internalCall(function()runtime:commit(kind,sub,nativePriority)end)end)
  if not committed then
   pcall(function()runtime:deactivate(kind)end)
   self:deactivate()
   return false,why
  end
  self.active=self.active or {};self.active[kind]=nativePriority
  self.ready=true
  self.subsystem=sub
  self.events:emit('ControlContextAttached',contextName(kind))
  return true
 end
 function api:sync()
  if not self.template then return self:deactivate() end
  local input,component,pc=gameplayInput()
  local sub=playerSubsystem(pc)
  if not valid(input) or not valid(component) or not valid(sub) then
   self:deactivate();return false,'gameplay Enhanced Input stack unavailable'
  end
  if self.bound and (self.componentPath~=path(component) or self.subsystem~=sub) then self:deactivate() end
  local wanted=targets();self.active=self.active or {}
  if next(wanted)~=nil then self.nativeSeen=true end
  -- The local player's subsystem is the attachment owner. The game's native
  -- contexts identify gameplay mode when present, but are not a prerequisite
  -- for adding KEC's own context during the initial player load.
  if next(wanted)==nil and not self.nativeSeen then wanted.OW=0 end
  if next(wanted)==nil then self:deactivate();return false,'native gameplay context unavailable' end
  for kind in pairs(self.active)do if wanted[kind]==nil or wanted[kind]~=self.active[kind] then self:deactivate(kind)end end
  for kind,priority in pairs(wanted)do
   if self.active[kind]==nil then
    local ok,why=self:activate(kind,priority,sub,component)
    if not ok then return false,why end
   end
  end
  return true
 end
 local startRetry
 function api:apply(template,settings,service)
  local cleared,why=self:deactivate()
  if not cleared then return false,why end
  self.template,self.settings,self.service=template,settings,service
  self.defaultGroup=1
  self.selectedGroup=self.defaultGroup
  local active,reason=self:sync()
  if not active and startRetry then startRetry() end
  return active,reason
 end
 local retryScheduled=false
 startRetry=function()
  if retryScheduled or not api.template or type(ExecuteWithDelay)~='function' then return end
  if api.active and next(api.active)~=nil then return end
  retryScheduled=true
  local scheduled,why=pcall(ExecuteWithDelay,500,function()
   local queued,queueWhy=pcall(queue,function()
    retryScheduled=false
    local ran,active,reason=pcall(function()return api:sync()end)
    if not ran then log('Enhanced Input retry failed: '..tostring(active))
    elseif active then log('Quickslot controls attached to player input')
    else startRetry()end
   end)
   if not queued then
    retryScheduled=false
    log('Enhanced Input retry queue failed: '..tostring(queueWhy))
   end
  end)
  if not scheduled then
   retryScheduled=false
   log('Enhanced Input retry timer failed: '..tostring(why))
  end
 end
 local function wake()
  if internal then return end
  local queued,why=pcall(queue,function()
   local ran,ok,reason=pcall(function()return api:sync()end)
   if not ran then log('Enhanced Input lifecycle sync failed: '..tostring(ok))
   elseif ok==false then
    if reason~=api.lastPendingReason then log('Enhanced Input lifecycle sync pending: '..tostring(reason))end
    api.lastPendingReason=reason
    startRetry()
   else
    if api.lastPendingReason then log('Quickslot controls attached to player input')end
    api.lastPendingReason=nil
   end
  end)
  if not queued then log('Enhanced Input lifecycle wake failed: '..tostring(why))end
 end
 local function hook(path,after)
  local ok,why=pcall(RegisterHook,path,function()end,after)
  if not ok then log('Enhanced Input hook unavailable: '..path..': '..tostring(why))end
  return ok
 end
 local function notify(path)
  local ok,why=pcall(NotifyOnNewObject,path,function(object)if valid(unwrap(object))then wake()end end)
  if not ok then log('Enhanced Input creation notification unavailable: '..path..': '..tostring(why))end
 end
 hook('/Script/EnhancedInput.EnhancedInputSubsystemInterface:AddMappingContext',wake)
 hook('/Script/EnhancedInput.EnhancedInputSubsystemInterface:RemoveMappingContext',wake)
 hook('/Script/EnhancedInput.EnhancedInputSubsystemInterface:ClearAllMappings',wake)
 hook('/Script/Engine.PlayerController:ClientRestart',wake)
 hook('/Script/Engine.PlayerController:ClientRetryClientRestart',wake)
 hook('/Script/Engine.Controller:OnRep_Pawn',wake)
 notify('/Script/Engine.PlayerController')
 notify('/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem')
 -- The pawn's input component can be constructed after the controller and
 -- subsystem notifications. Recheck on the next game-thread turn, when its
 -- owner has had a chance to assign it to the pawn.
 notify('/Script/EnhancedInput.EnhancedInputComponent')
 if type(RegisterLoadMapPostHook)=='function' then
  local ok,why=pcall(RegisterLoadMapPostHook,function()wake()end)
  if not ok then log('Enhanced Input map-load hook unavailable: '..tostring(why))end
 end
 return api
end
return M
