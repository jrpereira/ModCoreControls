package.path='Scripts/?.lua;' .. package.path
local Menu,DMM=require('mc_menu'),require('mc_dmm')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
local directory=os.tmpname()
assert(os.remove(directory))
assert(os.execute('mkdir ' .. string.format('%q',directory)))
local choices={}
function choices.open()
    local model={items={},pending={},committed={}}
    for i,item in ipairs(definition.settings) do
        model.items[i]={id=item.id}
        model.pending[i],model.committed[i]=item.default,item.default
    end
    return model
end
DMM.installStorage(choices)
local model=choices.open({id='ModCoreControls',path=directory .. '/mod_settings.ini'})
assert(not model.error,model.error)
local indices={}
for i,item in ipairs(model.items) do indices[item.id]=i end
assert(indices.MCC_actions_Map==nil,'the map picker is navigation, not a stored item')
-- Maps coexist: the same key in two maps is rejected like a duplicate in one.
local first=indices.MCC_actions_grouped_FixedSlot1_Key
local second=indices.MCC_actions_global_SlotAction2_Key
model.pending[first]=49
model.pending[second]=model.pending[first]
local ok,why,event=model:apply()
assert(not ok and why:find(model.items[second].id,1,true) and event==nil)
assert(model.pending[second]==model.pending[first] and
    model.committed[second]~=model.pending[second])
assert(io.open(directory .. '/config.ini','rb')==nil,'rejected Apply published a config')
model.pending[second]=3
ok,why,event=model:apply()
assert(not ok and why:find(model.items[second].id,1,true) and event==nil)
model.pending[second]=model.committed[second]
ok,why,event=model:apply()
assert(ok,why)
assert(event and event.values[model.items[second].id]~=nil)

-- Default Group mirrors Default's Default wheel: it loads from that setting, a
-- change is saved there, and changing both to different values is rejected.
local schema=DMM.schema(definition)
assert(schema:find('[Setting.MCC_actions_grouped_DefaultGroup]',1,true)
    and not schema:find('ConfigKey=grouped.DefaultGroup',1,true))
assert(schema:find('mcLabelWhen=MCC_actions_grouped_DefaultGroup\nmcLabels=1:Consumables;2:Abilities',1,true),
    'Secondary Group is labelled after the wheel other than Default')
-- DMM lists the mirror row beside the stored settings.
local open=choices.open
function choices.open(provider)
    local opened=open(provider)
    opened.items[#opened.items+1]={id='MCC_actions_grouped_DefaultGroup'}
    opened.pending[#opened.items],opened.committed[#opened.items]=0,0
    return opened
end
choices.mccStorageInstalled=nil
DMM.installStorage(choices)
local function reopen()
    local opened=choices.open({id='ModCoreControls',path=directory .. '/mod_settings.ini'})
    local at={}
    for i,item in ipairs(opened.items) do at[item.id]=i end
    return opened,at.MCC_actions_grouped_DefaultGroup,at.MCC_module_default_DefaultWheel
end
local mirrored,m,w=reopen()
assert(mirrored.pending[m]==2 and mirrored.committed[m]==2,'mirror loads the Default wheel')
mirrored.pending[m]=1
ok,why=mirrored:apply()
assert(ok,why)
assert(mirrored.committed[w]==1 and mirrored.committed[m]==1)
mirrored,m,w=reopen()
assert(mirrored.pending[m]==1 and mirrored.pending[w]==1,'mirror change persists to Default')
mirrored.pending[w]=2
assert(mirrored:apply() and mirrored.committed[m]==2,'source change reaches the mirror')
mirrored.pending[m],mirrored.pending[w]=1,1
assert(mirrored:apply() and mirrored.committed[w]==1,'matching changes are accepted')
mirrored.pending[m],mirrored.pending[w]=2,1
assert(mirrored:apply() and mirrored.committed[w]==2,'a mirror change wins over an unchanged source')
-- With two wheels, both rows can differ from their committed values only if
-- those values disagree; force that state to reach the conflict check.
mirrored.committed[m],mirrored.committed[w]=2,1
mirrored.pending[m],mirrored.pending[w]=1,2
local conflictOk,conflict=mirrored:apply()
assert(not conflictOk and conflict:find('different values',1,true),'conflicting changes are rejected')
assert(os.remove(directory .. '/config.ini'))
assert(os.execute('rmdir ' .. string.format('%q',directory)))
print('PASS DMM Apply validates the combined plan before persistence')
