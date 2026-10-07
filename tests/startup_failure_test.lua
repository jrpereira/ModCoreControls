package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
local queued,stopped,unsubscribed=0,0,0
ExecuteInGameThread=function(callback)
    queued=queued+1
    if queued==1 then return false end
    callback();return true
end
ModRef={}
RegisterConsoleCommandHandler=function() end
package.loaded['mc_input_host']={new=function()
    return {stop=function() stopped=stopped+1;return true end,
        apply=function() error('startup refresh should not execute') end}
end}
package.loaded['settings_api']={subscribe=function()
    return function() unsubscribed=unsubscribed+1;return true end
end}
local source=assert(os.getenv('PWD'))..'/Scripts/main.lua'
assert(loadfile(source))()
assert(ModCoreControls==nil and queued==2 and stopped==1 and unsubscribed==1)
queued,stopped,unsubscribed=0,0,0
ExecuteInGameThread=function()
    queued=queued+1
    return false
end
assert(loadfile(source))()
assert(ModCoreControls==nil and queued==2 and stopped==1 and unsubscribed==1)
print('PASS failed MCC startup revokes the facade and cleans constructed host and subscription')
