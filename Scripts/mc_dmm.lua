-- Controls page generation and storage, run by ModCoreSettings' page hooks.
local M = {}
-- The version comes from VERSION in the mod root, the release's single source.
local function version()
    local source=debug.getinfo(1,'S').source:gsub('^@','')
    local root=source:match('^(.*)[/\\]Scripts[/\\][^/\\]+$') or (source:match('^Scripts[/\\]') and '.')
    local file=root and io.open(root..'/VERSION','rb')
    if not file then return 'unknown' end
    local text=file:read(64) or '';file:close()
    return text:gsub('^\239\187\191',''):match('^%s*(%S+)') or 'unknown'
end
M.page={id='ModCoreControls',name='Controls',author='Jorge Pereira (kell)',version=version(),
    description='Choose the quickslot visuals and behaviours, and open the key mappings and controller buttons.'}
-- The Mappings page: one inner page with a tab per map that has a page, then Controller.
M.mappings={id=M.page.id..'.mappings',name='Mappings',
    description='The key mappings and controller buttons, one tab each.'}
M.controller={id='controller',name='Controller',
    description='The controller buttons and what the game assigns to each.'}
-- The Mappings page's tab picker: navigation only, never stored.
M.tabField='MCC_Mappings_Tab'
-- What each map's link says, by map id; a map without one has its own name in the description.
local LINKS={grouped='Quickslot keys for the wheel in focus, and the keys that swap or activate wheels.',
    global='Keys for each ability and consumable slot, whichever wheel is in focus.'}

