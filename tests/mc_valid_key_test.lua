-- The default environment's key check, against a stubbed engine library: it answers
-- only once it accepts a key that always exists, so a misbehaving check skips nothing.
package.path='Scripts/?.lua;'..package.path
local answers
local library={IsValid=function() return true end,
    Key_IsValid=function(_,key) return answers[key.KeyName] end}
StaticFindObject=function(path) if path:find('KismetInputLibrary',1,true) then return library end end
FName=function(name) return name end
FindAllOf=function() return {} end
-- defaultEnvironment is local; reach it through new() with no environment.
local captured
local Context=require('mc_input_context')
local new=Context.new
Context.new=function(e,...) captured=e;return new(e,...) end
require('mc_input_host').new(function() return true end,function() end,{})
Context.new=new
local env=assert(captured)
answers={SpaceBar=true,J=true,Bogus=false}
assert(env.validKey('J')==true and env.validKey('Bogus')==false,'trusted checker answers')
answers={SpaceBar=false,J=false,Bogus=false}
assert(env.validKey('J')==nil and env.validKey('Bogus')==nil,'untrusted checker is ignored')
print('PASS the engine key check is trusted only when it accepts SpaceBar')
