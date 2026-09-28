package.path='Scripts/?.lua;'..package.path
local objects,constructed={},{}
local function make(kind,path)
    local object={kind=kind,path=path}
    function object:IsValid() return true end
    function object:GetFullName() return self.kind..' '..self.path end
    objects[path]=object
    return object
end
local transient=make('Package','/Engine/Transient')
local engine=make('Engine','/Engine/Transient.Engine_0')
function engine:GetOuter() return transient end
FindAllOf=function(kind) return kind=='Engine' and {engine} or {} end
StaticFindObject=function(path)
    if path:match('^/Script/EnhancedInput%.') then return {kind=path:match('([^%.]+)$')} end
    return objects[path]
end
StaticConstructObject=function(class,outer,name,flags)
    assert(flags==0xC0)
    local path=outer.path..(class.kind=='InputAction' and ':' or '.')..name
    assert(not objects[path])
    constructed[#constructed+1]=path
    return make(class.kind,path)
end
FName=function(value) return value end
RegisterHook=function() end
NotifyOnNewObject=function() end
local env
package.loaded['mc.player_actions.runtime']=function(value) env=value;return {} end
require('mc.player_actions.ue4ss_host').new(function(callback)callback()end,function()end)
local first=env.input.retain('InputAction','IA_SharedSlot1')
assert(first.path=='/Engine/Transient.IMC_MCC_ActionOwner:IA_SharedSlot1')
assert(#constructed==2 and constructed[1]=='/Engine/Transient.IMC_MCC_ActionOwner')
assert(env.input.retain('InputAction','IA_SharedSlot1')==first)
assert(#constructed==2,'action owner and action should be reused')
print('PASS fresh MCC action owner construction and reuse')
