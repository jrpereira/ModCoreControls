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
local globalKeys=0
for _,group in ipairs(globalMap.groups) do
    for _,key in ipairs(group.keys) do assert(key.optional,'every Global key is optional: '..key.id);globalKeys=globalKeys+1 end
end
assert(globalKeys==8)
local binding=globalMap.groups[1].keys[1]
local setting=binding.setting
-- A binding is one setting holding '<FKey>|<trigger>' or 'none'.
assert(setting.kind=='keybind' and setting.default=='none' and setting.labels[1]=='Tap' and setting.labels[2]=='Hold')
assert(not pcall(model.set,model,setting.id,74),'key codes are not keybind values')
assert(not pcall(model.set,model,setting.id,'J|Push'),'only declared triggers')
model:set(setting.id,'J|Hold')
local encoded=Config.encode('[Other]\nsetting=unchanged\n',definition,model.values)
assert(not encoded:find('map=',1,true))
assert(encoded:find('global.AbilitySlot1=J|Hold',1,true))
assert(encoded:find('grouped.QuickSlot1=none',1,true),'every map is stored together')
assert(encoded:find('[Other]\nsetting=unchanged',1,true))
assert(not encoded:find('MCC_Section',1,true))
assert(not encoded:find('[ModCoreControls.exploration]',1,true))
local reopened=Menu.new(definition,Config.decode(encoded,definition))
assert(reopened.values[setting.id]=='J|Hold')
assert(Config.encode(encoded,definition,reopened.values)==encoded)
-- Stored text is read leniently: a bare key takes the first declared trigger,
-- 'default' the declared binding, and an unreadable value falls back to it. A letter
-- key reads as the engine's upper-case name, and excluded keys match in any case.
local swap=assert(definition.byId.MCC_actions_grouped_GroupFocus2,'Swap to <wheel> setting')
assert(swap.labels[1]=='Hold' and Menu.keybind(swap,'LeftAlt')=='LeftAlt|Hold',
    'Swap to <wheel> lists Hold first, so a bare key defaults to Hold')
for raw,expected in pairs({J='J|Tap',['j|hold']='J|Hold',default='none',['0']='none',['0|Hold']='0|Hold',
    One='1|Tap',['Left Alt']='none',['F|Push']='none',['escape|Tap']='none',
    ['gamepad_FaceButton_Bottom']='none'}) do
    local read=Config.decode('[ModCoreControls.actions]\nglobal.AbilitySlot1='..raw..'\n',definition)
    assert(Menu.new(definition,read).values[setting.id]==expected,raw)
end
-- Old key-code and trigger lines are ignored; the binding keeps its default.
assert(Config.decode('[ModCoreControls.actions]\nglobal.AbilitySlot1.key=49\nglobal.AbilitySlot1.trigger=1\n',definition)[setting.id]==nil)
-- A repeated key keeps its first value; an invalid numeric value falls back to its default.
assert(Config.decode('[ModCoreControls.actions]\nglobal.AbilitySlot1=J\nglobal.AbilitySlot1=K\n',
    definition)[setting.id]=='J|Tap')
assert(Config.decode('[ModCoreControls.module]\ndefault.DefaultWheel=7\n',definition)
    .MCC_module_default_DefaultWheel==nil)

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
assert(values[setting.id]==nil and values[actions.maps[1].groups[1].keys[1].setting.id]==nil,
    'migrated key-code lines are not keybind values')
assert(Config.migrate('[ModCoreControls.actions]\nmap=grouped\nglobal.AbilitySlot1.key=50\ngrouped.QuickSlot1.key=49\n')
    =='[ModCoreControls.actions]\ngrouped.QuickSlot1.key=49\n')
assert(Config.migrate('[ModCoreControls.actions]\nadvanced.AdvancedSlot1.key=49\ndefault.HoldSwap=1\n')
    =='[ModCoreControls.actions]\n[ModCoreControls.module]\ndefault.HoldSwap=1\n',
    'removed maps go even without a map choice; Default moves to Module')
