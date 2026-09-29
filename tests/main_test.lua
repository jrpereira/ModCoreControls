assert(loadfile('Scripts/main.lua'))()
assert(type(ModCoreControls) == 'table')
assert(type(ModCoreControls.addSection) == 'function')
assert(type(ModCoreControls.addSectionMap) == 'function')
assert(ModCoreControls.openMenu == nil and ModCoreControls.closeMenu == nil)
assert(ModCoreControls.new == nil and ModCoreControls.quickslotHost == nil)
local sections=require('mc_sections')
local maps=require('mc_maps')
local beforeSections,beforeMaps=#sections.order,#maps.order.actions
assert(not pcall(ModCoreControls.addSection,'late','Late controls'))
assert(not pcall(ModCoreControls.addSectionMap,'actions',
    {id='late',name='Late',value=9,contexts={'exploration'},map={}}))
assert(#sections.order==beforeSections and #maps.order.actions==beforeMaps)

print('PASS MCC entry point rejects registrations after its definition is frozen')
