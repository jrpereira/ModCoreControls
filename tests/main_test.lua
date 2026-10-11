package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
assert(loadfile('Scripts/main.lua'))()
-- MCC's Lua state is its own: it exports no global API.
assert(rawget(_G,'ModCoreControls')==nil,'MCC sets no global')
local sections=require('mc_sections')
local maps=require('mc_maps')
local beforeSections,beforeMaps=#sections.order,#maps.order.actions
assert(not pcall(sections.addSection,'late','Late controls'))
assert(not pcall(maps.addSectionMap,'actions',
    {id='late',name='Late',value=9,contexts={'exploration'},map={}}))
assert(#sections.order==beforeSections and #maps.order.actions==beforeMaps)

print('PASS MCC entry point rejects registrations after its definition is frozen')
