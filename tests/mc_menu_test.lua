package.path='Scripts/?.lua;' .. package.path
-- os.tmpname always uses /tmp; honour TMPDIR so the suite runs in sandboxes too.
local function tmpname()
    local dir=os.getenv('TMPDIR')
    if not dir then return os.tmpname() end
    local path=dir:gsub('/+$','') .. '/mcc_' .. os.time() .. '_' .. math.random(1000000000)
    assert(io.open(path,'wb')):close()
    return path
end
local Menu,Config=require('mc_menu'),require('mc_config')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
local model=Menu.new(definition,{})
local module,actions=definition.sections[1],definition.sections[2]
assert(module.id=='module' and module.maps[1].id=='default' and #module.maps==1)
assert(actions.id=='actions' and actions.maps[1].id=='grouped')
assert(definition.sections[3].id=='movement' and not definition.sections[3].selector)
local selector=actions.selector
-- The map picker only navigates between coexisting maps; it is never stored.
assert(selector.navigation and not definition.byId[selector.id] and model.values[selector.id]==nil)
assert(not pcall(model.set,model,selector.id,2))
local globalMap=actions.maps[2]
assert(globalMap.id=='global' and #actions.maps==2)
local binding=globalMap.groups[1].keys[1]
model:set(binding.key.id,74)
local encoded=Config.encode('[Other]\nsetting=unchanged\n',definition,model.values)
assert(not encoded:find('map=',1,true))
assert(encoded:find('global.AbilitySlot1.key=74',1,true))
assert(encoded:find('grouped.QuickSlot1.key=0',1,true),'every map is stored together')
assert(encoded:find('[Other]\nsetting=unchanged',1,true))
assert(not encoded:find('MCC_Section',1,true))
assert(not encoded:find('[ModCoreControls.exploration]',1,true))
local reopened=Menu.new(definition,Config.decode(encoded,definition))
assert(reopened.values[binding.key.id]==74)
assert(Config.encode(encoded,definition,reopened.values)==encoded)
assert(not pcall(Config.decode,'[ModCoreControls.actions]\nglobal.AbilitySlot1.key=255\n',definition))
assert(not pcall(Config.decode,
    '[ModCoreControls.actions]\nglobal.AbilitySlot1.key=49\nglobal.AbilitySlot1.key=50\n',definition))

-- Maps were alternatives chosen by map=<ID>. Migration drops the choice and the
-- entries of every map it did not select; Default is the base map and stays.
-- Advanced and Global's Show Controls key were removed.
local legacy=table.concat({'[Other]','keep=1','[ModCoreControls.actions]','map=flat',
    'default.DefaultWheel=1','grouped.QuickSlot1.key=49','flat.AbilitySlot1.key=50 ; mine',
    'global.FixedGroupFocus2.key=0','advanced.AdvancedSlot1.key=51',''},'\n')
local migrated=Config.migrate(legacy)
assert(migrated==table.concat({'[Other]','keep=1','[ModCoreControls.actions]',
    'global.AbilitySlot1.key=50 ; mine','[ModCoreControls.module]','default.DefaultWheel=1',''},'\n'),migrated)
assert(Config.migrate(migrated)==migrated,'migration is applied once')
local values=Config.decode(legacy,definition)
assert(values[binding.key.id]==50 and values[actions.maps[1].groups[1].keys[1].key.id]==nil)
assert(Config.migrate('[ModCoreControls.actions]\nmap=grouped\nglobal.AbilitySlot1.key=50\ngrouped.QuickSlot1.key=49\n')
    =='[ModCoreControls.actions]\ngrouped.QuickSlot1.key=49\n')
assert(Config.migrate('[ModCoreControls.actions]\nadvanced.AdvancedSlot1.key=49\ndefault.HoldSwap=1\n')
    =='[ModCoreControls.actions]\n[ModCoreControls.module]\ndefault.HoldSwap=1\n',
    'removed maps go even without a map choice; Default moves to Module')
-- Default's lines join an existing Module section; a line already there wins.
assert(Config.migrate('[ModCoreControls.module]\ndefault.HoldSwap=0\n[ModCoreControls.actions]\ndefault.HoldSwap=1\ndefault.DefaultWheel=1\n')
    =='[ModCoreControls.module]\ndefault.HoldSwap=0\ndefault.DefaultWheel=1\n[ModCoreControls.actions]\n')

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

local path=tmpname()
local file=assert(io.open(path,'wb')); file:write('[Other]\nkeep=1\n'); file:close()
local store=Config.open(path,definition)
reopened:apply(store)
local persisted=Config.open(path,definition)
assert(persisted.values[binding.key.id]==74)
file=assert(io.open(path,'ab')); file:write('; changed externally\n'); file:close()
assert(not pcall(persisted.save,persisted,reopened.values),'must reject concurrent config changes')
assert(os.remove(path))
print('PASS MCC map selection and INI persistence')
