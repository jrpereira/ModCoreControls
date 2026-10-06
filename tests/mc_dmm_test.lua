package.path='Scripts/?.lua;' .. package.path
-- os.tmpname always uses /tmp; honour TMPDIR so the suite runs in sandboxes too.
local function tmpname()
    local dir=os.getenv('TMPDIR')
    if not dir then return os.tmpname() end
    local path=dir:gsub('/+$','') .. '/mcc_' .. os.time() .. '_' .. math.random(1000000000)
    assert(io.open(path,'wb')):close()
    return path
end
-- Needs the real DMM parser and ModCoreSettings sources, which CI does not have; skip without them.
local path,settings=os.getenv('DMM_CHOICES_PATH'),os.getenv('MCS_SCRIPTS_PATH')
if not path or not settings then
    print('SKIP DMM integration: set DMM_CHOICES_PATH and MCS_SCRIPTS_PATH');return
end
local choices=dofile(path)
-- The same wrappers, in the same order, as ModCoreSettings' DMM extension.
local fieldTypes=dofile(settings .. '/field_types.lua').new()
fieldTypes:register('keybind',dofile(settings .. '/keybind_editor.lua'))
fieldTypes:install({choices=choices,controls={build=function() end}})
dofile(settings .. '/navigation.lua').install(choices)
dofile(settings .. '/presentation.lua').install(choices,{},nil)
dofile(settings .. '/init_config.lua').install(choices)
local PageHooks=dofile(settings .. '/page_hooks.lua')
PageHooks.install(choices)
local Menu,Config,DMM=require('mc_menu'),require('mc_config'),require('mc_dmm')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
local function same(actual,expected,label)
    assert(#actual==#expected,label .. ' count')
    for i,value in ipairs(expected) do assert(actual[i]==value,label .. ' value ' .. i) end
end
local temp=tmpname(); assert(os.remove(temp)); assert(os.execute('mkdir ' .. string.format('%q',temp)))
-- ModCoreSettings loads the hooks file once and builds the page provider from it.
-- Tests run from the module folder; the hooks path must be absolute.
local scripts=assert(io.popen('pwd')):read('l') .. '/Scripts'
local hooks=PageHooks.loader()(scripts .. '/mcs_page.lua')
local context=PageHooks.context({id='ModCoreControls',configDirectory=temp})
local manifest=PageHooks.manifest(hooks,context)
assert(manifest:find('mcSlot=visuals',1,true),'ModCoreSettings reads row slots from the manifest text')
local items=choices.parse(manifest)
local provider={id='ModCoreControls',name='Controls',testOnly=false,choices=items,
    settingsCount=#items,choicesLoaded=true,deferred=false,path=temp .. '/mod_settings.ini',
    mcManifest=manifest,mcHooks=hooks,mcHookContext=context}
-- The published page names this hooks file and the mod folder as its config directory.
local Contributions=require('menu_contributions')
assert(Contributions.validate('ModCoreControls',{pages={{id=DMM.page.id,name=DMM.page.name,
    attach='2_ModCore_Controls',hooks=scripts .. '/mcs_page.lua',configDirectory=temp}}}))
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
    if setting.kind=='keybind' or #setting.values>1 then
        editable=editable+1
        local index=assert(indices[setting.id],'missing DMM row: ' .. setting.id)
        local item=items[index]
        assert(item.default==setting.default,'default mismatch: ' .. setting.id)
        assert(item.file=='config.ini','config file mismatch: ' .. setting.id)
        assert(item.section==setting.configSection,'config section mismatch: ' .. setting.id)
        assert(item.key==setting.configKey,'config key mismatch: ' .. setting.id)
        if setting.kind=='choice' then
            same(item.values,setting.values,setting.id .. ' values')
            assert(not item.mcTabs,'no mode pickers render as tabs: ' .. setting.id)
            same(item.labels,setting.labels,setting.id .. ' labels')
        else
            -- One ModCoreSettings keybind row holds the key and its trigger.
            assert(item.kind=='extension' and item.editor=='keybind','keybind row missing: ' .. setting.id)
            same(item.triggers,setting.labels,setting.id .. ' triggers')
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
local slotRow=DMM.schema(definition):match('%[Setting%.MCC_Visuals_Pending%][^%[]*')
assert(slotRow and slotRow:find('mcSlot=visuals',1,true) and slotRow:find('mcSlotLabel=1',1,true)
    and slotRow:find('Label=Quickslots Visuals',1,true) and slotRow:find('mcCategory=1',1,true)
    and not slotRow:find('mcLevel',1,true),
    'the Visuals placeholder is the labelled ModCoreSettings row slot')
assert(DMM.schema(definition):match('%[Category%.Visuals%][^%[]*mcHeading=0'),
    'the template picker row replaces the Visuals heading')
assert(items[indices.MCC_Visuals_Pending].label=='Quickslots Visuals')
local map=indices.MCC_actions_Map
assert(items[map].mcFont==nil and not items[map].mcTabs,
    'Control Map must use DMM arrows without a presentation level')
local wheel=indices.MCC_module_default_DefaultWheel
local slot=indices.MCC_actions_global_AbilitySlot1
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
model:set(slot,'J|Hold')
local ok,why,event=model:apply(); assert(ok,why)
assert(not event.values.MCC_Section and not event.values.MCC_Page and not event.values.MCC_actions_Map)
local file=assert(io.open(temp .. '/config.ini','rb')); local saved=file:read('*a'); file:close()
assert(not saved:find('map=',1,true))
assert(saved:find('global.AbilitySlot1=J|Hold',1,true))
assert(saved:find('[ModCoreControls.module]',1,true))
local conflict=indices.MCC_actions_global_AbilitySlot2
model:set(conflict,'J|Hold')
local accepted,reason,failedEvent=model:apply()
assert(not accepted and reason:find('Key J (Hold) is bound to both "Ability Slot 1" and "Ability Slot 2"',1,true),reason)
assert(failedEvent==nil and model.pending[conflict]=='J|Hold' and model.committed[conflict]=='none')
file=assert(io.open(temp .. '/config.ini','rb'))
assert(file:read('*a')==saved,'invalid Apply changed persisted config')
file:close()
local native=Menu.new(definition,Config.decode(saved,definition))
assert(native.values.MCC_actions_global_AbilitySlot1=='J|Hold')
model=choices.open(provider)
assert(not model.error,model.error)
assert(model.pending[slot]=='J|Hold')
-- Live gamepad assignments become one read-only row per button.
local schema=DMM.schema(definition,{{key='Gamepad_DPad_Left',label='D-Pad Left',actions={'Quickslot Left','Map|Zoom'}},
    {key='Gamepad_DPad_Up',label='D-Pad Up',actions={}}})
assert(schema:find('[Setting.MCC_Pad_Gamepad_DPad_Left]',1,true)
    and schema:find('PresetLabels=Quickslot Left, Map Zoom|Quickslot Left, Map Zoom',1,true)
    and schema:find('PresetLabels=Unassigned|Unassigned',1,true)
    and not schema:find('MCC_Pad_Unavailable',1,true))
assert(os.remove(temp .. '/config.ini')); assert(os.execute('rmdir ' .. string.format('%q',temp)))
print('PASS DMM matches MCC definitions, storage, and page navigation')
