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
