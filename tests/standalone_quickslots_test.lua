package.path = 'Scripts/?.lua;' .. package.path

local applied = {count=0}
package.loaded['kec.player_actions.ue4ss_host'] = {
    new=function()
        return {apply=function(_,template,settings,service)
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
    assert(provider=='KEngineControls')
    onApply=callback
end}
ExecuteInGameThread=function(callback) callback() end
local cwd=assert(io.popen('pwd')):read('*l')
dofile(cwd .. '/Scripts/main.lua')
assert(applied.template.category == 'player.quickslots')
assert(applied.settings.access == 1)
assert(applied.settings.PrimaryWheel == 1)
assert(type(applied.service.activateQuickslot) == 'function')
assert(type(applied.service.selectQuickslotGroup) == 'function')
assert(KEngineControls.quickslotHost)
assert(applied.count==1 and type(onApply)=='function')
onApply({providerId='KEngineControls'})
assert(applied.count==2, 'KEC Apply must refresh controls without KET')
print('KEC quickslot input starts without a selected visual template')
