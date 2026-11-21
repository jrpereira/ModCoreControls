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
same(ids,{'ModCoreControls','ModCoreControls.grouped','ModCoreControls.global','ModCoreControls.controller'},'page ids')
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
local main,groups,global,pad=pages.ModCoreControls,pages['ModCoreControls.grouped'],
    pages['ModCoreControls.global'],pages['ModCoreControls.controller']
assert(main.manifest:find('mcSlot=visuals',1,true),'ModCoreSettings reads row slots from the manifest text')
-- The published pages name this hooks file and the mod folder as their config directory.
local Contributions=require('menu_contributions')
local published={{id=DMM.page.id,name=DMM.page.name,attach='2_ModCore_Controls',hooks=scripts .. '/mcs_page.lua',
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
        assert(link.mcNavigation and link.mcLinkPage==ids[i] and link.mcTabs and #link.labels==2
            and link.labels[1]=='edit' and link.labels[2]=='edit' and link.group=='Mappings',link.id..' is an edit link')
        labels[#labels+1]=link.label
    end
    same(labels,{'Group Keys','Global Keys','Controller'},'link labels')
    local slot=main.items[1]
    assert(slot.mcReadOnly and #slot.values==1 and slot.label=='Quickslots')
end
-- Every MCC setting is on exactly one page with its storage unchanged; the mirror is on Group Keys.
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
-- Extra rows: the slot and three links on the main page, the Default Group mirror on
-- Group Keys, and Controller's unavailable and note rows.
assert(#main.items+#groups.items+#global.items+#pad.items==editable+7,'DMM row count does not match editable MCC settings')
assert(groups.indices.MCC_actions_grouped_DefaultGroup and #pad.items==2)
for _,id in ipairs({'MCC_Pad_Unavailable','MCC_Pad_Note'}) do
    local item=pad.items[assert(pad.indices[id],id)]
    assert(item.mcReadOnly and #item.values==1,'read-only display row: ' .. id)
end
-- Inner pages show every row: no navigation gates them.
for _,page in ipairs({groups,global,pad}) do
    local model=choices.open(page.provider)
    assert(not model.error,model.error)
    for i in ipairs(page.items) do assert(model:visibility()[i],page.provider.id..' row '..i..' is shown') end
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
-- Inner pages head their groups by name.
assert(groups.manifest:find('[Category.actions.grouped.1]\nmcLabel=Active Group\n',1,true)
    and global.manifest:find('[Category.actions.global.2]\nmcLabel=Consumables\n',1,true))
-- A group activation key's Tap stays on its wheel, so it reads Toggle; values keep Tap.
local focusRow=groups.manifest:match('%[Setting%.MCC_actions_grouped_ActivateAbilities%][^%[]*')
assert(focusRow and focusRow:find('Triggers=Hold|Tap',1,true)
    and focusRow:find('TriggerLabels=Hold|Toggle',1,true),'activation keys label Tap as Toggle')
local slotKey=groups.manifest:match('%[Setting%.MCC_actions_grouped_QuickSlot1%][^%[]*')
assert(slotKey and not slotKey:find('TriggerLabels',1,true),'other keys keep the trigger names')

-- Apply on an inner page saves that page's keys; settings on other pages keep their values.
local slot=global.indices.MCC_actions_global_AbilitySlot1
local model=choices.open(global.provider)
assert(not model.error,model.error)
model:set(slot,'J|Hold')
local ok,why,event=model:apply(); assert(ok,why)
assert(event.values.MCC_actions_global_AbilitySlot1=='J|Hold' and not event.values.MCC_Link_grouped)
local saved=config()
assert(not saved:find('map=',1,true))
assert(saved:find('global.AbilitySlot1=J|Hold',1,true))
assert(saved:find('[ModCoreControls.module]',1,true) and saved:find('default.HoldThreshold=100|350',1,true))
local conflict=global.indices.MCC_actions_global_AbilitySlot2
model:set(conflict,'J|Hold')
local accepted,reason,failedEvent=model:apply()
assert(not accepted and reason:find('Key J (Hold) is bound to both "Ability Slot 1" and "Ability Slot 2"',1,true),reason)
assert(failedEvent==nil and model.pending[conflict]=='J|Hold' and model.committed[conflict]=='none')
assert(config()==saved,'invalid Apply changed persisted config')
-- A key taken on another page is refused at Apply too, naming both settings.
do
    local keys=choices.open(groups.provider)
    local quickslot=groups.indices.MCC_actions_grouped_QuickSlot1
    keys:set(quickslot,'J|Hold')
    local refused,message=keys:apply()
    assert(not refused and message:find('Key J (Hold) is bound to both',1,true),message)
    assert(config()==saved,'a cross-page collision changes nothing')
end
local native=Menu.new(definition,Config.decode(saved,definition))
assert(native.values.MCC_actions_global_AbilitySlot1=='J|Hold')
model=choices.open(global.provider)
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
    local keys=choices.open(groups.provider)
    local mirror=groups.indices.MCC_actions_grouped_DefaultGroup
    assert(keys.pending[mirror]==1)
    keys:set(mirror,2)
    assert(keys:apply())
    assert(config():find('default.DefaultWheel=2',1,true),'the mirror saves Default wheel')
    local home=choices.open(main.provider)
    assert(home.pending[main.indices.MCC_module_default_DefaultWheel]==2,'the main page loads it')
    keys:set(mirror,1);assert(keys:apply())
end
-- Live gamepad assignments become one read-only row per button on the Controller page.
local schema=DMM.schema(definition,{{key='Gamepad_DPad_Left',label='D-Pad Left',actions={'Quickslot Left','Map|Zoom'}},
    {key='Gamepad_DPad_Up',label='D-Pad Up',actions={}}},DMM.controller.id)
assert(schema:find('[Setting.MCC_Pad_Gamepad_DPad_Left]',1,true)
    and schema:find('PresetLabels=Quickslot Left, Map Zoom|Quickslot Left, Map Zoom',1,true)
    and schema:find('PresetLabels=Unassigned|Unassigned',1,true)
    and not schema:find('MCC_Pad_Unavailable',1,true))
-- The work-in-progress note heads the Controller page, above the button rows.
assert(schema:find('[Setting.MCC_Pad_Note]',1,true)<schema:find('[Setting.MCC_Pad_Gamepad_DPad_Left]',1,true))
assert(not DMM.schema(definition,{{key='K',label='K',actions={}}}):find('MCC_Pad',1,true),
    'controller rows stay off the main page')
assert(not pcall(DMM.schema,definition,nil,'ModCoreControls.nothing'),'unknown pages are refused')
-- Through ModCoreSettings' conflict scope, the same key and trigger on two rows of a page is
-- marked while editing.
if type(fieldTypes.conflicts)=='function' then
    local otherSlot=assert(global.indices.MCC_actions_global_AbilitySlot2)
    assert(global.items[slot].conflictScope=='controls','the real parser reads the controls scope')
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
    print('PASS ModCoreSettings marks colliding Controls keys on a page')
else
    print('SKIP collision marking: this ModCoreSettings has no conflict scopes')
end
print('PASS DMM matches MCC definitions, storage, and pages')

-- End to end through ModCoreSettings: the published pages become providers, the inner
-- pages are listed nowhere, a contributed row fills the Visuals slot, every Mappings link
-- opens its page, Apply there saves, and Back returns to the main page.
do
    local MenuPages=dofile(settings..'/menu_pages.lua')
    local Slots=dofile(settings..'/menu_slots.lua')
    local Links=dofile(settings..'/page_links.lua')
    local reports={}
    local function report(event,detail) reports[#reports+1]=event..' '..tostring(detail) end
    local controller=assert(Slots.install(choices,report,Contributions,function() return nil end))
    local function hooked(page)
        local own=PageHooks.loader()(page.hooks)
        local context=PageHooks.context(page)
        return own,PageHooks.manifest(own,context),context
    end
    -- A stand-in for ModCore Templates: a hidden page whose template picker fills the slot.
    local template=table.concat({'[Category.Quickslots]','mcHeading=0','',
        '[Setting.MCT_Template]','Id=MCT_Template','Label=Quickslots','Group=Quickslots','Type=picker',
        'Default=0','PresetValues=0|1','PresetLabels=Native|Fancy','ConfigFile=templates.ini',
        'ConfigSection=Templates','ConfigKey=Template','mcCategory=1',''},'\n')
    local providers={{id='detected:ue4ss:2_modcore_controls',name='2_ModCore_Controls',detectedKind='ue4ss',
        noSettings=true,choices={}},{id='Zeta',name='Zeta',choices={{id='z'}},path='/z/mod_settings.ini'}}
    local state={}
    MenuPages.apply(providers,{
        {id='ModCoreControls',pages=published},
        {id='ModCoreTemplates',pages={{id='ModCoreTemplates',name='Templates',manifest=template,
            configDirectory=temp,visible=false}},
            rows={{page='ModCoreTemplates',slot='controls:visuals',settings={'MCT_Template'}}}},
    },function(content) return choices.parse(content) end,state,report,controller,hooked)
    assert(#reports==0,table.concat(reports,' / '))
    local order,byId={},{}
    for index,provider in ipairs(providers) do order[index]=provider.id;byId[provider.id]=index end
    assert(table.concat(order,',')=='ModCoreControls,ModCoreControls.grouped,ModCoreControls.global,'
        ..'ModCoreControls.controller,Zeta',table.concat(order,','))
    for n=2,4 do
        assert(providers[n].mcBrowserHidden and providers[n].mcBrowserGroup=='inner',providers[n].id..' is not listed')
    end
    assert(not providers[1].mcBrowserHidden and providers[1].mcModuleEntry,'the main page is the mod\'s entry')
    -- The slot resolves: the template picker takes the placeholder's place.
    controller.inserts=state.inserts
    local host=providers[1]
    assert(controller:load(host,function() return nil end),'the slot is filled')
    local hostModel=choices.open(host)
    assert(not hostModel.error,hostModel.error)
    assert(hostModel.items[1].id=='MCT_Template' and hostModel.items[2].id=='MCC_Link_grouped',
        'the template picker heads the page, the links follow')
    -- A DMM page over these providers: the listed rows and DMM's full list.
    local page={rows={},allRows={},controlStatus={},mode='browser'}
    for index,provider in ipairs(providers) do
        local row={providerIndex=index}
        page.allRows[#page.allRows+1]=row
        if not provider.mcBrowserHidden then page.rows[#page.rows+1]=row end
    end
    local shown={}
    page.controls={tick=function() return false end,refresh=function() end,
        select=function(_,index) shown[#shown+1]='select '..index end,
        show=function(self,index)
            if providers[index].mcSlotBase then controller:load(providers[index],function() return nil end) end
            self.model=choices.open(providers[index]);self.provider=providers[index]
        end}
    function page:showBrowser() self.mode='browser';shown[#shown+1]='browser' end
    function page:showDetail(row)
        self.mode='detail'
        self.controls:show(self.rows[row].providerIndex)
        shown[#shown+1]=self.controls.provider.id
    end
    Links.wrap(page,providers,{setText=function(_,text) reports[#reports+1]='status '..text end},controller,report)
    local function follow(id)
        local current=page.controls.model
        local index
        for i,item in ipairs(current.items) do if item.id==id then index=i end end
        current.mcActivateLink=true;current:set(assert(index,id),0)
        assert(page.controls:tick()==true)
        return index
    end
    for n,link in ipairs({'MCC_Link_grouped','MCC_Link_global','MCC_Link_controller'}) do
        page:showDetail(1)
        assert(page.controls.provider==host)
        local row=follow(link)
        assert(page.mode=='detail' and page.controls.provider==providers[n+1],link..' opens '..providers[n+1].id)
        assert(not page.controls.model.error,page.controls.model.error)
        if link=='MCC_Link_global' then
            -- Apply on the inner page saves.
            local keys=page.controls.model
            local index
            for i,item in ipairs(keys.items) do if item.id=='MCC_actions_global_ConsumableSlot4' then index=i end end
            keys:set(index,'K|Tap')
            assert(keys:apply())
            assert(config():find('global.ConsumableSlot4=K|Tap',1,true),'Apply on Global Keys saves')
        end
        -- Back returns to the main page with the link selected; Back there reaches the browser.
        shown={}
        page:showBrowser()
        page.controls:tick()
        assert(page.mode=='detail' and page.controls.provider==host
            and shown[#shown]=='select '..row,link..' Back: '..table.concat(shown,','))
        page:showBrowser()
        assert(page.mode=='browser')
    end
    assert(#reports==0,table.concat(reports,' / '))
    print('PASS the Controls pages resolve in ModCoreSettings: slot, inner pages, Apply and Back')
end
assert(os.execute('rm -r ' .. string.format('%q',temp)))
