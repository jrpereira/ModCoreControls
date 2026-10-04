-- DMM page generation and shared MCC storage.
local M = {}
local metadata={Id='ModCoreControls',Name='Controls',Author='Jorge Pereira (kell)',Version='0.1.1',
    Description='Choose options, visuals, keyboard and mouse controls, or view controller buttons.'}

local function block(lines,name,fields)
    lines[#lines+1]='[' .. name .. ']'
    local keys={}
    for key in pairs(fields) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do lines[#lines+1]=key .. '=' .. tostring(fields[key]) end
    lines[#lines+1]=''
end

function M.manifest()
    local lines = {}
    block(lines,'Mod',metadata)
    return table.concat(lines,'\n')
end

-- gamepad: optional live button assignments from mc_gamepad.read().
function M.schema(definition,gamepad)
    local lines = {}
    local function row(item, group, extra)
        local data={Id=item.id,Label=item.name,Group=group,Default=item.default,
            ConfigFile='config.ini',ConfigSection=item.configSection,ConfigKey=item.configKey}
        if item.kind=='key' then
            data.Type,data.Minimum,data.Maximum,data.Step='integer',0,254,1
            data.mcType='keybind'
        elseif #item.values==1 then return
        else
            data.Type='picker'
            data.PresetValues=table.concat(item.values,'|')
            data.PresetLabels=table.concat(item.labels,'|')
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
    local keyed,values,labels={},{},{}
    for _,section in ipairs(definition.sections) do
        if section.id~='module' then
            keyed[section]=#values
            values[#values+1],labels[#labels+1]=#values,section.name
        end
    end
    block(lines,'Category.KeyMouse',{mcHeading=0,VisibleWhen='MCC_Page',VisibleValues=page.keys})
    block(lines,'Setting.MCC_Section',{Id='MCC_Section',Label='Section',Group='KeyMouse',Type='picker',
        Default=0,PresetValues=table.concat(values,'|'),PresetLabels=table.concat(labels,'|'),
        mcNavigation=1})
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
    -- mcSlotLabel the first contributed row takes this label and level, so the
    -- template picker is the page's "Quickslots Visuals" heading row.
    block(lines,'Category.Visuals',{mcHeading=0,VisibleWhen='MCC_Page',VisibleValues=page.visuals})
    display('MCC_Visuals_Pending','Visuals','Quickslots Visuals','Coming from ModCore Templates',
        {mcSlot='visuals',mcSlotLabel=1,mcLevel=2})
    block(lines,'Category.Controller',{VisibleWhen='MCC_Page',VisibleValues=page.controller})
    if gamepad then
        for _,button in ipairs(gamepad) do
            display('MCC_Pad_'..button.key,'Controller',button.label,
                #button.actions>0 and table.concat(button.actions,', ') or 'Unassigned')
        end
    else
        display('MCC_Pad_Unavailable','Controller','Gamepad buttons','Available in game')
    end
    display('MCC_Pad_Note','Controller','Note','Work in progress')
    for _,section in ipairs(definition.sections) do
        local pageWhen,pageValue='MCC_Section',keyed[section]
        if section.id=='module' then pageWhen,pageValue='MCC_Page',page.options end
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
                if #map.settings>0 then
                    local id=section.id..'.'..map.id..'.settings'
                    local when=#section.maps>1 and section.selector.id or pageWhen
                    local value=#section.maps>1 and map.value or pageValue
                    block(lines,'Category.'..id,{VisibleWhen=when,VisibleValues=value,
                        mcLabelWhen=when,mcLabels=value..':'..map.name})
                    for _,item in ipairs(map.settings) do row(item,id) end
                end
                for groupIndex,group in ipairs(map.groups) do
                    local id=section.id .. '.' .. map.id .. '.' .. groupIndex
                    local when=#section.maps>1 and section.selector.id or pageWhen
                    local value=#section.maps>1 and map.value or pageValue
                    assert(not group.name:find('[:;]'),'group name cannot contain : or ;')
                    block(lines,'Category.' .. id,{VisibleWhen=when,VisibleValues=value,
                        mcLabelWhen=when,mcLabels=value .. ':' .. group.name})
                    -- A mirror shows another map's setting on this page; MCC's
                    -- storage keeps it in step with that setting.
                    local labelSource=defaultWheel
                    for _,mirror in ipairs(group.settings) do
                        block(lines,'Setting.' .. mirror.id,{Id=mirror.id,Label=mirror.name,Group=id,
                            Type='picker',Default=mirror.default,
                            PresetValues=table.concat(mirror.values,'|'),
                            PresetLabels=table.concat(mirror.labels,'|')})
                        if mirror.mirror==defaultWheel then labelSource=mirror end
                    end
                    for _,binding in ipairs(group.keys) do
                        local keyMetadata={}
                        if #binding.trigger.values==1 then keyMetadata.mcMode=binding.trigger.labels[1] end
                        if binding.optional then keyMetadata.mcOptional=1 end
                        if binding.defaultControl then
                            keyMetadata.mcDefaultControl=binding.defaultControl
                        end
                        if binding.action.type=='focus' and binding.action.wheel then
                            local wheel=assert(labelSource,'relative focus needs a Default wheel: '..binding.id)
                            local entries={}
                            for index,default in ipairs(wheel.values) do
                                local shown=binding.action.wheel=='default' and index
                                    or #wheel.values+1-index
                                entries[#entries+1]=default..':'..wheel.labels[shown]
                            end
                            keyMetadata.mcLabelWhen=wheel.id
                            keyMetadata.mcLabels=table.concat(entries,';')
                        end
                        if binding.groupedBy then keyMetadata.mcGroupedBy='MCC_' .. section.id .. '_'
                            .. map.id .. '_' .. binding.groupedBy .. '_Key' end
                        row(binding.key,id,keyMetadata)
                        row(binding.trigger,id,{Pair=binding.key.id})
                    end
                end
            end
        end
    end
    return table.concat(lines,'\n')
end

function M.populate(choices,providers)
    local definition=require('mc_menu').define(require('mc_sections'),require('mc_maps'))
    for _,provider in ipairs(providers) do
        if provider.id=='ModCoreControls' then
            local read,gamepad=pcall(function() return require('mc_gamepad').read() end)
            local schema=M.schema(definition,read and gamepad or nil)
            local ok,items=pcall(choices.parse,schema)
            provider.choices=ok and items or {}
            -- ModCoreSettings reads row slots from the manifest text; MCC's page
            -- exists only in memory, so publish the exact text it parsed.
            provider.mcManifest=ok and schema or nil
            provider.choiceError=not ok and tostring(items) or nil
            provider.settingsCount=#provider.choices
            provider.deferred=false
            provider.choicesLoaded=true
        end
    end
end

local function indices(model)
    local result={}
    for i,item in ipairs(model.items) do result[item.id]=i end
    return result
end

function M.installStorage(choices)
    if choices.mccStorageInstalled then return end
    local open=choices.open
    choices.open=function(provider)
        if provider.id~='ModCoreControls' then return open(provider) end
        local definition=require('mc_menu').define(require('mc_sections'),require('mc_maps'))
        local copy={}
        for key,value in pairs(provider) do copy[key]=value end
        -- DMM supplies navigation and editing; MCC owns its data and IO.
        copy.testOnly=true
        local model=open(copy)
        model.provider=provider
        local store,shared
        local ok,why=pcall(function()
            local directory=assert(provider.path:match('^(.*)[/\\][^/\\]+$'))
            store=require('mc_config').open(directory .. '/config.ini',definition)
            shared=require('mc_menu').new(definition,store.values)
            for i,item in ipairs(model.items) do
                local value=shared.values[item.id]
                if value~=nil then model.pending[i],model.committed[i]=value,value end
            end
            for _,mirror in ipairs(definition.mirrors) do
                local i=indices(model)[mirror.id]
                if i then
                    local value=shared.values[mirror.mirror.id]
                    model.pending[i],model.committed[i]=value,value
                end
            end
        end)
        if not ok then model.error=tostring(why) end
        function model:apply()
            if self.error then return false,self.error end
            local event={values={},changes={}}
            local warning
            local applied,err=pcall(function()
                -- A changed mirror carries its value to the setting it mirrors.
                local at=indices(self)
                for _,mirror in ipairs(definition.mirrors) do
                    local m,s=at[mirror.id],at[mirror.mirror.id]
                    if m and s and self.pending[m]~=self.committed[m] then
                        assert(self.pending[s]==self.committed[s] or self.pending[s]==self.pending[m],
                            mirror.name .. ' and ' .. mirror.mirror.name .. ' were changed to different values')
                        self.pending[s]=self.pending[m]
                    end
                end
                for i,item in ipairs(self.items) do
                    if definition.byId[item.id] then
                        shared:set(item.id,self.pending[i])
                        event.values[item.id]=self.pending[i]
                        if self.pending[i]~=self.committed[i] then
                            event.changes[item.id]={old=self.committed[i],new=self.pending[i]}
                        end
                    end
                end
                require('mc_input_plan').build(definition,shared.values)
                warning=shared:apply(store)
                for _,mirror in ipairs(definition.mirrors) do
                    local m,s=at[mirror.id],at[mirror.mirror.id]
                    if m and s then self.pending[m]=self.pending[s] end
                end
                for i,value in ipairs(self.pending) do self.committed[i]=value end
            end)
            return applied,applied and warning or tostring(err),applied and event or nil
        end
        return model
    end
    choices.mccStorageInstalled=true
end
return M
