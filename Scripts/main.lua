local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate MCC Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$') or (scripts=='Scripts' and '.'),
    'cannot locate MCC root')
package.path = scripts .. '/?.lua;' .. package.path

local queue=rawget(_G,'ExecuteInGameThread')
local host,unsubscribe
-- The level comes from log_level.txt in the mod folder; WARN without it.
local log=require('mc_log').new({name='ModCoreControls',path=root .. '/log_level.txt'})
local function stopResources()
    if host then
        local ok,removed,why=pcall(host.stop,host)
        if not ok or removed==false then
            log.warn('input stop cleanup pending: ',ok and why or removed)
        end
    end
    if type(unsubscribe)=='function' then
        local ok,result,why=pcall(unsubscribe)
        if ok and result~=false then unsubscribe=nil
        else log.warn('settings unsubscribe failed: ',ok and why or result) end
    end
end
-- ModCoreSettings builds the Controls page from mcs_page.lua. Publish it first so
-- the menu stays available even when input startup fails.
local published,publishWhy=pcall(function()
    -- The cache directory is not shipped; create it for the page descriptors.
    local cache=root .. '/cache'
    local command
    if package.config:sub(1,1)=='\\' then
        -- Quoting alone does not prevent cmd.exe environment expansion.
        assert(not cache:find('["%%!\r\n]'),'unsupported cache path')
        cache=cache:gsub('/','\\')
        command='if not exist "' .. cache .. '" mkdir "' .. cache .. '"'
    else
        command="mkdir -p -- '" .. cache:gsub("'","'\\''") .. "'"
    end
    local made=os.execute(command)
    assert(made==true or made==0,'cannot create cache directory')
    local page=require('mc_dmm').page
    local pages=require('menu_contributions').publisher(assert(rawget(_G,'ModRef'),'ModRef unavailable'),
        {id=page.id,directory=root .. '/cache'})
    pages:publish({pages={{id=page.id,name=page.name,author=page.author,version=page.version,
        description=page.description,attach=root:match('([^/\\]+)$'),
        hooks=scripts .. '/mcs_page.lua',configDirectory=root}}})
end)
if not published then log.error('Controls page unavailable: ',publishWhy) end
local ok,err=pcall(function()
    local sections=require('mc_sections')
    local maps=require('mc_maps')
    local definition=require('mc_menu').define(sections,maps)
    local facade={addSection=sections.addSection,addSectionMap=maps.addSectionMap}
    if type(queue)=='function' then
        host=require('mc_input_host').new(queue,log)
        -- Saved controls never stop input: an unusable config runs on the defaults.
        local function plan()
            local built,result=pcall(function()
                local store=require('mc_config').open(root .. '/config.ini',definition)
                if store.recoveryError then log.warn('config unavailable; using defaults: ',store.recoveryError) end
                local model=require('mc_menu').new(definition,store.values)
                return require('mc_input_plan').build(definition,model.values)
            end)
            if built then return result end
            log.warn('saved controls unusable; using defaults: ',result)
            return require('mc_input_plan').build(definition,require('mc_menu').new(definition).values)
        end
        local function refresh(label)
            label=label or 'input refresh'
            local queued,why=pcall(queue,function()
                local ran,active,reason=pcall(function() return host:apply(plan()) end)
                if not ran then log.error(label,' failed: ',active)
                elseif not active then log.debug(label,' pending: ',reason) end
            end)
            if not queued or why==false then
                log.error(label,' scheduling failed: ',why)
                return false
            end
            return true
        end
        facade.inputHost=host
        facade.refresh=function() return refresh('manual input refresh') end
        facade.deactivate=function()
            local queued,why=pcall(queue,function()
                local removed,reason=host:deactivate()
                if not removed then log.error('input deactivation failed: ',reason) end
            end)
            if not queued or why==false then
                log.error('input deactivation scheduling failed: ',why)
                return false
            end
            return true
        end
        facade.stop=function()
            local queued,why=pcall(queue,stopResources)
            if not queued or why==false then
                log.error('input stop scheduling failed: ',why)
                return false
            end
            return true
        end
        local mods=assert(root:match('^(.*)[/\\][^/\\]+$'),'Mods folder unavailable')
        package.path=mods .. '/1_ModCore_Settings/Scripts/?.lua;' .. package.path
        local available,settings=pcall(require,'settings_api')
        if available and ModRef and type(RegisterConsoleCommandHandler)=='function' then
            local subscribed,result=pcall(settings.subscribe,'ModCoreControls',function()
                refresh('DMM Apply')
            end)
            if subscribed then unsubscribe=result
            else log.error('DMM Apply subscription failed: ',result) end
        else
            log.warn('DMM Apply notifications unavailable; input refreshes on restart.')
        end
        assert(refresh('startup input'),'startup input scheduling failed')
    end
    ModCoreControls=facade
end)

if not ok then
    if type(queue)=='function' then
        local queued,why=pcall(queue,stopResources)
        if not queued or why==false then
            log.error('startup cleanup scheduling failed: ',why)
            stopResources()
        end
    else stopResources() end
    ModCoreControls=nil
    log.critical('startup failed: ',err)
else
    log.info(require('mc_dmm').page.version,' loaded; input attaches when gameplay is ready')
end
