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
local first=indices.MCC_actions_grouped_FixedSlot1_Key
local second=indices.MCC_actions_grouped_FixedSlot2_Key
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
assert(os.remove(directory .. '/config.ini'))
assert(os.execute('rmdir ' .. string.format('%q',directory)))
print('PASS DMM Apply validates selected plan before persistence')
