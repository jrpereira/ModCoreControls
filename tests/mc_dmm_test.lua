package.path='Scripts/?.lua;Scripts/vendor/?.lua;' .. package.path
-- os.tmpname always uses /tmp; honour TMPDIR so the suite runs in sandboxes too.
local function tmpname()
    local dir=os.getenv('TMPDIR')
    if not dir then return os.tmpname() end
    local path=dir:gsub('/+$','') .. '/mcc_' .. os.time() .. '_' .. math.random(1000000000)
    assert(io.open(path,'wb')):close()
    return path
end
-- Needs the real DMM parser and ModCoreSettings sources, which CI does not have; skip without them.
-- It is a local pre-release check instead: see "Before a release" in docs/BUILD.md.
local path,settings=os.getenv('DMM_CHOICES_PATH'),os.getenv('MCS_SCRIPTS_PATH')
if not path or not settings then
    print('SKIP DMM integration: set DMM_CHOICES_PATH and MCS_SCRIPTS_PATH;'
        ..' required before a release (docs/BUILD.md, "Before a release")');return
end
-- ModCoreSettings' files require their siblings; MCC's own modules still win.
package.path=package.path..';'..settings..'/?.lua'
local choices=dofile(path)
-- The same wrappers, in the same order, as ModCoreSettings' DMM extension.
local fieldTypes=dofile(settings .. '/field_types.lua').new()
fieldTypes:register('keybind',dofile(settings .. '/keybind_editor.lua'))
fieldTypes:register('range',dofile(settings .. '/range_editor.lua'))
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
local function config()
    local file=io.open(temp .. '/config.ini','rb')
    if not file then return nil end
    local text=file:read('*a');file:close();return text
