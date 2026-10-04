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
assert(provider.settingsCount==#items)
local model=choices.open(provider)
assert(not model.error,model.error)
local indices={}
for i,item in ipairs(items) do indices[item.id]=i end
local nav=indices.MCC_Section
assert(nav==1,'Section must be the first DMM control')
assert(items[nav].mcNavigation and items[nav].mcHeader and items[nav].mcFont==nil,
    'Section must be transient navigation presented as a heading')
local sectionValues,sectionLabels={},{}
for i,section in ipairs(definition.sections) do
    sectionValues[i],sectionLabels[i]=i-1,section.name
end
same(items[nav].values,sectionValues,'section picker values')
same(items[nav].labels,sectionLabels,'section picker labels')
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
assert(#items==editable+1,'DMM row count does not match editable MCC settings')
for sectionIndex,section in ipairs(definition.sections) do
    for _,mapDefinition in ipairs(section.maps) do
        for _,group in ipairs(mapDefinition.groups) do
            for _,binding in ipairs(group.keys) do
                local keyItem=items[assert(indices[binding.key.id])]
                assert(keyItem.mcOptional==(binding.optional or false),
                    'optional key metadata mismatch: ' .. binding.key.id)
                assert(keyItem.mcDefaultControl==binding.defaultControl,
                    'default control metadata mismatch: ' .. binding.key.id)
                assert(keyItem.mcGroup and keyItem.mcGroup.heading,
                    'key group heading missing: ' .. binding.key.id)
                local sourceValue=#section.maps>1 and mapDefinition.value or sectionValues[sectionIndex]
                assert(keyItem.mcGroup.labelRule
                    and keyItem.mcGroup.labelRule.values[sourceValue]==group.name,
                    'key group label mismatch: ' .. binding.key.id)
                if #binding.trigger.values==1 then
                    assert(keyItem.mcFixedMode==binding.trigger.labels[1],
                        'fixed trigger mode mismatch: ' .. binding.key.id)
                end
            end
        end
    end
end
local map=indices.MCC_actions_Map
assert(items[map].mcFont==nil and not items[map].mcTabs,
    'Control Map must use DMM arrows without a presentation level')
assert(model:visibility()[map])
model:set(nav,1)
assert(not model:visibility()[map] and not model:dirty())
for i,item in ipairs(items) do if i~=nav then assert(not model:visibility()[i],item.id) end end
model:set(nav,0); model:set(map,2)
local slot=indices.MCC_actions_global_SlotAction1_Key
assert(model:visibility()[slot])
model:set(slot,74)
local ok,why,event=model:apply(); assert(ok,why)
assert(not event.values.MCC_Section)
local file=assert(io.open(temp .. '/config.ini','rb')); local saved=file:read('*a'); file:close()
assert(saved:find('[ModCoreControls.actions]\nmap=global',1,true))
assert(saved:find('global.SlotAction1.key=74',1,true))
local conflict=indices.MCC_actions_global_SlotAction2_Key
model:set(conflict,74)
local accepted,reason,failedEvent=model:apply()
assert(not accepted and reason:find('MCC_actions_global_SlotAction2_Key',1,true))
assert(failedEvent==nil and model.pending[conflict]==74 and model.committed[conflict]~=74)
file=assert(io.open(temp .. '/config.ini','rb'))
assert(file:read('*a')==saved,'invalid Apply changed persisted config')
file:close()
local native=Menu.new(definition,Config.decode(saved,definition))
assert(native.values.MCC_actions_Map==2)
assert(native.values.MCC_actions_global_SlotAction1_Key==74)
model=choices.open(provider)
assert(not model.error,model.error)
assert(model.pending[map]==2 and model.pending[slot]==74)
assert(os.remove(temp .. '/config.ini')); assert(os.execute('rmdir ' .. string.format('%q',temp)))
print('PASS DMM matches MCC definitions, storage, and Section navigation')
