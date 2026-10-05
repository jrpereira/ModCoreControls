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
local values=Menu.new(definition,{}).values
local wheel='MCC_module_default_DefaultWheel'
assert(values[wheel]==2)
local first=Config.encode('[Other]\nkeep=one\n',definition,values)
local changed={}
for id,value in pairs(values) do changed[id]=value end
changed[wheel]=1
local second=Config.encode(first,definition,changed)
local path=tmpname()
assert(os.remove(path))
local temporary,previous=path .. '.mcc-tmp',path .. '.mcc-previous'
local function write(name,content)
    local file=assert(io.open(name,'wb'))
    assert(file:write(content)); assert(file:close())
end
local function read(name)
    local file=io.open(name,'rb')
    if not file then return nil end
    local result=assert(file:read('*a')); assert(file:close()); return result
end
local function clear()
    os.remove(path);os.remove(temporary);os.remove(previous)
end
-- An unresolved transaction never blocks startup: the store opens on defaults,
-- leaves every file for review and refuses to save.
local function fails()
    local store=Config.open(path,definition)
    assert(tostring(store.recoveryError):find('unresolved',1,true),tostring(store.recoveryError))
    assert(Menu.new(definition,store.values).values[wheel]==2)
    local saved,why=pcall(store.save,store,changed)
    assert(not saved and tostring(why):find('reviewed',1,true),tostring(why))
end

clear()
assert(Menu.new(definition,Config.open(path,definition).values).values[wheel]==2)
write(path,first)
assert(Config.open(path,definition).values[wheel]==2)

clear();write(path,first);write(temporary,second)
assert(Config.open(path,definition).values[wheel]==2)
assert(read(path)==first and read(temporary)==nil)

clear();write(previous,first);write(temporary,second)
assert(Config.open(path,definition).values[wheel]==2)
assert(read(path)==first and read(previous)==nil and read(temporary)==nil)

clear();write(previous,first)
assert(Config.open(path,definition).values[wheel]==2)
assert(read(path)==first and read(previous)==nil)

clear();write(path,second);write(previous,first)
assert(Config.open(path,definition).values[wheel]==1)
assert(read(path)==second and read(previous)==nil)

clear();write(temporary,second);fails()
assert(read(temporary)==second and read(path)==nil)

clear();write(path,second);write(previous,first);write(temporary,second);fails()
assert(read(path)==second and read(previous)==first and read(temporary)==second)

-- An invalid saved value falls back to its default; the published file wins.
clear();write(path,'[ModCoreControls.module]\ndefault.DefaultWheel=9\n');write(previous,first)
assert(Menu.new(definition,Config.open(path,definition).values).values[wheel]==2)
assert(read(previous)==nil)
-- Repeated sections and keys keep the first value.
clear();write(path,'[ModCoreControls.module]\ndefault.DefaultWheel=1\n[ModCoreControls.module]\ndefault.DefaultWheel=2\n')
assert(Config.open(path,definition).values[wheel]==1)

clear();write(path,first)
local store=Config.open(path,definition)
local remove=os.remove
os.remove=function(name)
    if name==previous then return nil,'injected cleanup failure' end
    return remove(name)
end
local committed,warning=store:save(changed)
os.remove=remove
assert(committed and warning:find('cleanup pending',1,true))
assert(read(path)==second and read(previous)==first)
assert(Config.open(path,definition).values[wheel]==1)
assert(read(previous)==nil)

clear();write(path,first)
store=Config.open(path,definition)
local rename=os.rename
os.rename=function(from,to)
    if from==temporary and to==path then return nil,'injected publication failure' end
    return rename(from,to)
end
local published,problem=pcall(store.save,store,changed)
os.rename=rename
assert(not published and tostring(problem):find('publication failure',1,true))
assert(read(path)==first and read(temporary)==nil and read(previous)==nil)

store=Config.open(path,definition)
os.rename=function(from,to)
    if from==path and to==previous then return nil,'injected retirement failure' end
    return rename(from,to)
end
published,problem=pcall(store.save,store,changed)
os.rename=rename
assert(not published and tostring(problem):find('retirement failure',1,true))
assert(read(path)==first and read(temporary)==nil and read(previous)==nil)
clear()
print('PASS MCC config transaction recovery')

-- The Flat map was renamed Global: saved flat.* keys and map=flat migrate once on open.
local legacy=tmpname()
write(legacy,'[Other]\nflat.keep=1\n[ModCoreControls.actions]\nmap=flat\nflat.AbilitySlot1.key=74\nflat.AbilitySlot1.trigger=0\n')
local migrated=Config.open(legacy,definition)
assert(migrated.migrationError==nil,migrated.migrationError)
local slot
for _,item in ipairs(definition.settings) do
    if item.configKey=='global.AbilitySlot1' then slot=item.id end
end
-- Key-code lines predate keybind text; the binding keeps its default.
assert(slot and migrated.values[slot]==nil and Menu.new(definition,migrated.values).values[slot]=='none',
    'old key-code values are ignored')
local persisted=read(legacy)
assert(not persisted:find('map=',1,true) and persisted:find('global.AbilitySlot1.key=74',1,true)
    and not persisted:find('\nflat.AbilitySlot',1,true) and persisted:find('[Other]\nflat.keep=1',1,true),
    'migration must persist renamed keys and leave other sections untouched')
assert(Config.migrate(persisted)==persisted,'migration must be idempotent')
assert(os.remove(legacy))
print('PASS legacy Flat config migrates to Global')
