-- ModCoreSettings loads this in its menu state to build and store the Controls pages:
-- the main page and its inner pages, told apart by context.page.
local Page=require('mc_dmm')
return {
    contract=1,
    manifest=function(context) return Page.manifest(context.page) end,
    load=function(context) return Page.load(context.directory,context.page) end,
    apply=function(context,values,changes) return Page.apply(context.directory,values,changes,context.page) end,
}
