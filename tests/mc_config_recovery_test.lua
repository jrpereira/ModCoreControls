package.path='Scripts/?.lua;' .. package.path
local Menu,Config=require('mc_menu'),require('mc_config')
local definition=Menu.define(require('mc_sections'),require('mc_maps'))
local values=Menu.new(definition,{}).values
local first=Config.encode('[Other]\nkeep=one\n',definition,values)
local changed={}
for id,value in pairs(values) do changed[id]=value end
changed.MCC_actions_Map=1
local second=Config.encode(first,definition,changed)
local path=os.tmpname()
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
local function fails()
    local ok,why=pcall(Config.open,path,definition)
    assert(not ok and tostring(why):find('unresolved',1,true),tostring(why))
end

clear()
assert(Menu.new(definition,Config.open(path,definition).values).values.MCC_actions_Map==0)
write(path,first)
assert(Config.open(path,definition).values.MCC_actions_Map==0)

clear();write(path,first);write(temporary,second)
assert(Config.open(path,definition).values.MCC_actions_Map==0)
assert(read(path)==first and read(temporary)==nil)

clear();write(previous,first);write(temporary,second)
assert(Config.open(path,definition).values.MCC_actions_Map==0)
assert(read(path)==first and read(previous)==nil and read(temporary)==nil)

clear();write(previous,first)
assert(Config.open(path,definition).values.MCC_actions_Map==0)
assert(read(path)==first and read(previous)==nil)

clear();write(path,second);write(previous,first)
assert(Config.open(path,definition).values.MCC_actions_Map==1)
assert(read(path)==second and read(previous)==nil)

clear();write(temporary,second);fails()
assert(read(temporary)==second and read(path)==nil)

clear();write(path,second);write(previous,first);write(temporary,second);fails()
assert(read(path)==second and read(previous)==first and read(temporary)==second)

clear();write(path,'[ModCoreControls.actions]\nmap=corrupt\n');write(previous,first);fails()
assert(read(previous)==first)

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
assert(Config.open(path,definition).values.MCC_actions_Map==1)
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
