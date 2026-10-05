package.path='Scripts/?.lua;' .. package.path
-- os.tmpname always uses /tmp; honour TMPDIR so the suite runs in sandboxes too.
local function tmpname()
    local dir=os.getenv('TMPDIR')
    if not dir then return os.tmpname() end
    local path=dir:gsub('/+$','') .. '/mcc_' .. os.time() .. '_' .. math.random(1000000000)
    assert(io.open(path,'wb')):close()
    return path
end
local DMM=require('mc_dmm')
local directory=tmpname()
assert(os.remove(directory))
assert(os.execute('mkdir ' .. string.format('%q',directory)))

-- ModCoreSettings' page hooks call load() when the page opens and apply() with
-- every stored value by id plus the edited ones as {old=,new=}.
local committed
local function open() committed=DMM.load(directory) end
local function apply(edits)
    local values,changes={},{}
    for id,value in pairs(committed) do values[id]=value end
    for id,value in pairs(edits) do
        values[id]=value
        if committed[id]~=value then changes[id]={old=committed[id],new=value} end
    end
    local ok,saved,warning=pcall(DMM.apply,directory,values,changes)
    if ok then for id,value in pairs(saved) do committed[id]=value end end
    return ok,saved,warning
end
local function config()
    local file=io.open(directory .. '/config.ini','rb')
    if not file then return nil end
    local content=file:read('*a');file:close();return content
end

open()
assert(committed.MCC_actions_Map==nil,'the map picker is navigation, not a stored value')
-- Maps coexist: the same key in two maps is rejected like a duplicate in one.
local first,second='MCC_actions_grouped_QuickSlot1','MCC_actions_global_AbilitySlot2'
assert(committed[first]=='none' and committed[second]=='none','keybinds load as text')
local ok,why=apply({[first]='1|Tap',[second]='1|Tap'})
assert(not ok and tostring(why):find(second,1,true))
assert(config()==nil,'rejected Apply published a config')
ok,why=apply({[second]=3})
assert(not ok and tostring(why):find(second,1,true),'a key code is rejected by id')
local saved
ok,saved=apply({[first]='1|Hold'})
assert(ok,saved)
assert(saved[first]=='1|Hold' and config():find('grouped.QuickSlot1=1|Hold\n',1,true))
-- Number settings stay integers in the same file.
assert(config():find('default.DefaultWheel=2\n',1,true))

-- Default Group mirrors Default's Default wheel: it loads from that setting, a
-- change is saved there, and changing both to different values is rejected.
local schema=DMM.schema(require('mc_menu').define(require('mc_sections'),require('mc_maps')))
assert(schema:find('[Setting.MCC_actions_grouped_DefaultGroup]',1,true)
    and not schema:find('ConfigKey=grouped.DefaultGroup',1,true))
assert(schema:find('mcLabelWhen=MCC_actions_grouped_DefaultGroup\nmcLabels=1:Swap to Consumables;2:Swap to Abilities',1,true),
    'the swap key is labelled after the wheel other than Default')
assert(schema:find('Label=Swap to Abilities\n',1,true),'its static label names the wheel for the default setting')
-- Swap back to default shows its wheels as tabs.
assert(schema:match('%[Setting%.MCC_actions_grouped_DefaultGroup%]\n(.-)\n\n'):find('\nmcType=cycle$'))
-- Hold to Swap and the Swap key explain how they interact.
assert(schema:find('Description=Applies to the Toggle Quickslots key. If you bind Swap',1,true)
    and schema:find('Description=Tap swaps, and tapping again swaps back.',1,true))
assert(schema:find('Label=Swap back to default\n',1,true) and schema:find('Label=Activate Abilities\n',1,true)
    and schema:find('Label=Activate Consumables\n',1,true) and schema:find('[Category.actions.grouped.3]',1,true))
local m,w='MCC_actions_grouped_DefaultGroup','MCC_module_default_DefaultWheel'
open()
assert(committed[m]==2 and committed[w]==2,'mirror loads the Default wheel')
assert(apply({[m]=1}) and committed[w]==1 and committed[m]==1)
open()
assert(committed[m]==1 and committed[w]==1,'mirror change persists to Default')
assert(apply({[w]=2}) and committed[m]==2,'source change reaches the mirror')
assert(apply({[m]=1,[w]=1}) and committed[w]==1,'matching changes are accepted')
assert(apply({[m]=2}) and committed[w]==2,'a mirror change wins over an unchanged source')
-- With two wheels, both rows can change only from disagreeing committed values;
-- force that state to reach the conflict check.
committed[m],committed[w]=2,1
local conflictOk,conflict=apply({[m]=1,[w]=2})
assert(not conflictOk and tostring(conflict):find('different values',1,true),'conflicting changes are rejected')

-- A config changed since the page opened is refused, not overwritten.
local file=assert(io.open(directory .. '/config.ini','ab'));file:write('; edited elsewhere\n');file:close()
ok,why=apply({[first]='2|Tap'})
assert(not ok and tostring(why):find('changed externally',1,true))
assert(not config():find('2|Tap',1,true))
assert(os.remove(directory .. '/config.ini'))
assert(os.execute('rmdir ' .. string.format('%q',directory)))
print('PASS DMM Apply validates the combined plan before persistence')
