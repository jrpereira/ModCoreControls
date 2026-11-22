-- An Apply in ModCore Settings reaches MCC's input refresh through the vendored
-- settings_api (v2 or later), also when it carries text values: a keybind or a range.
package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
local jobs,handlers,shared={}, {}, {}
ExecuteInGameThread=function(callback) jobs[#jobs+1]=callback;return true end
ModRef={GetSharedVariable=function(_,key) return shared[key] end,
    SetSharedVariable=function(_,key,value) shared[key]=value end}
RegisterConsoleCommandHandler=function(command,callback) handlers[command]=callback;return true end
local applies=0
package.loaded['mc_input_host']={new=function()
    return {apply=function() applies=applies+1;return true end,stop=function() return true end}
end}
local function hex(value) return (value:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
local function drain() while #jobs>0 do table.remove(jobs,1)() end end

assert(require('settings_api').version>=2,'MCC vendors settings_api v2 or later')
local source=assert(os.getenv('PWD'))..'/Scripts/main.lua'
assert(loadfile(source))()
drain()
assert(applies==1,'startup applies once')
local command='MC_SettingsApplied_v2_'..hex('ModCoreControls')
assert(handlers[command],'MCC subscribes to the v2 Apply notification')

-- ModCore Settings publishes an Apply: a keybind and a range change, as text.
local function apply(revision,rows)
    local lines={tostring(revision)}
    for _,row in ipairs(rows) do
        lines[#lines+1]=hex(row[1])..' '..row[2]..' '..row[3]
    end
    shared[command..'.data']=table.concat(lines,'\n')
    handlers[command]()
    drain()
end
apply(1,{{'global.AbilitySlot1','s'..hex('One'),'s'..hex('J')}})
assert(applies==2,'an Apply carrying a keybind reaches refresh()')
apply(2,{{'HoldThreshold','s'..hex('100|350'),'s'..hex('150|400')},{'InstantTap','n1','n0'}})
assert(applies==3,'an Apply carrying a range reaches refresh()')
apply(2,{{'InstantTap','n0','n1'}})
assert(applies==3,'a repeated revision is not applied twice')
print('PASS an Apply with keybind or range values reaches the input refresh')
