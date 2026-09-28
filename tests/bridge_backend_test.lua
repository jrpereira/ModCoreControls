package.path='Scripts/?.lua;'..package.path
local Backend=require('mc.bridge_backend')
local scope={canClose=false,closeCalls=0}
function scope:Bind() return nil,'binding rejected' end
function scope:Close()
    self.closeCalls=self.closeCalls+1
    return self.canClose,'scope close failed'
end
local bridge={
    GetCapabilities=function() return {api=4,helpers=true,trigger_tap=true,trigger_hold=true} end,
    Helpers={Trigger={Tap=1,Hold=2},OpenInput=function() return scope end},
}
local backend=Backend.new({bridge=bridge,targets=function() return 'component','subsystem' end,
    queue=function(callback) callback() end})
local installation,why,cleanup=backend:install({{key='F10',trigger='Tap',action='dash'}},function() end)
assert(installation==nil and why:find('cleanup',1,true) and cleanup)
assert(scope.closeCalls==1)
scope.canClose=true
assert(cleanup:close() and scope.closeCalls==2)
scope.canClose=true
scope.Bind=function() error('invalid provider option') end
local ok,problem=backend:install({{key='F10',trigger='Tap',action='dash'}},function()end)
assert(not ok and problem:find('binding failed',1,true) and scope.closeCalls==3,
    'throwing Bind must close its open scope')
print('PASS failed partial bridge binding retains cleanup handle')
