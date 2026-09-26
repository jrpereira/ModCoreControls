package.path = 'Scripts/?.lua;' .. package.path

local applied = {count=0}
local inGameThread=false
package.loaded['mcc.player_actions.ue4ss_host'] = {
    new=function()
        return {apply=function(_,template,settings,service)
            assert(inGameThread,'all quickslot Apply work must run on the game thread')
            applied.count=applied.count+1
            applied.template,applied.settings,applied.service=template,settings,service
            return true
        end}
    end,
}
local onApply
ModRef={}
RegisterConsoleCommandHandler=function() end
package.loaded.settings_api={subscribe=function(provider,callback)
    assert(provider=='ModCoreControls')
    onApply=callback
end}
ExecuteInGameThread=function(callback) inGameThread=true;callback();inGameThread=false end
local cwd=assert(io.popen('pwd')):read('*l')
dofile(cwd .. '/Scripts/main.lua')
assert(applied.template.category == 'player.quickslots')
assert(applied.settings.access == 1)
assert(applied.settings.PrimaryWheel == 1)
assert(type(applied.service.activateQuickslot) == 'function')
assert(type(applied.service.selectQuickslotGroup) == 'function')
assert(ModCoreControls.quickslotHost)
assert(applied.count==1 and type(onApply)=='function')
onApply({providerId='ModCoreControls'})
assert(applied.count==2, 'MCC Apply must refresh controls without MCC')
print('MCC quickslot input starts without a selected visual template')
