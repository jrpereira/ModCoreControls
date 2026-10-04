package.path='Scripts/?.lua;' .. package.path
local Menu,Config=require('mc_menu'),require('mc_config')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
local model=Menu.new(definition,{})
local actions=definition.sections[1]
assert(actions.id=='actions' and actions.maps[1].id=='default')
assert(definition.sections[2].id=='movement' and not definition.sections[2].selector)
local selector=actions.selector
model:set(selector.id,2)
local globalMap=actions.maps[3]
assert(globalMap.id=='global' and model.values[selector.id]==globalMap.value)
local binding=globalMap.groups[1].keys[1]
model:set(binding.key.id,74)
local encoded=Config.encode('[Other]\nsetting=unchanged\n',definition,model.values)
assert(encoded:find('[ModCoreControls.actions]\nmap=global\n',1,true))
assert(encoded:find('global.SlotAction1.key=74',1,true))
assert(encoded:find('[Other]\nsetting=unchanged',1,true))
assert(not encoded:find('MCC_Section',1,true))
assert(not encoded:find('[ModCoreControls.exploration]',1,true))
local reopened=Menu.new(definition,Config.decode(encoded,definition))
assert(reopened.values[selector.id]==globalMap.value and reopened.values[binding.key.id]==74)
assert(Config.encode(encoded,definition,reopened.values)==encoded)
assert(not pcall(Config.decode,'[ModCoreControls.actions]\nmap=unknown\n',definition))
assert(not pcall(Config.decode,'[ModCoreControls.actions]\nmap=global\nmap=grouped\n',definition))
assert(not pcall(Config.decode,'[ModCoreControls.actions]\nglobal.SlotAction1.key=255\n',definition))

local function declaration(changes)
    local key={id='One',name='One',trigger='Tap',default=49,
        action={type='selected',slot=1}}
    local map={id='custom',name='Custom',value=0,contexts={'exploration'},
        map={{name='Actions',keys={key}}}}
    if changes then changes(map,key) end
    return Menu.define({order={'actions'}},{maps={actions={custom=map}},order={actions={'custom'}}})
end
assert(declaration())
assert(not pcall(declaration,function(map) map.contexts={'unknown'} end))
assert(not pcall(declaration,function(_,key) key.default=3 end))
assert(not pcall(declaration,function(_,key) key.action={type='selected',slot=5} end))
assert(not pcall(declaration,function(map,key) map.map[1].keys[2]=key end))

local path=os.tmpname()
local file=assert(io.open(path,'wb')); file:write('[Other]\nkeep=1\n'); file:close()
local store=Config.open(path,definition)
reopened:apply(store)
local persisted=Config.open(path,definition)
assert(persisted.values[selector.id]==2)
file=assert(io.open(path,'ab')); file:write('; changed externally\n'); file:close()
assert(not pcall(persisted.save,persisted,reopened.values),'must reject concurrent config changes')
assert(os.remove(path))
print('PASS MCC map selection and INI persistence')
