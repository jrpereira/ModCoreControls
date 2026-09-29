-- DMM loads provider extensions through this entrypoint.
local source=debug.getinfo(1,'S').source:gsub('^@','')
local scripts=assert(source:match('^(.*)[/\\][^/\\]+$'))
package.path=scripts .. '/?.lua;' .. package.path
return {
    id='ModCoreControls', apiVersion=1,
    install=function(dmm)
        -- Generate choices when controls are built, after ModCoreSettings has
        -- installed its parsers and configuration initializers.
        local build=dmm.controls.build
        dmm.controls.build=function(tree,providers,...)
            local page=require('mc_dmm')
            page.installStorage(dmm.choices)
            page.populate(dmm.choices,providers)
            return build(tree,providers,...)
        end
    end,
}
