package.path='Scripts/?.lua;'..package.path
-- main.lua publishes the Controls page to ModCoreSettings before input startup,
-- so the menu stays available even when input cannot start.
local Contributions=dofile('Scripts/menu_contributions.lua')
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
assert(loadfile(root .. '/Scripts/main.lua'))()
assert(ModCoreControls==nil,'input startup must still fail in this test')
assert(#published==1,'the page is published although input startup failed')
local page=published[1].pages[1]
assert(#published[1].pages==1 and page.id=='ModCoreControls' and page.name=='Controls')
assert(page.hooks==root .. '/Scripts/mcs_page.lua' and page.configDirectory==root)
assert(page.attach==root:match('([^/\\]+)$'),'the page replaces this mod folder\'s placeholder')
assert(options.id=='ModCoreControls' and options.directory==root .. '/cache')

-- The hooks file follows ModCoreSettings' hooks contract 1.
local hooks=dofile(page.hooks)
assert(hooks.contract==1 and type(hooks.manifest)=='function'
    and type(hooks.load)=='function' and type(hooks.apply)=='function')
assert(hooks.manifest({page=page.id,directory=page.configDirectory}):find('[Setting.MCC_Page]',1,true))
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
