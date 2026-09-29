local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate MCC Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$') or (scripts=='Scripts' and '.'),
    'cannot locate MCC root')
package.path = scripts .. '/?.lua;' .. package.path

local ok, err = pcall(function()
    local sections = require('mc_sections')
    local maps = require('mc_maps')
    ModCoreControls = {
        addSection = sections.addSection,
        addSectionMap = maps.addSectionMap,
    }
    if type(ExecuteInGameThread)=='function' then
        local function log(message) print('[ModCoreControls] ' .. tostring(message) .. '\n') end
        local definition=require('mc_menu').define(sections,maps)
        local host=require('mc_input_host').new(ExecuteInGameThread,log)
        local function plan()
            local store=require('mc_config').open(root .. '/config.ini',definition)
            local model=require('mc_menu').new(definition,store.values)
            return require('mc_input_plan').build(definition,model.values)
        end
        local function refresh(label)
            ExecuteInGameThread(function()
                local ran,active,why=pcall(function() return host:apply(plan()) end)
                if not ran then log((label or 'input refresh') .. ' failed: ' .. tostring(active))
                elseif not active and why~='gameplay Enhanced Input stack unavailable' then
                    log((label or 'input refresh') .. ' pending: ' .. tostring(why))
                end
            end)
        end
        ModCoreControls.inputHost=host
        ModCoreControls.refresh=function() refresh('manual input refresh') end
        ModCoreControls.deactivate=function()
            ExecuteInGameThread(function()
                local removed,why=host:deactivate()
                if not removed then log('input deactivation failed: ' .. tostring(why)) end
            end)
        end
        local unsubscribe
        ModCoreControls.stop=function()
            ExecuteInGameThread(function()
                local removed,why=host:stop()
                if not removed then log('input stop cleanup pending: ' .. tostring(why)) end
                if type(unsubscribe)=='function' then
                    local ok,err=pcall(unsubscribe)
                    if not ok then log('settings unsubscribe failed: ' .. tostring(err)) end
                    unsubscribe=nil
                end
            end)
        end
        local mods=assert(root:match('^(.*)[/\\][^/\\]+$'),'Mods folder unavailable')
        package.path=mods .. '/_ModCore_1_Settings/Scripts/?.lua;' .. package.path
        local available,settings=pcall(require,'settings_api')
        if available and ModRef and type(RegisterConsoleCommandHandler)=='function' then
            local subscribed,result=pcall(settings.subscribe,'ModCoreControls',function()
                refresh('DMM Apply')
            end)
            if subscribed then unsubscribe=result
            else log('DMM Apply subscription failed: ' .. tostring(result)) end
        else
            log('DMM Apply notifications unavailable; input refreshes on restart.')
        end
        refresh('startup input')
    end
end)

if not ok then
    print('[ModCoreControls] startup failed: ' .. tostring(err) .. '\n')
else
    print('[ModCoreControls] 0.1.1 loaded; input attaches when gameplay is ready\n')
end
