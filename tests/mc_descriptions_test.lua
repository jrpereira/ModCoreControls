package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
-- Declared descriptions pass through to DMM: settings and keys as the row's
-- Description, groups and sections as help text under a heading.
for _,name in ipairs({'mc_maps','mc_sections','mc_menu'}) do package.loaded[name]=nil end
local sections,maps=require('mc_sections'),require('mc_maps')
sections.sections.actions.description='Keys that use your quickslots.'
local grouped=maps.maps.actions.grouped
grouped.map[1].description='Fire the focused wheel.'
grouped.map[2].description='Swap between wheels.'
-- ; and | are ordinary text in a description.
grouped.map[2].settings[2].description='The wheel shown at rest; Abilities | Consumables.'
local Menu=require('mc_menu')
local definition=Menu.define(sections,maps)
local schema=require('mc_dmm').schema(definition)
local function section(name)
    return assert(schema:match('%['..name:gsub('%p','%%%0')..'%]\n(.-)\n\n'),'missing section '..name)
end
-- The section's description leads its first heading; that group's own text follows.
assert(section('Category.actions.grouped.1'):find('mcHelp=Keys that use your quickslots. Fire the focused wheel.\n',1,true))
assert(section('Category.actions.grouped.2'):find('mcHelp=Swap between wheels.\n',1,true))
-- Every map page of the section starts with it, once.
assert(section('Category.actions.global.1'):find('mcHelp=Keys that use your quickslots.',1,true))
assert(not section('Category.actions.global.2'):find('mcHelp',1,true))
-- Keys and mirrors carry their own Description.
assert(section('Setting.MCC_actions_grouped_DefaultGroup')
    :find('Description=The wheel shown at rest; Abilities | Consumables.\n',1,true))
assert(section('Setting.MCC_actions_grouped_GroupFocus2'):find('Description=Tap swaps',1,true))
-- Group activation keys show Tap as Toggle; the stored trigger names stay Hold and Tap.
for _,id in ipairs({'GroupFocus2','ActivateAbilities','ActivateConsumables'}) do
    local row=section('Setting.MCC_actions_grouped_'..id)
    assert(row:find('\nTriggers=Hold|Tap\n',1,true) and row:find('\nTriggerLabels=Hold|Toggle\n',1,true),id)
end
assert(not section('Setting.MCC_actions_global_AbilitySlot1'):find('TriggerLabels',1,true),
    'slot keys keep Tap')
-- Empty descriptions add nothing; line breaks, control characters and over-long text,
-- which DMM cannot read, are rejected.
assert(not section('Category.module.default.settings'):find('mcHelp',1,true))
assert(Menu.description('',"x")==nil and Menu.description('a; b | c','x')=='a; b | c')
assert(not pcall(Menu.description,'line\nbreak','x') and not pcall(Menu.description,'tab\there','x')
    and not pcall(Menu.description,('x'):rep(4097),'x'))
-- With DMM available, the real parser and ModCoreSettings' presentation read them.
local choicesPath,settings=os.getenv('DMM_CHOICES_PATH'),os.getenv('MCS_SCRIPTS_PATH')
if choicesPath and settings then
    -- ModCoreSettings' files require their siblings; MCC's own modules still win.
    package.path=package.path..';'..settings..'/?.lua'
    local choices=dofile(choicesPath)
    local fieldTypes=dofile(settings .. '/field_types.lua').new()
    fieldTypes:register('keybind',dofile(settings .. '/keybind_editor.lua'))
    fieldTypes:install({choices=choices,controls={build=function() end}})
    dofile(settings .. '/navigation.lua').install(choices)
    dofile(settings .. '/presentation.lua').install(choices,{},nil)
    local byId={}
    for _,item in ipairs(choices.parse(schema)) do byId[item.id]=item end
    local slot=assert(byId.MCC_actions_grouped_QuickSlot1)
    assert(slot.mcGroup and slot.mcGroup.help=='Keys that use your quickslots. Fire the focused wheel.')
    assert(byId.MCC_actions_grouped_DefaultGroup.description=='The wheel shown at rest; Abilities | Consumables.')
end
print('PASS declared descriptions pass through to DMM')
