package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
-- main.lua publishes the Controls page to ModCoreSettings before input startup,
-- so the menu stays available even when input cannot start.
local Contributions=dofile('Scripts/vendor/menu_contributions.lua')
local published,options={}
package.loaded['menu_contributions']={publisher=function(shared,given)
    assert(shared==ModRef,'the page publishes through this mod\'s shared variables')
    options=given
    return {publish=function(_,contribution)
        assert(Contributions.validate(given.id,contribution))
        published[#published+1]=contribution
        return #published
    end}
end}
ModRef={}
ExecuteInGameThread=function() error('input startup failed') end
local root=assert(os.getenv('PWD'))
local printed,print_={},print
print=function(line) printed[#printed+1]=tostring(line) end
assert(loadfile(root .. '/Scripts/main.lua'))()
print=print_
local failed=false
for _,line in ipairs(printed) do
    if line:find('CRITICAL',1,true) and line:find('startup failed',1,true) then failed=true end
end
assert(failed,'input startup must still fail in this test: '..table.concat(printed,' / '))
assert(#published==1,'the page is published although input startup failed')
local page=published[1].pages[1]
assert(page.id=='ModCoreControls' and page.name=='Controls')
-- Hidden: ModCore Settings shows it as its Controls tab.
assert(page.visible==false and page.attach==nil,'the main page is shown in the Controls tab')
-- Then its inner pages, listed nowhere and opened from the main page's Mappings links.
local inner={}
local pages=published[1].pages
local entry=table.remove(pages)
for n=2,#pages do
    local child=published[1].pages[n]
    assert(child.under=='ModCoreControls' and child.group=='inner' and child.hooks==root .. '/Scripts/mcs_page.lua'
        and child.configDirectory==root,child.id)
    inner[#inner+1]=child.id..'='..child.name
end
assert(table.concat(inner,',')=='ModCoreControls.grouped=Group Keys,ModCoreControls.global=Global Keys,'
    ..'ModCoreControls.controller=Controller',table.concat(inner,','))
assert(page.hooks==root .. '/Scripts/mcs_page.lua' and page.configDirectory==root)
-- Last, the mod's entry: it replaces this mod folder's placeholder and opens the tab.
assert(entry.id=='ModCoreControls.entry' and entry.link=='settings:controls'
    and entry.attach==root:match('([^/\\]+)$') and not entry.hooks and not entry.configDirectory,entry.id)
-- Every main page setting, in page order, goes into the tab.
local rows=published[1].rows
assert(#rows==1 and rows[1].page=='ModCoreControls' and rows[1].slot=='settings:controls')
local DMM=require('mc_dmm')
assert(table.concat(rows[1].settings,',')==table.concat(DMM.ids(DMM.manifest()),',')
    and rows[1].settings[1]=='MCC_Visuals_Pending' and rows[1].settings[2]=='MCC_Link_grouped'
    and rows[1].settings[#rows[1].settings]=='MCC_module_default_KeyOutline',table.concat(rows[1].settings,','))
assert(options.id=='ModCoreControls' and options.directory==root .. '/cache')

-- The hooks file follows ModCoreSettings' hooks contract 1.
local hooks=dofile(page.hooks)
assert(hooks.contract==1 and type(hooks.manifest)=='function'
    and type(hooks.load)=='function' and type(hooks.apply)=='function')
assert(hooks.manifest({page=page.id,directory=page.configDirectory}):find('mcLinkPage=ModCoreControls.grouped',1,true))
assert(hooks.manifest({page='ModCoreControls.controller',directory=page.configDirectory}):find('[Setting.MCC_Pad_Note]',1,true))
print('PASS main publishes the Controls page before input startup')

-- The page version is the release's VERSION, whether loaded relatively or by full path.
local released=assert(io.open('VERSION','rb')):read('a'):match('^%s*(%S+)')
package.loaded.mc_dmm=nil
assert(require('mc_dmm').page.version==released,'page version must come from VERSION')
local absolute=assert(io.popen('pwd')):read('l')..'/Scripts/mc_dmm.lua'
assert(dofile(absolute).page.version==released,'page version must resolve from a full path')
print('PASS the page version comes from VERSION')

-- With the cache folder present, startup runs no shell command to create it.
do
    local execute,ran=os.execute,0
    os.execute=function(...) ran=ran+1;return execute(...) end
    assert(os.rename(root..'/cache',root..'/cache'),'the cache folder exists for this check')
    assert(loadfile(root .. '/Scripts/main.lua'))()
    os.execute=execute
    assert(ran==0,'an existing cache folder must not be created again')
end
print('PASS startup creates the cache folder only when missing')
