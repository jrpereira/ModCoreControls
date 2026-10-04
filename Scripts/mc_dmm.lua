-- DMM page generation and shared MCC storage.
local M = {}
local metadata={Id='ModCoreControls',Name='Controls',Author='Jorge Pereira (kell)',Version='0.1.1',
    Description='Choose a section and configure its control map.'}

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

function M.schema(definition)
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
    local values,labels={},{}
    for i,section in ipairs(definition.sections) do values[i]=i-1; labels[i]=section.name end
    block(lines,'Setting.MCC_Section',{Id='MCC_Section',Label='Section',Group='Sections',Type='picker',
        Default=0,PresetValues=table.concat(values,'|'),PresetLabels=table.concat(labels,'|'),
        mcNavigation=1,mcHeading=true})
    block(lines,'Category.Sections',{mcHeading=0})
    for i,section in ipairs(definition.sections) do
        if section.selector then
            if #section.selector.values>1 then
                block(lines,'Category.' .. section.name,{mcHeading=0})
                row(section.selector,section.name,{VisibleWhen='MCC_Section',VisibleValues=i-1})
            end
            -- Groups relative to the Default wheel are titled after the wheel they show.
            local defaultWheel
            for _,map in ipairs(section.maps) do
                if map.holdSwap then defaultWheel=map.holdSwap.defaultWheel end
            end
            for _,map in ipairs(section.maps) do
                if #map.settings>0 then
                    local id=section.id..'.'..map.id..'.settings'
                    local when=#section.maps>1 and section.selector.id or 'MCC_Section'
                    local value=#section.maps>1 and map.value or i-1
                    block(lines,'Category.'..id,{VisibleWhen=when,VisibleValues=value,
                        mcLabelWhen=when,mcLabels=value..':'..map.name})
                    for _,item in ipairs(map.settings) do row(item,id) end
                end
                for groupIndex,group in ipairs(map.groups) do
                    local id=section.id .. '.' .. map.id .. '.' .. groupIndex
                    local when=#section.maps>1 and section.selector.id or 'MCC_Section'
                    local value=#section.maps>1 and map.value or i-1
                    assert(not group.name:find('[:;]'),'group name cannot contain : or ;')
                    local labelWhen,labels=when,value .. ':' .. group.name
                    if group.wheel then
                        local wheel=assert(defaultWheel,'relative group needs a Default wheel: '..id)
                        local entries={}
                        for index,default in ipairs(wheel.values) do
                            local shown=group.wheel=='default' and index or #wheel.values+1-index
                            entries[#entries+1]=default..':'..group.name..': '..wheel.labels[shown]
                        end
                        labelWhen,labels=wheel.id,table.concat(entries,';')
                    end
                    block(lines,'Category.' .. id,{VisibleWhen=when,VisibleValues=value,
                        mcLabelWhen=labelWhen,mcLabels=labels})
                    for _,binding in ipairs(group.keys) do
                        local keyMetadata={}
                        if #binding.trigger.values==1 then keyMetadata.mcMode=binding.trigger.labels[1] end
                        if binding.optional then keyMetadata.mcOptional=1 end
                        if binding.defaultControl then
                            keyMetadata.mcDefaultControl=binding.defaultControl
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
            local ok,items=pcall(choices.parse,M.schema(definition))
            provider.choices=ok and items or {}
            provider.choiceError=not ok and tostring(items) or nil
            provider.settingsCount=#provider.choices
            provider.deferred=false
            provider.choicesLoaded=true
        end
    end
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
        end)
        if not ok then model.error=tostring(why) end
        function model:apply()
            if self.error then return false,self.error end
            local event={values={},changes={}}
            local warning
            local applied,err=pcall(function()
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
                for i,value in ipairs(self.pending) do self.committed[i]=value end
            end)
            return applied,applied and warning or tostring(err),applied and event or nil
        end
        return model
    end
    choices.mccStorageInstalled=true
end
return M
