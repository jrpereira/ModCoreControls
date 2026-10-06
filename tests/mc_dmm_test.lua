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
-- ModCoreSettings' files require their siblings; MCC's own modules still win.
package.path=package.path..';'..settings..'/?.lua'
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
-- Only sections with maps get a page; with a single one there is no Section picker.
local keyed={}
for _,section in ipairs(definition.sections) do
    if section.id~='module' and #section.maps>0 then keyed[#keyed+1]=section.name end
end
local nav=indices.MCC_Section
if #keyed>1 then
    assert(nav and items[nav].mcNavigation,'Section is navigation')
    same(items[nav].labels,keyed,'section picker labels')
else
    assert(nav==nil,'a single keyed section needs no Section picker')
end
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
-- Extra rows: Page, Section (with several keyed sections), Control Map, the Default
-- Group mirror, Visuals' placeholder, and Controller's unavailable and note rows.
assert(#items==editable+6+(nav and 1 or 0),'DMM row count does not match editable MCC settings')
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
assert(shown(wheel) and not shown(map) and not shown(slot))
model:set(page,1)
assert(shown(indices.MCC_Visuals_Pending) and not shown(wheel) and not shown(map))
model:set(page,3)
assert(shown(indices.MCC_Pad_Note) and not shown(indices.MCC_Visuals_Pending))
-- Key & Mouse shows the Control Map, then the map's keys; empty placeholder
-- sections such as Movement and System add no page.
model:set(page,2)
assert(shown(map) and not shown(wheel) and not model:dirty())
for _,item in ipairs(items) do
    assert(not tostring(item.label):find('Movement',1,true) and not tostring(item.label):find('System',1,true),
        'placeholder sections must not appear: '..tostring(item.label))
end
model:set(map,2)
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
-- Through ModCoreSettings' conflict scope, the same key and trigger on two rows is
-- marked while editing; on different Control Map pages the map picker is marked too.
if type(fieldTypes.conflicts)=='function' then
    local quickslot=assert(indices.MCC_actions_grouped_QuickSlot1)
    local otherSlot=assert(indices.MCC_actions_global_AbilitySlot2)
    assert(items[slot].conflictScope=='controls','the real parser reads the controls scope')
    local rows,pickers=fieldTypes.conflicts(model)
    assert(next(rows)==nil and next(pickers)==nil,'saved controls start without collisions')
    -- Different maps: both rows and the Control Map picker.
    model:set(quickslot,'J|Hold')
    rows,pickers=fieldTypes.conflicts(model)
    assert(rows[quickslot] and rows[slot] and pickers[map],'a cross-map pair marks both rows and the map picker')
    assert(not pickers[page],'the Page picker does not separate the pair')
    -- Another trigger is a different binding.
    model:set(quickslot,'J|Tap')
    rows,pickers=fieldTypes.conflicts(model)
    assert(next(rows)==nil and next(pickers)==nil,'Tap and Hold on one key do not collide')
    -- Same map: the rows only.
    model:set(quickslot,'none');model:set(otherSlot,'J|Hold')
    rows,pickers=fieldTypes.conflicts(model)
    assert(rows[otherSlot] and rows[slot] and not pickers[map],'a same-map pair marks only the rows')
    model:set(otherSlot,'none')
    rows=fieldTypes.conflicts(model)
    assert(next(rows)==nil,'clearing the key clears the collision')
    print('PASS ModCoreSettings marks colliding Controls keys and their map picker')
else
    print('SKIP collision marking: this ModCoreSettings has no conflict scopes')
end
assert(os.remove(temp .. '/config.ini')); assert(os.execute('rmdir ' .. string.format('%q',temp)))
print('PASS DMM matches MCC definitions, storage, and page navigation')

-- Once a second section has maps, the Section picker returns and gates each section.
do
    local extended={}
    for key,value in pairs(definition) do extended[key]=value end
    extended.sections={}
    local actions
    for _,section in ipairs(definition.sections) do
        if section.id=='actions' then actions=section end
    end
    for _,section in ipairs(definition.sections) do
        if section.id=='movement' then
            local copy={}
            for key,value in pairs(actions) do copy[key]=value end
            copy.id,copy.name='movement','Movement'
            copy.selector={id='MCC_movement_Map',name='Control Map',values=actions.selector.values,
                labels=actions.selector.labels,default=actions.selector.default}
            section=copy
        end
        extended.sections[#extended.sections+1]=section
    end
    local text=DMM.schema(extended)
    local picker=assert(text:match('%[Setting%.MCC_Section%][^%[]*'),'Section picker returns')
    assert(picker:find('PresetLabels=Actions|Movement',1,true),picker)
    assert(text:match('%[Setting%.MCC_movement_Map%][^%[]*VisibleWhen=MCC_Section'),
        'each section is gated by the Section picker')
end
print('PASS the Section picker lists only sections with maps')
