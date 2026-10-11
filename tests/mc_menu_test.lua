package.path='Scripts/?.lua;Scripts/vendor/?.lua;' .. package.path
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

-- Retired maps and keys are not migrated: unknown lines are ignored and kept.
local retired='[Other]\nkeep=1\n[ModCoreControls.actions]\nmap=flat\nflat.AbilitySlot1=J\nadvanced.AdvancedSlot1=K\n'
local values=Config.decode(retired,definition)
assert(next(values)==nil,'retired lines decode to nothing')
local kept=Config.encode(retired,definition,Menu.new(definition,{}).values)
assert(kept:find('flat.AbilitySlot1=J',1,true) and kept:find('[Other]\nkeep=1',1,true),'saving keeps unknown lines')

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
-- Focus group 3 has no runtime target yet: only an inactive key may name it.
assert(not pcall(declaration,function(_,key) key.params.action={type='focus',group=3} end),
    'an active key cannot focus group 3')
assert(declaration(function(_,key) key.params.action={type='focus',group=3};key.params.inactive=true end),
    'an inactive key may declare group 3')
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
