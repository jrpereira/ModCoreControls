package.path='Scripts/?.lua;' .. package.path
local path=assert(os.getenv('DMM_CHOICES_PATH'),'set DMM_CHOICES_PATH to the current DMM choices.lua')
local settings=assert(os.getenv('MCS_SCRIPTS_PATH'),'set MCS_SCRIPTS_PATH to ModCoreSettings/Scripts')
local choices=dofile(path)
dofile(settings .. '/navigation.lua').install(choices)
dofile(settings .. '/presentation.lua').install(choices,{},nil)
dofile(settings .. '/init_config.lua').install(choices)
local Menu,Config,DMM=require('mc_menu'),require('mc_config'),require('mc_dmm')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
DMM.installStorage(choices)
local function same(actual,expected,label)
    assert(#actual==#expected,label .. ' count')
    for i,value in ipairs(expected) do assert(actual[i]==value,label .. ' value ' .. i) end
end
local temp=os.tmpname(); assert(os.remove(temp)); assert(os.execute('mkdir ' .. string.format('%q',temp)))
local provider={id='ModCoreControls',path=temp .. '/mod_settings.ini',choices={},deferred=true,choicesLoaded=false}
DMM.populate(choices,{provider})
local items=provider.choices
assert(not provider.choiceError and not provider.deferred and provider.choicesLoaded)
assert(provider.mcManifest and provider.mcManifest:find('mcSlot=visuals',1,true),
    'ModCoreSettings reads row slots from the published manifest text')
-- The extension generates the page before ModCoreSettings' inner pages.build.
local extension=dofile('Scripts/dmm_extension.lua')
local seen
local fake={choices=choices,controls={build=function() end},
    pages={build=function(_,providers) seen=providers[1].mcManifest end}}
extension.install(fake)
fake.pages.build({},{{id='ModCoreControls',path=temp .. '/mod_settings.ini',choices={}}})
assert(seen and seen:find('mcSlot=visuals',1,true),'page must exist before the inner pages.build')
assert(provider.settingsCount==#items)
local model=choices.open(provider)
assert(not model.error,model.error)
local indices={}
for i,item in ipairs(items) do indices[item.id]=i end
local page=indices.MCC_Page
assert(page==1,'Page must be the first DMM control')
assert(items[page].mcNavigation and items[page].mcHeader and items[page].mcFont==nil,
    'Page must be transient navigation presented as a heading')
same(items[page].labels,{'Options','Visuals','Key & Mouse','Controller'},'page picker labels')
local nav=assert(indices.MCC_Section)
assert(items[nav].mcNavigation,'Section is navigation')
local keyed={}
for _,section in ipairs(definition.sections) do
    if section.id~='module' then keyed[#keyed+1]=section.name end
end
same(items[nav].labels,keyed,'section picker labels')
local editable=0
for _,setting in ipairs(definition.settings) do
    if setting.kind=='key' or #setting.values>1 then
        editable=editable+1
        local index=assert(indices[setting.id],'missing DMM row: ' .. setting.id)
        local item=items[index]
        assert(item.default==setting.default,'default mismatch: ' .. setting.id)
        assert(item.file=='config.ini','config file mismatch: ' .. setting.id)
        assert(item.section==setting.configSection,'config section mismatch: ' .. setting.id)
        assert(item.key==setting.configKey,'config key mismatch: ' .. setting.id)
        if setting.kind=='choice' then
            same(item.values,setting.values,setting.id .. ' values')
            assert((item.mcTabs==true)==(item.mcPairTargetId~=nil),
                'only paired mode pickers should render as tabs: ' .. setting.id)
            same(item.labels,setting.labels,setting.id .. ' labels')
        else
            assert(item.mcKeybind,'key capture missing: ' .. setting.id)
        end
    else
        assert(not indices[setting.id],'fixed trigger should not create a picker: ' .. setting.id)
    end
end
-- Extra rows: Page, Section, Control Map, the Default Group mirror, Visuals'
-- placeholder, and Controller's unavailable and note rows.
assert(#items==editable+7,'DMM row count does not match editable MCC settings')
for _,id in ipairs({'MCC_Visuals_Pending','MCC_Pad_Unavailable','MCC_Pad_Note'}) do
    local item=items[assert(indices[id],id)]
    assert(item.mcReadOnly and #item.values==1,'read-only display row: ' .. id)
end
assert(DMM.schema(definition):find('[Setting.MCC_Visuals_Pending]',1,true)
    and DMM.schema(definition):match('%[Setting%.MCC_Visuals_Pending%][^%[]*mcSlot=visuals'),
    'the Visuals placeholder is the ModCoreSettings row slot')
local map=indices.MCC_actions_Map
assert(items[map].mcFont==nil and not items[map].mcTabs,
    'Control Map must use DMM arrows without a presentation level')
local wheel=indices.MCC_module_default_DefaultWheel
local slot=indices.MCC_actions_global_SlotAction1_Key
local function shown(i) return model:visibility()[i] end
-- Options shows the Module section only.
assert(shown(wheel) and not shown(nav) and not shown(map) and not shown(slot))
model:set(page,1)
assert(shown(indices.MCC_Visuals_Pending) and not shown(wheel) and not shown(nav))
model:set(page,3)
assert(shown(indices.MCC_Pad_Note) and not shown(indices.MCC_Visuals_Pending))
-- Key & Mouse nests Section, then Control Map, then the map's keys.
model:set(page,2)
assert(shown(nav) and shown(map) and not shown(wheel) and not model:dirty())
model:set(nav,1)
assert(not shown(map) and not shown(slot),'Movement hides Actions')
model:set(nav,0); model:set(map,2)
assert(shown(slot))
model:set(slot,74)
local ok,why,event=model:apply(); assert(ok,why)
assert(not event.values.MCC_Section and not event.values.MCC_Page and not event.values.MCC_actions_Map)
local file=assert(io.open(temp .. '/config.ini','rb')); local saved=file:read('*a'); file:close()
assert(not saved:find('map=',1,true))
assert(saved:find('global.SlotAction1.key=74',1,true))
assert(saved:find('[ModCoreControls.module]',1,true))
local conflict=indices.MCC_actions_global_SlotAction2_Key
model:set(conflict,74)
local accepted,reason,failedEvent=model:apply()
assert(not accepted and reason:find('MCC_actions_global_SlotAction2_Key',1,true))
assert(failedEvent==nil and model.pending[conflict]==74 and model.committed[conflict]~=74)
file=assert(io.open(temp .. '/config.ini','rb'))
assert(file:read('*a')==saved,'invalid Apply changed persisted config')
file:close()
local native=Menu.new(definition,Config.decode(saved,definition))
assert(native.values.MCC_actions_global_SlotAction1_Key==74)
model=choices.open(provider)
assert(not model.error,model.error)
assert(model.pending[slot]==74)
-- Live gamepad assignments become one read-only row per button.
local schema=DMM.schema(definition,{{key='Gamepad_DPad_Left',label='D-Pad Left',actions={'Quickslot Left','Map|Zoom'}},
    {key='Gamepad_DPad_Up',label='D-Pad Up',actions={}}})
assert(schema:find('[Setting.MCC_Pad_Gamepad_DPad_Left]',1,true)
    and schema:find('PresetLabels=Quickslot Left, Map Zoom|Quickslot Left, Map Zoom',1,true)
    and schema:find('PresetLabels=Unassigned|Unassigned',1,true)
    and not schema:find('MCC_Pad_Unavailable',1,true))
assert(os.remove(temp .. '/config.ini')); assert(os.execute('rmdir ' .. string.format('%q',temp)))
print('PASS DMM matches MCC definitions, storage, and page navigation')
