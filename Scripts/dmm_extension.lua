-- DMM loads provider extensions through this entrypoint.
local source=debug.getinfo(1,'S').source:gsub('^@','')
local scripts=assert(source:match('^(.*)[/\\][^/\\]+$'))
package.path=scripts .. '/?.lua;' .. package.path
return {
    id='ModCoreControls', apiVersion=1,
    install=function(dmm)
        -- Generate choices before each menu build. DMM installs extensions in
        -- path order, so ModCoreSettings' wrapper is inner: MCC's page and its
        -- row slot exist when ModCoreSettings decides on slots and links.
        local build=dmm.pages.build
        dmm.pages.build=function(tree,providers,...)
            local page=require('mc_dmm')
            page.installStorage(dmm.choices)
            page.populate(dmm.choices,providers)
            return build(tree,providers,...)
        end
    end,
}
