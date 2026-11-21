local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate MCC Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$') or (scripts=='Scripts' and '.'),
    'cannot locate MCC root')
-- Files shared with other modules, unchanged, keep their own module names. Searched first,
-- so a copy left in Scripts by an earlier release is never loaded instead.
package.path = scripts .. '/vendor/?.lua;' .. scripts .. '/?.lua;' .. package.path

local queue=rawget(_G,'ExecuteInGameThread')
local host,unsubscribe
local log=require('mc_log').new({name='ModCoreControls'})
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
    require('safe_file').mkdir(root .. '/cache')
    local Page=require('mc_dmm')
    local page=Page.page
    local pages=require('menu_contributions').publisher(assert(rawget(_G,'ModRef'),'ModRef unavailable'),
        {id=page.id,directory=root .. '/cache'})
    -- The main page, then its inner pages: listed nowhere, opened from its Mappings links.
    local list={{id=page.id,name=page.name,author=page.author,version=page.version,
        description=page.description,attach=root:match('([^/\\]+)$'),
        hooks=scripts .. '/mcs_page.lua',configDirectory=root}}
    for _,inner in ipairs(Page.pages(require('mc_menu').define(require('mc_sections'),require('mc_maps')))) do
        list[#list+1]={id=inner.id,name=inner.name,description=inner.description,version=page.version,
            under=page.id,group='inner',hooks=scripts .. '/mcs_page.lua',configDirectory=root}
    end
    pages:publish({pages=list})
end)
if not published then log.error('Controls page unavailable: ',publishWhy) end
local ok,err=pcall(function()
    local definition=require('mc_menu').define(require('mc_sections'),require('mc_maps'))
    if type(queue)=='function' then
        host=require('mc_input_host').new(queue,log)
        -- Saved controls never stop input: an unusable config runs on the defaults.
        local function plan()
            local built,result=pcall(function()
                local store=require('mc_config').open(root .. '/config.ini',definition)
                if store.recoveryError then log.warn('config unavailable; using defaults: ',store.recoveryError) end
                local model=require('mc_menu').new(definition,store.values)
                -- A key saved twice keeps its first binding until the player fixes it.
                local plan=require('mc_input_plan').build(definition,model.values,{lenient=true})
                for _,why in ipairs(plan.skipped) do log.warn('binding skipped: ',why) end
                return plan
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
        local available,settings=pcall(require,'settings_api')
        if available and ModRef and type(RegisterConsoleCommandHandler)=='function' then
            -- Each Controls page publishes its own Apply.
            local ids={require('mc_dmm').page.id}
            for _,inner in ipairs(require('mc_dmm').pages(definition)) do ids[#ids+1]=inner.id end
            local tickets={}
            for _,id in ipairs(ids) do
                local subscribed,result=pcall(settings.subscribe,id,function()
                    refresh('Settings Apply')
                end)
                if subscribed then tickets[#tickets+1]=result
                else log.error('Settings Apply subscription failed for ',id,': ',result) end
            end
            if #tickets>0 then
                unsubscribe=function()
                    for _,ticket in ipairs(tickets) do ticket() end
                end
            end
        else
            log.warn('Settings Apply notifications unavailable; input refreshes on restart.')
        end
        assert(refresh('startup input'),'startup input scheduling failed')
    end
end)

if not ok then
    if type(queue)=='function' then
        local queued,why=pcall(queue,stopResources)
        if not queued or why==false then
            log.error('startup cleanup scheduling failed: ',why)
            stopResources()
        end
    else stopResources() end
    log.critical('startup failed: ',err)
else
    log.info(require('mc_dmm').page.version,' loaded; input attaches when gameplay is ready')
end
