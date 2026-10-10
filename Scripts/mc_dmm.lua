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
    description='Choose options, visuals, keyboard and mouse controls, or view controller buttons.'}

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

-- gamepad: optional live button assignments from mc_gamepad.read().
function M.schema(definition,gamepad)
    local lines = {}
    local function row(item, group, extra)
        local data={Id=item.id,Label=item.name,Group=group,Default=item.default,
            ConfigFile='config.ini',ConfigSection=item.configSection,ConfigKey=item.configKey,
            Description=item.description}
        if item.kind=='keybind' then
            data.Type='keybind'
            -- Every key on the page shares one scope, so ModCoreSettings marks the same
            -- key and trigger on two rows as it is edited, as Apply would reject it.
            data.mcConflictScope='controls'
        elseif #item.values==1 then return
        else
            data.Type='picker'
            data.PresetValues=table.concat(item.values,'|')
            data.PresetLabels=table.concat(item.labels,'|')
            data.mcType=item.tab and 'tab' or item.cycle and 'cycle' or nil
        end
        for k,v in pairs(extra or {}) do data[k]=v end
        block(lines,'Setting.' .. item.id,data)
    end
    -- Keys relative to the Default wheel are labelled after the wheel they show.
    local defaultWheel
    for _,section in ipairs(definition.sections) do
        for _,map in ipairs(section.maps) do
            if map.holdSwap then defaultWheel=map.holdSwap.defaultWheel end
        end
    end
    -- The top picker chooses a page. Options shows the Module section; Key &
    -- Mouse nests a Section picker over the other sections; all are navigation.
    local pages={'Options','Visuals','Key & Mouse','Controller'}
    local page={options=0,visuals=1,keys=2,controller=3}
    local pageValues={}
    for i in ipairs(pages) do pageValues[i]=i-1 end
    block(lines,'Setting.MCC_Page',{Id='MCC_Page',Label='Page',Group='Pages',Type='picker',
        Default=0,PresetValues=table.concat(pageValues,'|'),PresetLabels=table.concat(pages,'|'),
        mcNavigation=1,mcHeading=true})
    block(lines,'Category.Pages',{mcHeading=0})
    -- Only sections with maps get a page; a section without any (a placeholder) is
    -- left out. A single one needs no Section picker and shows under Key & Mouse.
    local keyed,values,labels={},{},{}
    for _,section in ipairs(definition.sections) do
        if section.id~='module' and #section.maps>0 then
            keyed[section]=#values
            values[#values+1],labels[#labels+1]=#values,section.name
        end
    end
    block(lines,'Category.KeyMouse',{mcHeading=0,VisibleWhen='MCC_Page',VisibleValues=page.keys})
    if #values>1 then
        block(lines,'Setting.MCC_Section',{Id='MCC_Section',Label='Section',Group='KeyMouse',Type='picker',
            Default=0,PresetValues=table.concat(values,'|'),PresetLabels=table.concat(labels,'|'),
            mcNavigation=1})
    end
    -- One read-only row. DMM pickers need two choices; ModCoreSettings collapses
    -- matching read-only labels to the single displayed value.
    local function display(id,group,label,value,extra)
        value=value:gsub('[|;\r\n]',' ')
        local fields={Id=id,Label=label,Group=group,Type='picker',Default=0,
            PresetValues='0|1',PresetLabels=value..'|'..value,mcReadOnly=1}
        for key,field in pairs(extra or {}) do fields[key]=field end
        block(lines,'Setting.'..id,fields)
    end
    -- Visuals hosts ModCore Templates' quickslot Template picker. The placeholder
    -- is ModCoreSettings' row slot controls:visuals: contributed rows take its
    -- place and gating, and it shows only while nothing is contributed. With
    -- mcSlotLabel the first contributed row takes this label and mcCategory, so the
    -- template picker is the page's "Quickslots Visuals" heading row, with the
    -- other contributed rows indented beneath it.
    block(lines,'Category.Visuals',{mcHeading=0,VisibleWhen='MCC_Page',VisibleValues=page.visuals})
    display('MCC_Visuals_Pending','Visuals','Quickslots Visuals','Coming from ModCore Templates',
        {mcSlot='visuals',mcSlotLabel=1,mcCategory=1})
    block(lines,'Category.Controller',{VisibleWhen='MCC_Page',VisibleValues=page.controller})
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
    for _,section in ipairs(definition.sections) do
        local pageWhen,pageValue='MCC_Section',keyed[section]
        if section.id=='module' then pageWhen,pageValue='MCC_Page',page.options
        elseif #values==1 then pageWhen,pageValue='MCC_Page',page.keys end
        if section.selector then
            if #section.selector.values>1 then
                local selector=section.selector
                block(lines,'Category.' .. section.name,{mcHeading=0})
                block(lines,'Setting.' .. selector.id,{Id=selector.id,Label=selector.name,
                    Group=section.name,Type='picker',Default=selector.default,
                    PresetValues=table.concat(selector.values,'|'),
                    PresetLabels=table.concat(selector.labels,'|'),
                    mcNavigation=1,VisibleWhen=pageWhen,VisibleValues=pageValue})
            end
            for _,map in ipairs(section.maps) do
                -- The section's description is help text under the first heading of each
                -- of its map pages, ahead of that group's own description.
                local sectionHelp=section.description
                local function help(own)
                    local text=sectionHelp and own and sectionHelp .. ' ' .. own or sectionHelp or own
                    sectionHelp=nil
                    return text
                end
                if #map.settings>0 then
                    local id=section.id..'.'..map.id..'.settings'
                    local when=#section.maps>1 and section.selector.id or pageWhen
                    local value=#section.maps>1 and map.value or pageValue
                    block(lines,'Category.'..id,{VisibleWhen=when,VisibleValues=value,
                        mcLabelWhen=when,mcLabels=value..':'..map.name,mcHelp=help(nil)})
                    for _,item in ipairs(map.settings) do row(item,id) end
                end
                for groupIndex,group in ipairs(map.groups) do
                    local id=section.id .. '.' .. map.id .. '.' .. groupIndex
                    local when=#section.maps>1 and section.selector.id or pageWhen
                    local value=#section.maps>1 and map.value or pageValue
                    assert(not group.name:find('[:;]'),'group name cannot contain : or ;')
                    block(lines,'Category.' .. id,{VisibleWhen=when,VisibleValues=value,
                        mcLabelWhen=when,mcLabels=value .. ':' .. group.name,mcHelp=help(group.description)})
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
                            block(lines,'Setting.' .. mirror.id,{Id=mirror.id,Label=mirror.name,Group=id,
                                Type='picker',Default=mirror.default,
                                PresetValues=table.concat(mirror.values,'|'),
                                PresetLabels=table.concat(mirror.labels,'|'),Description=mirror.description,
                                mcType=mirror.tab and 'tab' or mirror.cycle and 'cycle' or nil})
                        else
                            -- One ModCoreSettings keybind row: key, trigger and value together.
                            local setting=binding.setting
                            local keyMetadata={Triggers=table.concat(setting.labels,'|')}
                            -- A tapped group activation key stays on its wheel until pressed
                            -- again, so its Tap reads Toggle. Display only: values keep Tap.
                            if binding.action.type=='focus' then
                                local shown={}
                                for n,name in ipairs(setting.labels) do shown[n]=name=='Tap' and 'Toggle' or name end
                                keyMetadata.TriggerLabels=table.concat(shown,'|')
                            end
                            if binding.optional then keyMetadata.Optional=1 end
                            if binding.defaultControl then keyMetadata.DefaultControl=binding.defaultControl end
                            if binding.action.type=='focus' and binding.action.wheel then
                                local wheel=assert(labelSource,'relative focus needs a Default wheel: '..binding.id)
                                local entries={}
                                for index,default in ipairs(wheel.values) do
                                    local shown=binding.action.wheel=='default' and index
                                        or #wheel.values+1-index
                                    -- {wheel} in the name is the wheel the key shows; without
                                    -- it the label is that wheel's name.
                                    local label=setting.name:find('{wheel}',1,true)
                                        and setting.name:gsub('{wheel}',(wheel.labels[shown]:gsub('%%','%%%%')))
                                        or wheel.labels[shown]
                                    entries[#entries+1]=default..':'..label
                                    if default==wheel.default then keyMetadata.Label=label end
                                end
                                keyMetadata.mcLabelWhen=wheel.id
                                keyMetadata.mcLabels=table.concat(entries,';')
                            end
                            row(setting,id,keyMetadata)
                        end
                    end
                end
            end
        end
    end
    return table.concat(lines,'\n')
end

-- The page's settings, rebuilt on every menu build so controller rows stay current.
function M.manifest()
    local read,gamepad=pcall(function() return require('mc_gamepad').read() end)
    return M.schema(define(),read and gamepad or nil)
end

-- Each load opens the config; Apply saves through that store, so a file changed
-- since the page opened is refused rather than overwritten.
local opened={}

function M.load(directory)
    local definition=define()
    local store=require('mc_config').open(directory .. '/config.ini',definition)
    local shared=require('mc_menu').new(definition,store.values)
    opened[directory]={definition=definition,store=store,shared=shared}
    local values={}
    for id,value in pairs(shared.values) do values[id]=value end
    for _,mirror in ipairs(definition.mirrors) do values[mirror.id]=shared.values[mirror.mirror.id] end
    return values
end

-- values holds every stored row by id; changes the edited ones as {old=,new=}.
-- Returns the saved values, mirrors included, and an optional warning.
function M.apply(directory,values,changes)
    local page=assert(opened[directory],'Controls settings are not loaded')
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