end
-- ModCoreSettings loads the hooks file once and builds each page's provider from it.
-- Tests run from the module folder; the hooks path must be absolute.
local scripts=assert(io.popen('pwd')):read('l') .. '/Scripts'
local hooks=PageHooks.loader()(scripts .. '/mcs_page.lua')
local inner=DMM.pages(definition)
local ids={DMM.page.id}
for _,entry in ipairs(inner) do ids[#ids+1]=entry.id end
same(ids,{'ModCoreControls','ModCoreControls.mappings'},'page ids')
local pages={}
for _,id in ipairs(ids) do
    local context=PageHooks.context({id=id,configDirectory=temp})
    local manifest=PageHooks.manifest(hooks,context)
    local items=choices.parse(manifest)
    local indices={}
    for i,item in ipairs(items) do indices[item.id]=i end
    pages[id]={manifest=manifest,items=items,indices=indices,provider={id=id,name=id,testOnly=false,choices=items,
        settingsCount=#items,choicesLoaded=true,deferred=false,path=temp .. '/mod_settings.ini',
        mcManifest=manifest,mcHooks=hooks,mcHookContext=context}}
    for _,gone in ipairs({'MCC_Page','MCC_Section','MCC_actions_Map'}) do
        assert(not manifest:find(gone,1,true),'no page or map pickers: '..gone..' on '..id)
    end
end
local main,mappings=pages.ModCoreControls,pages['ModCoreControls.mappings']
-- Each Mappings link opens the page at its tab's first row.
local anchors={'MCC_actions_grouped_QuickSlot1','MCC_actions_global_AbilitySlot1','MCC_Pad_Note'}
assert(main.manifest:find('mcSlot=visuals',1,true),'ModCoreSettings reads row slots from the manifest text')
-- The published pages name this hooks file and the mod folder as their config directory.
local Contributions=require('menu_contributions')
local published={{id=DMM.page.id,name=DMM.page.name,visible=false,hooks=scripts .. '/mcs_page.lua',
    configDirectory=temp}}
for _,entry in ipairs(inner) do
    published[#published+1]={id=entry.id,name=entry.name,description=entry.description,under=DMM.page.id,
        group='inner',hooks=scripts .. '/mcs_page.lua',configDirectory=temp}
end
assert(Contributions.validate('ModCoreControls',{pages=published}))

-- The main page: the Visuals slot, the Mappings links, then Behaviours.
do
    local order={}
    for i=1,4 do order[i]=main.items[i].id end
    same(order,{'MCC_Visuals_Pending','MCC_Link_grouped','MCC_Link_global','MCC_Link_controller'},'main page order')
    assert(main.items[5].id=='MCC_module_default_SwapOutsideCombat','Behaviours follows the links')
    local labels={}
    for i=2,4 do
        local link=main.items[i]
        assert(link.mcNavigation and link.mcLinkPage=='ModCoreControls.mappings#'..anchors[i-1] and link.mcTabs and #link.labels==2
            and link.labels[1]=='edit' and link.labels[2]=='edit' and link.group=='Mappings',link.id..' is an edit link')
        labels[#labels+1]=link.label
    end
    same(labels,{'Group Keys','Global Keys','Controller'},'link labels')
    local slot=main.items[1]
    assert(slot.mcReadOnly and #slot.values==1 and slot.label=='Quickslots')
end
-- Every MCC setting is on exactly one page with its storage unchanged; the mirror is on Mappings.
local editable=0
for _,setting in ipairs(definition.settings) do
    local found
    for _,id in ipairs(ids) do
        local index=pages[id].indices[setting.id]
        if index then assert(not found,'on two pages: '..setting.id);found={pages[id],index} end
    end
    if setting.kind=='keybind' or setting.kind=='range' or #setting.values>1 then
        editable=editable+1
        assert(found,'missing DMM row: ' .. setting.id)
        local item=found[1].items[found[2]]
        assert(item.default==setting.default,'default mismatch: ' .. setting.id)
        assert(item.file=='config.ini','config file mismatch: ' .. setting.id)
        assert(item.section==setting.configSection,'config section mismatch: ' .. setting.id)
        assert(item.key==setting.configKey,'config key mismatch: ' .. setting.id)
        if setting.kind=='range' then
            assert(item.kind=='extension' and item.editor=='range','range row: '..setting.id)
        elseif setting.kind=='choice' then
            same(item.values,setting.values,setting.id .. ' values')
            assert(not item.mcTabs,'no mode pickers render as tabs: ' .. setting.id)
            same(item.labels,setting.labels,setting.id .. ' labels')
        else
            -- One ModCoreSettings keybind row holds the key and its trigger.
            assert(item.kind=='extension' and item.editor=='keybind','keybind row missing: ' .. setting.id)
            same(item.triggers,setting.labels,setting.id .. ' triggers')
        end
    else
        assert(not found,'fixed trigger should not create a picker: ' .. setting.id)
    end
end
-- Extra rows: the slot and three links on the main page; on Mappings the tab picker, the
-- Default Group mirror, and Controller's unavailable and note rows.
assert(#main.items+#mappings.items==editable+8,'DMM row count does not match editable MCC settings')
assert(mappings.indices.MCC_actions_grouped_DefaultGroup)
for _,id in ipairs({'MCC_Pad_Unavailable','MCC_Pad_Note'}) do
    local item=mappings.items[assert(mappings.indices[id],id)]
    assert(item.mcReadOnly and #item.values==1,'read-only display row: ' .. id)
end
-- The Mappings page's title row is its tab picker, Group Keys | Global Keys | Controller:
-- navigation, never stored. Each tab shows its own rows; every row is on one tab.
do
    local tabs=mappings.items[1]
    assert(tabs.id=='MCC_Mappings_Tab' and tabs.mcNavigation and tabs.mcHeading
        and table.concat(tabs.labels,'|')=='Group Keys|Global Keys|Controller'
        and table.concat(tabs.values,'|')=='0|1|2' and tabs.default==0,'the title row is the tab picker')
    local model=choices.open(mappings.provider)
    assert(not model.error,model.error)
    assert(model.pending[1]==0,'the page opens on Group Keys')
    local seen={}
    local prefixes={'^MCC_actions_grouped_','^MCC_actions_global_','^MCC_Pad_'}
    for tab=0,2 do
        model:set(1,tab)
        assert(not model:dirty(),'tabs are navigation')
        local visible=model:visibility()
        assert(visible[1],'the tab picker always shows')
        local count=0
        for i=2,#mappings.items do
            if visible[i] then
                local id=mappings.items[i].id
                assert(id:find(prefixes[tab+1]) and not seen[id],id..' on tab '..tab)
                seen[id]=true;count=count+1
            end
        end
        assert(count>0,'tab '..tab..' has rows')
        if tab==2 then assert(count==2,'Controller: the note and the unavailable row') end
    end
    for i=2,#mappings.items do assert(seen[mappings.items[i].id],mappings.items[i].id..' is on a tab') end
    assert(mappings.items[2].id==anchors[1],'Group Keys starts the page')
end
-- Behaviours heads two subgroups, Quickslot Wheels and Shortcuts, each holding its block
-- of the main page's settings in order.
do
    local schema=main.manifest
    local function block(label)
        local id,body=schema:match('%[Category%.(module%.default%.settings[%.%d]*)%]([^%[]*mcLabel='..label..'\n[^%[]*)')
        assert(id,label..' heading')
        assert(body:find('mcWithin=module.default.within\n',1,true)
            and body:find('mcWithinLabel=Behaviours\n',1,true),label..' sits under Behaviours')
        local order={}
        for setting,group in schema:gmatch('%[Setting%.([%w_]+)%][^%[]-Group=([%w%._]+)') do
            if group==id then order[#order+1]=setting end
        end
        return table.concat(order,',')
    end
    local wheels=block('Quickslot Wheels')
    assert(wheels=='MCC_module_default_SwapOutsideCombat,MCC_module_default_HoldSwap,'
        ..'MCC_module_default_DefaultWheel',wheels)
    local shortcuts=block('Shortcuts')
    assert(shortcuts=='MCC_module_default_InstantTap,MCC_module_default_HoldThreshold,'
        ..'MCC_module_default_KeyOutline',shortcuts)
    assert(not schema:find('[Category.module.default.within]',1,true),'Behaviours has no rows of its own')
    -- ModCoreSettings draws one Behaviours heading over both subgroups.
    local parents={}
    for _,item in ipairs(main.items) do
        local group=item.mcGroup
        if item.group:match('^module%.default%.settings') then
            assert(group and group.within=='module.default.within' and group.parent
                and group.parent.label=='Behaviours' and group.parent.category,item.id..' under Behaviours')
            parents[group.parent]=true
        end
    end
    assert(next(parents) and next(parents,next(parents))==nil,'one shared Behaviours heading')
end
local slotRow=main.manifest:match('%[Setting%.MCC_Visuals_Pending%][^%[]*')
assert(slotRow and slotRow:find('mcSlot=visuals',1,true) and not slotRow:find('mcSlotLabel',1,true)
    and slotRow:find('Label=Quickslots\n',1,true) and slotRow:find('mcCategory=1',1,true)
    and slotRow:find('mcSlotGroups=1',1,true) and not slotRow:find('VisibleWhen',1,true)
    and not slotRow:find('mcLevel',1,true),
    'the Visuals placeholder is the labelled ModCoreSettings row slot')
assert(main.manifest:match('%[Category%.Visuals%][^%[]*mcHeading=0'),
    'the template picker row replaces the Visuals heading')
-- The tabs head their groups by name; each group shows on its tab only.
assert(mappings.manifest:find('[Category.actions.grouped.1]\nVisibleValues=0\nVisibleWhen=MCC_Mappings_Tab\nmcLabel=Active Group\n',1,true)
    and mappings.manifest:find('[Category.actions.global.2]\nVisibleValues=1\nVisibleWhen=MCC_Mappings_Tab\nmcLabel=Consumables\n',1,true)
    and mappings.manifest:find('[Category.Controller]\nVisibleValues=2\nVisibleWhen=MCC_Mappings_Tab\n',1,true))
-- A group activation key's Tap stays on its wheel, so it reads Toggle; values keep Tap.
local focusRow=mappings.manifest:match('%[Setting%.MCC_actions_grouped_ActivateAbilities%][^%[]*')
assert(focusRow and focusRow:find('Triggers=Hold|Tap',1,true)
    and focusRow:find('TriggerLabels=Hold|Toggle',1,true),'activation keys label Tap as Toggle')
local slotKey=mappings.manifest:match('%[Setting%.MCC_actions_grouped_QuickSlot1%][^%[]*')
assert(slotKey and not slotKey:find('TriggerLabels',1,true),'other keys keep the trigger names')

-- Apply on the Mappings page saves its keys; settings on the main page keep their values.
local slot=mappings.indices.MCC_actions_global_AbilitySlot1
local model=choices.open(mappings.provider)
assert(not model.error,model.error)
model:set(slot,'J|Hold')
local ok,why,event=model:apply(); assert(ok,why)
assert(event.values.MCC_actions_global_AbilitySlot1=='J|Hold' and not event.values.MCC_Link_grouped)
local saved=config()
assert(not saved:find('map=',1,true))
assert(saved:find('global.AbilitySlot1=J|Hold',1,true))
assert(saved:find('[ModCoreControls.module]',1,true) and saved:find('default.HoldThreshold=100|350',1,true))
local conflict=mappings.indices.MCC_actions_global_AbilitySlot2
model:set(conflict,'J|Hold')
local accepted,reason,failedEvent=model:apply()
assert(not accepted and reason:find('Key J (Hold) is bound to both "Ability Slot 1" and "Ability Slot 2"',1,true),reason)
assert(failedEvent==nil and model.pending[conflict]=='J|Hold' and model.committed[conflict]=='none')
assert(config()==saved,'invalid Apply changed persisted config')
-- A key taken on another tab is refused at Apply too, naming both settings.
do
    local keys=choices.open(mappings.provider)
    local quickslot=mappings.indices.MCC_actions_grouped_QuickSlot1
    keys:set(quickslot,'J|Hold')
    local refused,message=keys:apply()
    assert(not refused and message:find('Key J (Hold) is bound to both',1,true),message)
    assert(config()==saved,'a cross-tab collision changes nothing')
end
local native=Menu.new(definition,Config.decode(saved,definition))
assert(native.values.MCC_actions_global_AbilitySlot1=='J|Hold')
model=choices.open(mappings.provider)
assert(not model.error,model.error)
assert(model.pending[slot]=='J|Hold')
-- The Hold threshold slider on the main page saves its value on Apply, keeping the keys.
do
    local home=choices.open(main.provider)
    assert(not home.error,home.error)
    local threshold=main.indices.MCC_module_default_HoldThreshold
    assert(home.pending[threshold]=='100|350','the window starts at its default')
    home:set(threshold,'150|400')
    assert(home:apply())
    local text=config()
    assert(text:find('default.HoldThreshold=150|400',1,true) and text:find('global.AbilitySlot1=J|Hold',1,true),
        'the window is saved and the keys stay')
end
-- The Default Group mirror on Group Keys saves the main page's Default wheel.
do
    local keys=choices.open(mappings.provider)
    local mirror=mappings.indices.MCC_actions_grouped_DefaultGroup
    assert(keys.pending[mirror]==1)
    keys:set(mirror,2)
    assert(keys:apply())
    assert(config():find('default.DefaultWheel=2',1,true),'the mirror saves Default wheel')
    local home=choices.open(main.provider)
    assert(home.pending[main.indices.MCC_module_default_DefaultWheel]==2,'the main page loads it')
    keys:set(mirror,1);assert(keys:apply())
end
-- Live gamepad assignments become one read-only row per button on the Controller tab.
local schema=DMM.schema(definition,{{key='Gamepad_DPad_Left',label='D-Pad Left',actions={'Quickslot Left','Map|Zoom'}},
    {key='Gamepad_DPad_Up',label='D-Pad Up',actions={}}},DMM.mappings.id)
assert(schema:find('[Setting.MCC_Pad_Gamepad_DPad_Left]',1,true)
    and schema:find('PresetLabels=Quickslot Left, Map Zoom|Quickslot Left, Map Zoom',1,true)
    and schema:find('PresetLabels=Unassigned|Unassigned',1,true)
    and not schema:find('MCC_Pad_Unavailable',1,true))
-- The work-in-progress note heads the Controller tab, above the button rows.
assert(schema:find('[Setting.MCC_Pad_Note]',1,true)<schema:find('[Setting.MCC_Pad_Gamepad_DPad_Left]',1,true))
assert(not DMM.schema(definition,{{key='K',label='K',actions={}}}):find('[Setting.MCC_Pad',1,true),
    'controller rows stay off the main page')
assert(not pcall(DMM.schema,definition,nil,'ModCoreControls.nothing'),'unknown pages are refused')
-- Through ModCoreSettings' conflict scope, the same key and trigger on two rows of a page is
-- marked while editing, across Group Keys and Global Keys too, where the tab picker shows it.
if type(fieldTypes.conflicts)=='function' then
    local otherSlot=assert(mappings.indices.MCC_actions_global_AbilitySlot2)
    assert(mappings.items[slot].conflictScope=='controls','the real parser reads the controls scope')
    local rows=fieldTypes.conflicts(model)
    assert(next(rows)==nil,'saved controls start without collisions')
    model:set(otherSlot,'J|Hold')
    rows=fieldTypes.conflicts(model)
    assert(rows[otherSlot] and rows[slot],'a pair marks both rows')
    -- Another trigger is a different binding.
    model:set(otherSlot,'J|Tap')
    rows=fieldTypes.conflicts(model)
    assert(next(rows)==nil,'Tap and Hold on one key do not collide')
    model:set(otherSlot,'none')
    local quickslot=mappings.indices.MCC_actions_grouped_QuickSlot1
    model:set(quickslot,'J|Hold')
    local pickers
    rows,pickers=fieldTypes.conflicts(model)
    assert(rows[quickslot] and rows[slot] and pickers[1],'a pair on two tabs marks both rows and the tab picker')
    model:set(quickslot,'none')
    print('PASS ModCoreSettings marks colliding Controls keys on a page and across its tabs')
else
    print('SKIP collision marking: this ModCoreSettings has no conflict scopes')
end
print('PASS DMM matches MCC definitions, storage, and pages')

-- End to end through ModCoreSettings: the page main.lua publishes becomes ModCore
-- Settings' Controls tab, its first tab (the page opens on Settings). ModCore Settings' page
-- parses with all four tabs, Controls | Templates | Settings | Developer Tools; both slots
-- fill, the Visuals slot inside the Controls tab included; Apply there saves into each
-- page's own config and publishes its own event; every Mappings link opens the Mappings
-- page on its tab at its first row, Apply there saves, Back returns to the Controls tab with
-- the link selected; and each mod list entry or link to a slot opens its tab.
do
    local MenuPages=dofile(settings..'/menu_pages.lua')
    local Slots=dofile(settings..'/menu_slots.lua')
    local Links=dofile(settings..'/page_links.lua')
    local MenuData=dofile(settings..'/menu_data.lua')
    local Groups=dofile(settings..'/browser_groups.lua')
    local reports={}
    local function report(event,detail) reports[#reports+1]=event..' '..tostring(detail) end
    local controller=assert(Slots.install(choices,report,Contributions,function() return nil end))
    local applied={}
    controller.applied=function(provider,event) applied[#applied+1]={id=provider.id,event=event} end
    local function compile(menu) return MenuData.manifest(menu) end
    local function hooked(page)
        local own=PageHooks.loader()(page.hooks)
        local context=PageHooks.context(page)
        local manifest,menu=PageHooks.manifest(own,context,compile)
        return own,manifest,context,menu
    end
    local function stored(page) return PageHooks.stored(page.menu),PageHooks.context(page) end
    -- The contribution exactly as main.lua publishes it, with its config in the temp folder.
    local contribution
    do
        local real,given=package.loaded.menu_contributions,nil
        package.loaded.menu_contributions={publisher=function(_,options)
            given=options
            return {publish=function(_,value) contribution=value;return 1 end}
        end}
        local modRef,queue=rawget(_G,'ModRef'),rawget(_G,'ExecuteInGameThread')
        ModRef,ExecuteInGameThread={},nil
        local print_=print;print=function() end
        local ran,why=pcall(assert(loadfile(scripts..'/main.lua')))
        print=print_
        ModRef,ExecuteInGameThread,package.loaded.menu_contributions=modRef,queue,real
        assert(ran,why)
        assert(given.id=='ModCoreControls' and Contributions.validate('ModCoreControls',contribution))
        for _,page in ipairs(contribution.pages) do
            if page.configDirectory then page.configDirectory=temp end
            -- Installed, the mod's folder is 2_ModCore_Controls.
            if page.attach then page.attach='2_ModCore_Controls' end
        end
        contribution.id='ModCoreControls'
    end
    -- A stand-in for ModCore Templates, published first: its Quickslots page fills the
    -- Visuals slot and its list the Templates tab, its entry links to that tab, and a
    -- merged module page links to the Visuals slot.
    local template=table.concat({'[Category.Quickslots]','mcHeading=0','',
        '[Setting.MCT_Template]','Id=MCT_Template','Label=Quickslots','Group=Quickslots','Type=picker',
        'Default=0','PresetValues=0|1','PresetLabels=Native|Fancy','ConfigFile=templates.ini',
        'ConfigSection=Templates','ConfigKey=Template','mcCategory=1','',
        '[Setting.MCT_Size]','Id=MCT_Size','Label=Size','Group=Fancy','Type=picker','Default=0',
        'PresetValues=0|1','PresetLabels=Small|Large','VisibleWhen=MCT_Template','VisibleValues=1',
        'ConfigFile=templates.ini','ConfigSection=Templates','ConfigKey=Size',''},'\n')
    local listing=table.concat({'[Category.Player]','',
        '[Setting.MCT_Listed_1]','Id=MCT_Listed_1','Label=Wheels','Group=Player','Type=picker','Default=0',
        'PresetValues=0|1','PresetLabels=Fangdango|Fangdango','mcReadOnly=1',''},'\n')
    local merged=table.concat({'[Category.Fangdango]','',
        '[Setting.MCT_MergedNotice]','Id=MCT_MergedNotice','Label=Merged into Controls','Group=Fangdango',
        'Type=picker','Default=0','PresetValues=0|1','PresetLabels=Controls|Controls','mcNavigation=1',
        'mcLinkPage=controls:visuals','mcType=tab',''},'\n')
    local templates={id='ModCoreTemplates',pages={
        {id='ModCoreTemplates',name='ModCore Templates',attach='3_ModCore_Templates',link='settings:templates'},
        {id='ModCoreTemplates.templates',name='ModCore Templates',manifest=listing,configDirectory=temp,visible=false},
        {id='ModCoreTemplates.quickslots',name='Quickslots',manifest=template,configDirectory=temp,visible=false},
        {id='ModCoreTemplates.module.Fangdango',name='Fangdango',manifest=merged,configDirectory=temp,
            attach='9_ModCore_Fangdango'}},
        rows={{page='ModCoreTemplates.templates',slot='settings:templates',settings={'MCT_Listed_1'}},
            {page='ModCoreTemplates.quickslots',slot='controls:visuals',settings={'MCT_Template','MCT_Size'}}}}
    assert(Contributions.validate('ModCoreTemplates',{pages=templates.pages,rows=templates.rows}))
    local mcs={id='ModCoreSettings',pages={{id='ModCoreSettings',name='ModCore Settings',attach='1_ModCore_Settings',
        menu=dofile(settings..'/mcs_page.lua'),configDirectory=temp..'/mcs'}}}
    assert(os.execute('mkdir ' .. string.format('%q',temp..'/mcs')))
    local function placeholder(folder)
        return {id='detected:ue4ss:'..folder:lower(),name=folder,detectedKind='ue4ss',noSettings=true,choices={}}
    end
    local providers={placeholder('1_ModCore_Settings'),placeholder('2_ModCore_Controls'),
        placeholder('3_ModCore_Templates'),placeholder('9_ModCore_Fangdango'),
        {id='Zeta',name='Zeta',choices={{id='z'}},path='/z/mod_settings.ini'}}
    local state={}
    MenuPages.apply(providers,{templates,contribution,mcs},function(content) return choices.parse(content) end,
        state,report,controller,hooked,compile,stored)
    assert(#reports==0,table.concat(reports,' / '))
    local byId,listed={},{}
    for index,provider in ipairs(providers) do
        byId[provider.id]=index
        if not provider.mcBrowserHidden then listed[#listed+1]=provider.id end
    end
    table.sort(listed)
    -- The mod list: ModCore Controls' and ModCore Templates' entries link to their tabs.
    assert(table.concat(listed,',')=='ModCoreControls.entry,ModCoreSettings,'
        ..'ModCoreTemplates,ModCoreTemplates.module.Fangdango,Zeta',table.concat(listed,','))
    local entry=providers[byId['ModCoreControls.entry']]
    assert(entry.mcModuleEntry and entry.mcLinkSlot.host=='ModCoreSettings' and entry.mcLinkSlot.slot=='controls',
        'ModCore Controls\' entry opens the Controls tab')
    assert(providers[byId.ModCoreTemplates].mcLinkSlot.slot=='templates')
    -- The main page and its Mappings page are kept, listed nowhere.
    for _,id in ipairs(ids) do
        assert(byId[id] and providers[byId[id]].mcBrowserHidden,id..' is kept, unlisted')
    end
    -- ModCore Settings' page as the browser leaves it: its Developer Tools tab appended.
    local host=providers[byId.ModCoreSettings]
    host.mcManifest=host.mcManifest:gsub('%s*$','')..'\n\n'
        ..Groups.manifest({['ModCoreDevTools.sounds']=true},{},{{id='ModCoreDevTools.sounds',name='Sounds Explorer'}})
    host.choices=choices.parse(host.mcManifest);host.settingsCount=#host.choices
    controller.inserts=state.inserts
    assert(controller:load(host,function() return nil end),'both slots fill')
    assert(#reports==0,table.concat(reports,' / '))
    local model=choices.open(host)
    assert(not model.error,model.error)
    local index,order={},{}
    for i,item in ipairs(model.items) do index[item.id]=i;order[i]=item.id end
    -- DMM takes at most 256 settings on a page.
    assert(#model.items<=256 and #model.items==#host.choices,#model.items)
    local tabs=model.items[1]
    assert(tabs.id=='MCS_Page' and table.concat(tabs.labels,'|')=='Controls|Templates|Settings|Developer Tools'
        and table.concat(tabs.values,'|')=='0|1|2|3' and model.pending[1]==2,'four tabs, opening on Settings')
    -- The Controls tab: the Quickslots picker and its template's rows, the Mappings links,
    -- then Behaviours. Nothing of MCC's placeholder remains.
    local mainIds=DMM.ids(DMM.manifest())
    local expected={'MCS_Page','MCT_Template','MCT_Size'}
    for n=2,#mainIds do expected[#expected+1]=mainIds[n] end
    assert(table.concat(order,',',1,#expected)==table.concat(expected,','),table.concat(order,','))
    assert(not index.MCC_Visuals_Pending and not index.MCS_Controls and not index.MCS_Templates,'placeholders give way')
    local function shown(page)
        model:set(1,page)
        local visible=model:visibility()
        local out={}
        for i,item in ipairs(model.items) do if visible[i] then out[#out+1]=item.id end end
        return table.concat(out,',')
    end
    local controls=shown(0)
    assert(controls:find('^MCS_Page,MCT_Template,MCC_Link_grouped') and controls:find('MCC_module_default_KeyOutline$')
        and not controls:find('SortBy',1,true) and not controls:find('MCT_Listed_1',1,true),controls)
    assert(shown(1)=='MCS_Page,MCT_Listed_1',shown(1))
    local own=shown(2)
    assert(own:find('CompactStyle',1,true) and own:find('SortBy',1,true) and not own:find('MCC_',1,true),own)
    assert(shown(3)=='MCS_Page,MCS_Index_1',shown(3))
    model:set(1,0)
    assert(not model:dirty(),'tabs are navigation')
    -- The rows keep their groups and their own types: Behaviours heads its two subgroups,
    -- the threshold is ModCoreSettings' range, the links are edit links.
    local threshold=model.items[index.MCC_module_default_HoldThreshold]
    assert(threshold.kind=='extension' and threshold.editor=='range','the threshold stays a range')
    local link=model.items[index.MCC_Link_grouped]
    assert(link.mcNavigation and link.mcLinkPage=='ModCoreControls.mappings#'..anchors[1] and link.mcTabs,'links stay edit links')
    local parents={}
    for _,item in ipairs(model.items) do
        if item.id:match('^MCC_module_default_') then
            assert(item.mcGroup and item.mcGroup.parent and item.mcGroup.parent.label=='Behaviours',item.id..' under Behaviours')
            parents[item.mcGroup.parent]=true
        end
    end
    assert(next(parents) and next(parents,next(parents))==nil,'one shared Behaviours heading')
    assert(model.items[index.MCT_Template].mcSlotSource==providers[byId['ModCoreTemplates.quickslots']]
        and model.items[index.MCC_Link_grouped].mcSlotSource==providers[byId.ModCoreControls],'each row keeps its owner')
    -- Apply on the Controls tab saves into each page's own config and publishes its own event.
    local before=config()
    model:set(index.MCC_module_default_HoldThreshold,'120|300')
    model:set(index.MCT_Template,1)
    assert(model:dirty())
    local ok,why=model:apply()
    assert(ok,why)
    local text=config()
    assert(text:find('default.HoldThreshold=120|300',1,true) and text~=before,'MCC saves its own setting')
    local file=assert(io.open(temp..'/templates.ini','rb'));local saved=file:read('a');file:close()
    assert(saved:find('Template=1',1,true),'the template choice is saved by its own page')
    local events={}
    for _,entryEvent in ipairs(applied) do events[entryEvent.id]=entryEvent.event end
    assert(events.ModCoreControls and events.ModCoreControls.values.MCC_module_default_HoldThreshold=='120|300',
        'MCC\'s Apply subscribers hear the tab\'s Apply')
    assert(events['ModCoreTemplates.quickslots'],'the template page publishes its own')
    -- A DMM page over these providers: the listed rows and DMM's full list.
    local page={rows={},allRows={},controlStatus={},mode='browser'}
    for at,provider in ipairs(providers) do
        local row={providerIndex=at}
        page.allRows[#page.allRows+1]=row
        if not provider.mcBrowserHidden then page.rows[#page.rows+1]=row end
    end
    local trace={}
    page.controls={tick=function() return false end,refresh=function() end,
        select=function(_,at) trace[#trace+1]='select '..at end,
        show=function(self,at)
            controller:load(providers[at],function() return nil end)
            self.model=choices.open(providers[at]);self.provider=providers[at]
        end}
    function page:showBrowser() self.mode='browser';trace[#trace+1]='browser' end
    function page:showDetail(row)
        self.mode='detail'
        self.controls:show(self.rows[row].providerIndex)
        trace[#trace+1]=self.controls.provider.id
    end
    Links.wrap(page,providers,{setText=function(_,message) reports[#reports+1]='status '..message end},controller,report)
    local function rowOf(id)
        for row,candidate in ipairs(page.rows) do if providers[candidate.providerIndex].id==id then return row end end
    end
    local function follow(id)
        local current=page.controls.model
        local at
        for i,item in ipairs(current.items) do if item.id==id then at=i end end
        current.mcActivateLink=true;current:set(assert(at,id),0)
        assert(page.controls:tick()==true)
        return at
    end
    -- ModCore Controls' entry opens ModCore Settings' page on the Controls tab, at its first row.
    trace={}
    page:showDetail(rowOf('ModCoreControls.entry'))
    assert(page.controls.provider==host and page.controls.model.pending[1]==0
        and trace[#trace]=='select '..index.MCT_Template,table.concat(trace,','))
    -- ModCore Templates' entry opens the Templates tab.
    trace={}
    page:showDetail(rowOf('ModCoreTemplates'))
    assert(page.controls.provider==host and page.controls.model.pending[1]==1
        and trace[#trace]=='select '..index.MCT_Listed_1,table.concat(trace,','))
    page:showBrowser()
    -- A link to the Visuals slot opens the Controls tab at the Quickslots picker.
    page:showDetail(rowOf('ModCoreTemplates.module.Fangdango'))
    trace={}
    follow('MCT_MergedNotice')
    assert(page.controls.provider==host and page.controls.model.pending[1]==0
        and trace[#trace]=='select '..index.MCT_Template,table.concat(trace,','))
    page:showBrowser();page.controls:tick()
    assert(page.controls.provider==providers[byId['ModCoreTemplates.module.Fangdango']],'Back returns to the merged page')
    page:showBrowser()
    -- Every Mappings link opens the Mappings page on its tab, at the tab's first row; Apply
    -- there saves; Back lands on the Controls tab, link selected.
    local saves={MCC_Link_grouped={'MCC_actions_grouped_QuickSlot4','L|Hold','grouped.QuickSlot4=L|Hold'},
        MCC_Link_global={'MCC_actions_global_ConsumableSlot4','K|Tap','global.ConsumableSlot4=K|Tap'}}
    for n,id in ipairs({'MCC_Link_grouped','MCC_Link_global','MCC_Link_controller'}) do
        page:showDetail(rowOf('ModCoreSettings'))
        assert(page.controls.provider==host)
        page.controls.model:set(1,2)
        page.controls.model:set(1,0)
        trace={}
        local row=follow(id)
        local keys=page.controls.model
        assert(page.mode=='detail' and page.controls.provider==providers[byId['ModCoreControls.mappings']],
            id..' opens Mappings')
        assert(not keys.error,keys.error)
        local first
        for i,item in ipairs(keys.items) do if item.id==anchors[n] then first=i end end
        assert(keys.items[1].id=='MCC_Mappings_Tab' and keys.pending[1]==n-1 and keys:visibility()[first]
            and trace[#trace]=='select '..first and not keys:dirty(),id..' opens its tab: '..table.concat(trace,','))
        local save=saves[id]
        if save then
            local at
            for i,item in ipairs(keys.items) do if item.id==save[1] then at=i end end
            keys:set(at,save[2])
            assert(keys:apply())
            assert(config():find(save[3],1,true),'Apply on the tab saves: '..save[3])
        end
        trace={}
        page:showBrowser()
        page.controls:tick()
        assert(page.mode=='detail' and page.controls.provider==host and page.controls.model.pending[1]==0
            and trace[#trace]=='select '..row,id..' Back: '..table.concat(trace,','))
        page:showBrowser()
        assert(page.mode=='browser')
    end
    assert(#reports==0,table.concat(reports,' / '))
    print('PASS ModCore Settings\' page has Controls | Templates | Settings | Developer Tools: slots, links, Apply and Back')
end
assert(os.execute('rm -r ' .. string.format('%q',temp)))
