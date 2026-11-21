-- The default environment's key check, against a stubbed engine library: it answers
-- only once it accepts a key that always exists, so a misbehaving check skips nothing.
package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
local answers
local library={IsValid=function() return true end,
    Key_IsValid=function(_,key) return answers[key.KeyName] end}
StaticFindObject=function(path) if path:find('KismetInputLibrary',1,true) then return library end end
FName=function(name) return name end
local env=require('mc_input_host').defaultEnvironment()
answers={SpaceBar=true,J=true,Bogus=false}
assert(env.validKey('J')==true and env.validKey('Bogus')==false,'trusted checker answers')
answers={SpaceBar=false,J=false,Bogus=false}
assert(env.validKey('J')==nil and env.validKey('Bogus')==nil,'untrusted checker is ignored')
print('PASS the engine key check is trusted only when it accepts SpaceBar')