local function block(lines,name,fields)
    lines[#lines+1]='[' .. name .. ']'
    local keys={}
    for key in pairs(fields) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do lines[#lines+1]=key .. '=' .. tostring(fields[key]) end
    lines[#lines+1]=''
end

local function define()
    return require('mc_menu').define(require('mc_sections'),require('mc_maps'))
end

-- The Mappings page's tabs, in the order the main page links them: each map with a page,
-- then Controller. Each is {id=,name=,description=,section=,map=} (no map: Controller);
-- id is the map id, which names the link row MCC_Link_<id>.
function M.tabs(definition)
    local list={}
    for _,section in ipairs(definition.sections) do
        for _,map in ipairs(section.maps) do
            if map.page then
                list[#list+1]={id=map.id,name=map.page,section=section,map=map,
                    description=LINKS[map.id] or map.name..' keys.'}
            end
        end
    end
    list[#list+1]=M.controller
    return list
end

-- The inner pages: the Mappings page.
function M.pages()
    return {M.mappings}
end

-- One page's manifest text, and the id of each Mappings tab's first row by tab id
-- (filled when writing the Mappings page).
local function build(definition,gamepad,pageId)
    assert(pageId==M.page.id or pageId==M.mappings.id,'unknown Controls page: '..tostring(pageId))
    local lines = {}
    -- gate is the Mappings tab being written: its groups show only on that tab.
    local gate,firsts=nil,{}
    local function category(name,fields)
        if gate then fields.VisibleWhen,fields.VisibleValues=M.tabField,gate.value end
        block(lines,'Category.'..name,fields)
    end
    local function setting(fields)
        if gate and not firsts[gate.id] then firsts[gate.id]=fields.Id end
        block(lines,'Setting.'..fields.Id,fields)
    end
    local function row(item, group, extra)
        local data={Id=item.id,Label=item.name,Group=group,Default=item.default,
            ConfigFile='config.ini',ConfigSection=item.configSection,ConfigKey=item.configKey,
            Description=item.description}
        if item.kind=='keybind' then
            data.Type='keybind'
            -- Every key on a page shares one scope, so ModCoreSettings marks the same
            -- key and trigger on two rows as it is edited, as Apply would reject it.
            data.mcConflictScope='controls'
        elseif item.kind=='range' then
            data.Type='range'
            data.Min,data.Max,data.Step,data.DeltaMin,data.Suffix=item.minimum,item.maximum,item.step,
                math.max(item.gap,item.step),item.suffix
        elseif #item.values==1 then return
        else
            data.Type='picker'
            data.PresetValues=table.concat(item.values,'|')
            data.PresetLabels=table.concat(item.labels,'|')
            data.mcType=item.tab and 'tab' or item.cycle and 'cycle' or nil
        end
        for k,v in pairs(extra or {}) do data[k]=v end
        setting(data)
    end
    -- One read-only row. DMM pickers need two choices; ModCoreSettings collapses
    -- matching read-only labels to the single displayed value.
    local function display(id,group,label,value,extra)
        value=value:gsub('[|;\r\n]',' ')
        local fields={Id=id,Label=label,Group=group,Type='picker',Default=0,
            PresetValues='0|1',PresetLabels=value..'|'..value,mcReadOnly=1}
        for key,field in pairs(extra or {}) do fields[key]=field end
        setting(fields)
    end
    -- Keys relative to the Default wheel are labelled after the wheel they show.
    local defaultWheel
    for _,section in ipairs(definition.sections) do
        for _,map in ipairs(section.maps) do
            if map.holdSwap then defaultWheel=map.holdSwap.defaultWheel end
        end
    end
    -- A map's settings and groups.
    local function writeMap(section,map)
        -- The section's description is help text under the map's first heading, ahead of
        -- that group's own description.
        local sectionHelp=section.description
        local function help(own)
            local text=sectionHelp and own and sectionHelp .. ' ' .. own or sectionHelp or own
            sectionHelp=nil
            return text
        end
        if #map.settings>0 then
            local id=section.id..'.'..map.id..'.settings'
            -- With within, every block is a subgroup of a category without rows,
            -- headed by the within text (ModCoreSettings' mcWithin/mcWithinLabel).
            local within=map.within and section.id..'.'..map.id..'.within'
            category(id,{mcLabel=map.name,mcHelp=help(nil),mcWithin=within,mcWithinLabel=map.within})
            -- A setting with a heading starts a titled block; the ones after it
            -- follow under it.
            local current,blocks=id,0
            for _,item in ipairs(map.settings) do
                if item.heading then
                    blocks=blocks+1
                    current=id..'.'..blocks
                    category(current,{mcLabel=item.heading,mcWithin=within,mcWithinLabel=map.within})
                end
                row(item,current)
            end
        end
        for groupIndex,group in ipairs(map.groups) do
            local id=section.id .. '.' .. map.id .. '.' .. groupIndex
            assert(not group.name:find('[:;]'),'group name cannot contain : or ;')
            category(id,{mcLabel=group.name,mcHelp=help(group.description)})
            -- A mirror shows another map's setting on this page; MCC's
            -- storage keeps it in step with that setting.
            local labelSource=defaultWheel
            for _,mirror in ipairs(group.settings) do
                if mirror.mirror==defaultWheel then labelSource=mirror end
            end
            -- Rows follow the group's declared order.
            for _,entry in ipairs(group.items) do
                local mirror,binding=entry.mirror,entry.binding
                if mirror then
                    setting({Id=mirror.id,Label=mirror.name,Group=id,
                        Type='picker',Default=mirror.default,
                        PresetValues=table.concat(mirror.values,'|'),
                        PresetLabels=table.concat(mirror.labels,'|'),Description=mirror.description,
                        mcType=mirror.tab and 'tab' or mirror.cycle and 'cycle' or nil})
                else
                    -- One ModCoreSettings keybind row: key, trigger and value together.
                    local bound=binding.setting
                    local keyMetadata={Triggers=table.concat(bound.labels,'|')}
                    -- A tapped group activation key stays on its wheel until pressed
                    -- again, so its Tap reads Toggle. Display only: values keep Tap.
                    if binding.action.type=='focus' then
                        local shownLabels={}
                        for n,name in ipairs(bound.labels) do shownLabels[n]=name=='Tap' and 'Toggle' or name end
                        keyMetadata.TriggerLabels=table.concat(shownLabels,'|')
                    end
                    if binding.optional then keyMetadata.Optional=1 end
                    if binding.defaultControl then keyMetadata.DefaultControl=binding.defaultControl end
                    if binding.action.type=='focus' and binding.action.wheel then
                        local wheel=assert(labelSource,'relative focus needs a Default wheel: '..binding.id)
                        local entries={}
                        for index,default in ipairs(wheel.values) do
                            local shownWheel=binding.action.wheel=='default' and index
                                or #wheel.values+1-index
                            -- {wheel} in the name is the wheel the key shows; without
                            -- it the label is that wheel's name.
                            local label=bound.name:find('{wheel}',1,true)
                                and bound.name:gsub('{wheel}',(wheel.labels[shownWheel]:gsub('%%','%%%%')))
                                or wheel.labels[shownWheel]
                            entries[#entries+1]=default..':'..label
                            if default==wheel.default then keyMetadata.Label=label end
                        end
                        keyMetadata.mcLabelWhen=wheel.id
                        keyMetadata.mcLabels=table.concat(entries,';')
                    end
                    row(bound,id,keyMetadata)
                end
            end
        end
    end
    local tabs=M.tabs(definition)
    if pageId==M.mappings.id then
        -- The title row is the tab picker, as on ModCore Settings' own page.
        block(lines,'Category.Tabs',{mcHeading=0})
        local values,labels={},{}
        for n,tab in ipairs(tabs) do values[n],labels[n]=n-1,tab.name end
        setting({Id=M.tabField,Label=M.mappings.name,Group='Tabs',Type='picker',Default=0,
            PresetValues=table.concat(values,'|'),PresetLabels=table.concat(labels,'|'),
            mcHeading=1,mcNavigation=1})
        for n,tab in ipairs(tabs) do
            gate={id=tab.id,value=n-1}
            if tab.map then writeMap(tab.section,tab.map)
            else
                category('Controller',{})
                display('MCC_Pad_Note','Controller','Note','Work in progress')
                if gamepad then
                    for _,button in ipairs(gamepad) do
                        -- Long action lists wrap at commas in a wider value column.
                        display('MCC_Pad_'..button.key,'Controller',button.label,
                            #button.actions>0 and table.concat(button.actions,', ') or 'Unassigned',{mcWrap=1})
                    end
                else
                    display('MCC_Pad_Unavailable','Controller','Gamepad buttons','Available in game')
                end
            end
            assert(firsts[tab.id],'empty Mappings tab: '..tab.name)
        end
        return table.concat(lines,'\n'),firsts
    end
    -- The top hosts ModCore Templates' quickslot templates. The placeholder is
    -- ModCoreSettings' row slot controls:visuals: contributed rows take its place,
    -- and it shows only while nothing is contributed, as the "Quickslots" heading
    -- row. The rows keep their groups (mcSlotGroups), so the slot reads as the
    -- template's own module page: the Quickslots template picker as the heading,
    -- then the chosen template's settings.
    block(lines,'Category.Visuals',{mcHeading=0})
    display('MCC_Visuals_Pending','Visuals','Quickslots','Coming from ModCore Templates',
        {mcSlot='visuals',mcSlotGroups=1,mcCategory=1})
    -- Mappings links each tab of the Mappings page: the link opens it at the tab's first
    -- row (ModCoreSettings' '<page>#<row>'); Back there returns here.
    local _,anchors=build(definition,nil,M.mappings.id)
    block(lines,'Category.Mappings',{})
    for _,tab in ipairs(tabs) do
        setting({Id='MCC_Link_'..tab.id,Label=tab.name,Group='Mappings',Type='picker',Default=0,
            PresetValues='0|1',PresetLabels='edit|edit',mcType='tab',mcNavigation=1,
            mcLinkPage=M.mappings.id..'#'..anchors[tab.id],
            Description='Opens '..tab.name..': '..tab.description})
    end
    -- The maps without a page of their own.
    for _,section in ipairs(definition.sections) do
        for _,map in ipairs(section.maps) do
            if not map.page then writeMap(section,map) end
        end
    end
    return table.concat(lines,'\n'),firsts
end

-- The manifest of one page: pageId is M.page.id (the main page, by default) or
-- M.mappings.id.
-- gamepad: optional live button assignments from mc_gamepad.read(), for the Controller tab.
function M.schema(definition,gamepad,pageId)
    return (build(definition,gamepad,pageId or M.page.id))
end

-- A page's settings, rebuilt on every menu build so the Controller tab's rows stay current.
function M.manifest(pageId)
    local gamepad
    if pageId==M.mappings.id then
        local read,buttons=pcall(function() return require('mc_gamepad').read() end)
        gamepad=read and buttons or nil
    end
    return M.schema(define(),gamepad,pageId)
end

-- The ids of a manifest's settings, in page order: the main page's are the rows ModCore
-- Settings shows in its Controls tab.
function M.ids(manifest)
    local ids={}
    for id in ('\n'..manifest):gmatch('\nId=([^\n]+)') do ids[#ids+1]=id end
    return ids
end

-- Each load opens the config; Apply saves through that store, so a file changed
-- since the page opened is refused rather than overwritten. Every page has its own.
local opened={}

function M.load(directory,pageId)
    local definition=define()
    local store=require('mc_config').open(directory .. '/config.ini',definition)
    local shared=require('mc_menu').new(definition,store.values)
    opened[directory..'\0'..(pageId or M.page.id)]={definition=definition,store=store,shared=shared}
    local values={}
    for id,value in pairs(shared.values) do values[id]=value end
    for _,mirror in ipairs(definition.mirrors) do values[mirror.id]=shared.values[mirror.mirror.id] end
    return values
end

-- values holds every stored row by id; changes the edited ones as {old=,new=}.
-- Returns the saved values, mirrors included, and an optional warning.
-- Settings that are not on the page keep the values loaded with it.
function M.apply(directory,values,changes,pageId)
    local page=assert(opened[directory..'\0'..(pageId or M.page.id)],'Controls settings are not loaded')
    local definition,shared=page.definition,page.shared
    local resolved={}
    for id,value in pairs(values) do resolved[id]=value end
    -- A changed mirror carries its value to the setting it mirrors.
    for _,mirror in ipairs(definition.mirrors) do
        local source=mirror.mirror.id
        if changes[mirror.id] then
            assert(not changes[source] or resolved[source]==resolved[mirror.id],
                mirror.name .. ' and ' .. mirror.mirror.name .. ' were changed to different values')
            resolved[source]=resolved[mirror.id]
        end
    end
    local candidate={}
    for _,setting in ipairs(definition.settings) do
        local value=resolved[setting.id]
        if value==nil then value=shared.values[setting.id] end
        assert(require('mc_menu').valid(setting,value),'invalid setting value: ' .. setting.id)
        candidate[setting.id]=value
    end
    require('mc_input_plan').build(definition,candidate)
    for id,value in pairs(candidate) do shared:set(id,value) end
    local warning=shared:apply(page.store)
    local saved={}
    for id,value in pairs(candidate) do saved[id]=value end
    for _,mirror in ipairs(definition.mirrors) do saved[mirror.id]=candidate[mirror.mirror.id] end
    return saved,warning
end
return M
