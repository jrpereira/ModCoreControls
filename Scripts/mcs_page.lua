-- ModCoreSettings loads this in its menu state to build and store the Controls page.
local Page=require('mc_dmm')
return {
    contract=1,
    manifest=function() return Page.manifest() end,
    load=function(context) return Page.load(context.directory) end,
    apply=function(context,values,changes) return Page.apply(context.directory,values,changes) end,
}