-- Default's lines join an existing Module section; a line already there wins.
assert(Config.migrate('[ModCoreControls.module]\ndefault.HoldSwap=0\n[ModCoreControls.actions]\ndefault.HoldSwap=1\ndefault.DefaultWheel=1\n')
    =='[ModCoreControls.module]\ndefault.HoldSwap=0\ndefault.DefaultWheel=1\n[ModCoreControls.actions]\n')

local function declaration(changes)
    local key={id='One',name='One',type='keybind',default='One',
        params={trigger='Tap',action={type='selected',slot=1}}}
    local map={id='custom',name='Custom',value=0,contexts={'exploration'},
        settings={{id='Wheel',name='Wheel',type='picker',default=1,params={values={1,2},labels={'A','B'}}}},
        map={{name='Actions',settings={key}}}}
    if changes then changes(map,key) end
    return Menu.define({order={'actions'}},{maps={actions={custom=map}},order={actions={'custom'}}})
end
assert(declaration())
assert(not pcall(declaration,function(map) map.contexts={'unknown'} end))
assert(not pcall(declaration,function(_,key) key.default=3 end))
assert(not pcall(declaration,function(_,key) key.params.action={type='selected',slot=5} end))
assert(not pcall(declaration,function(map,key) map.map[1].settings[2]=key end))
-- Every setting has a type; a type's own arguments sit in params, nowhere else.
assert(not pcall(declaration,function(_,key) key.type=nil end),'type is required')
assert(not pcall(declaration,function(_,key) key.trigger='Tap' end),'keybind arguments belong in params')
assert(not pcall(declaration,function(_,key) key.params.values={1} end),'params are checked per type')
assert(not pcall(declaration,function(map) map.settings[1].type='keybind' end),'map settings are pickers')
assert(not pcall(declaration,function(map) map.settings[1].values={1,2} end),'picker arguments belong in params')
assert(not pcall(declaration,function(map) map.map[1].keys={} end),'groups list settings only')
-- A group's rows follow its declared order: a mirror may sit between keybinds.
local ordered=declaration(function(map,key)
    local two={id='Two',name='Two',type='keybind',default='Two',params={trigger='Tap',action={type='selected',slot=2}}}
    map.map[1].settings={key,{id='Shown',name='Shown',type='mirror',params={map='custom',setting='Wheel'}},two}
end)
local group=ordered.sections[1].maps[1].groups[1]
assert(#group.items==3 and group.items[1].binding.id=='One' and group.items[2].mirror.name=='Shown'
    and group.items[3].binding.id=='Two' and #group.keys==2 and #group.settings==1)

local path=tmpname()
local file=assert(io.open(path,'wb')); file:write('[Other]\nkeep=1\n'); file:close()
local store=Config.open(path,definition)
reopened:apply(store)
local persisted=Config.open(path,definition)
assert(persisted.values[setting.id]=='J|Hold')
file=assert(io.open(path,'ab')); file:write('; changed externally\n'); file:close()
assert(not pcall(persisted.save,persisted,reopened.values),'must reject concurrent config changes')
assert(os.remove(path))
print('PASS MCC map selection and INI persistence')

-- Bindings whose ids differ only in punctuation would share one generated Input
-- Action, so the definition rejects them.
do
    local function key(id) return {id=id,name=id,type='keybind',params={trigger='Tap',
        action={type='ability',slot=1},optional=true}} end
    local function map(id,value,binding) return {id=id,name=id,value=value,contexts={'exploration'},
        map={{name='Keys',settings={key(binding)}}}} end
    local registry={order={'actions'},sections={}}
    local maps={maps={actions={a=map('a',1,'b_c'),a_b=map('a_b',2,'c')}},order={actions={'a','a_b'}}}
    local ok,why=pcall(Menu.define,registry,maps)
    assert(not ok and tostring(why):find('would share the Input Action IA_MCC_a_b_c',1,true),tostring(why))
    maps.maps.actions.a_b=map('a_b',2,'d')
    assert(Menu.define(registry,maps),'distinct names are accepted')
end
print('PASS colliding generated Input Action names are rejected')
