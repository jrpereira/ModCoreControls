local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate MCC Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$') or (scripts=='Scripts' and '.'),
    'cannot locate MCC root')
package.path = scripts .. '/?.lua;' .. package.path

local queue=rawget(_G,'ExecuteInGameThread')
local host,unsubscribe
local function log(message) print('[ModCoreControls] ' .. tostring(message) .. '\n') end
local function stopResources()
    if host then
        local ok,removed,why=pcall(host.stop,host)
        if not ok or removed==false then
            log('input stop cleanup pending: '..tostring(ok and why or removed))
        end
    end
    if type(unsubscribe)=='function' then
        local ok,result,why=pcall(unsubscribe)
        if ok and result~=false then unsubscribe=nil
        else log('settings unsubscribe failed: '..tostring(ok and why or result)) end
    end
end
local ok,err=pcall(function()
    local sections=require('mc_sections')
    local maps=require('mc_maps')
    local definition=require('mc_menu').define(sections,maps)
    local facade={addSection=sections.addSection,addSectionMap=maps.addSectionMap}
    if type(queue)=='function' then
        host=require('mc_input_host').new(queue,log)
        local function plan()
            local store=require('mc_config').open(root .. '/config.ini',definition)
            local model=require('mc_menu').new(definition,store.values)
            return require('mc_input_plan').build(definition,model.values)
        end
        local function refresh(label)
            local queued,why=pcall(queue,function()
                local ran,active,reason=pcall(function() return host:apply(plan()) end)
                if not ran then log((label or 'input refresh') .. ' failed: ' .. tostring(active))
                elseif not active and reason~='gameplay Enhanced Input stack unavailable' then
                    log((label or 'input refresh') .. ' pending: ' .. tostring(reason))
                end
            end)
            if not queued or why==false then
                log((label or 'input refresh') .. ' scheduling failed: '..tostring(why))
                return false
            end
            return true
        end
        facade.inputHost=host
        facade.refresh=function() return refresh('manual input refresh') end
        facade.deactivate=function()
            return queue(function()
                local removed,why=host:deactivate()
                if not removed then log('input deactivation failed: ' .. tostring(why)) end
            end)
        end
        facade.stop=function()
            local queued,why=pcall(queue,stopResources)
            if not queued or why==false then
                log('input stop scheduling failed: '..tostring(why))
                return false
            end
            return true
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
        assert(refresh('startup input'),'startup input scheduling failed')
    end
    ModCoreControls=facade
end)

if not ok then
    if type(queue)=='function' then
        local queued,why=pcall(queue,stopResources)
        if not queued or why==false then
            log('startup cleanup scheduling failed: '..tostring(why))
            stopResources()
        end
    else stopResources() end
    ModCoreControls=nil
    log('startup failed: '..tostring(err))
else
    log('0.1.1 loaded; input attaches when gameplay is ready')
end
