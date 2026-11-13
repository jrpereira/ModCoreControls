package.path='Scripts/?.lua;Scripts/vendor/?.lua;'..package.path
local HoldMarks=require('mc_hold_marks')

-- A HUD with both wheels; each key sits in its wheel's overlay.
local function widget(path,fields)
    local value=fields or {}
    value.path=path;value.alive=true
    return value
end
local function newHud(id)
    local hud=widget('/HUD'..id)
    for kind,fields in pairs({ability={'WBP_AA_Quickslots','WBP_AA_Quickslots_Bindings'},
        consumable={'WBP_HUD_Quickslots','WBP_HUD_Quickslots_Bindings'}}) do
        local overlay=widget(hud.path..'.'..kind..'.Overlay',{children={}})
        local bindings=widget(hud.path..'.'..fields[2])
        for index,position in ipairs({'Left','Top','Right','Bottom'}) do
            local key=widget(bindings.path..'.'..position,{parent=overlay,
                placement={x=index*100,y=-50,scaleX=.9,scaleY=.9,visibility=4,opacity=1}})
            bindings[position]=key
            overlay.children[#overlay.children+1]=key
        end
        hud[fields[1]]=widget(hud.path..'.'..fields[1],{[fields[2]]=bindings})
    end
    return hud
end
local hud=newHud(1)
local created,applied,removed=0,0,0
local e={
    valid=function(value) return type(value)=='table' and value.alive==true end,
    path=function(value) return value.path end,
    property=function(object,name) return object and object[name] end,
    hud=function() return hud end,
    parent=function(value) return value.parent end,
    find=function(parent,name)
        for _,child in ipairs(parent.children) do if child.name==name and child.alive then return child end end
    end,
    create=function(parent,name)
        created=created+1
        local mark=widget(parent.path..'.'..name,{name=name,parent=parent})
        parent.children[#parent.children+1]=mark
        return mark
    end,
    placement=function(key)
        local copy={}
        for field,value in pairs(key.placement) do copy[field]=value end
        return copy
    end,
    apply=function(mark,placement) applied=applied+1;mark.placement=placement end,
    remove=function(mark) removed=removed+1;mark.alive=false end,
}
local marks=HoldMarks.new(e)
local function mark(kind,position)
    local wheel=kind=='ability' and hud.WBP_AA_Quickslots.WBP_AA_Quickslots_Bindings
        or hud.WBP_HUD_Quickslots.WBP_HUD_Quickslots_Bindings
    return e.find(wheel[position].parent,HoldMarks.name(kind,position)),wheel[position]
end
local plan={bindings={
    {id='grouped.QuickSlot1',keyName='One',mode=1,action={type='selected',slot=1}},
    {id='global.ConsumableSlot4',keyName='Q',mode=1,action={type='consumable',slot=4}},
    {id='global.AbilitySlot2',keyName='E',mode=0,action={type='ability',slot=2}},
}}

-- Only keys set to Hold get a mark, placed where their key is.
marks:refresh(plan)
assert(created==3,'a grouped Hold key marks both wheels, a Global one its own: '..created)
local consumable,key=mark('consumable','Bottom')
assert(consumable and consumable.placement.x==key.placement.x and consumable.placement.scaleX==.9)
assert(mark('ability','Left') and mark('consumable','Left') and not mark('ability','Top'),
    'a Tap key gets no mark')

-- Unchanged placements are not written again.
local before=applied
marks:refresh(plan)
marks:place()
assert(applied==before and created==3,'nothing moved, nothing written')

-- A layout pass moved a key: place copies it to its mark.
key.placement.x=999;key.placement.visibility=1
marks:place()
assert(applied==before+1 and consumable.placement.x==999 and consumable.placement.visibility==1)

-- A key changed to Tap loses its mark.
plan.bindings[2].mode=0
marks:refresh(plan)
assert(not mark('consumable','Bottom') and removed==1)
plan.bindings[2].mode=1

-- A new Lua state finds the marks of the earlier one by name and reuses them.
local again=HoldMarks.new(e)
again:refresh(plan)
assert(created==4,'only the removed mark is created again: '..created)

-- A Hold key changed to Tap is cleaned up even when an earlier state made its mark.
plan.bindings[1].mode=0
local fresh=HoldMarks.new(e)
fresh:refresh(plan)
assert(not mark('ability','Left') and not mark('consumable','Left'),'stale marks are removed')
plan.bindings[1].mode=1

-- Clear removes every mark.
again:refresh(plan)
again:clear()
for _,kind in ipairs({'ability','consumable'}) do
    for _,position in ipairs({'Left','Top','Right','Bottom'}) do
        assert(not mark(kind,position),'clear leaves no mark: '..kind..' '..position)
    end
end

-- A new HUD (a save load) gets its own marks; the old HUD's are forgotten.
again:refresh(plan)
local old=mark('consumable','Bottom')
hud=newHud(2)
again:refresh(plan)
assert(mark('consumable','Bottom') and mark('consumable','Bottom')~=old,'the new HUD is marked')
assert(not old.alive,'the old HUD mark is dropped')

-- A mark that cannot be created skips only itself.
hud=newHud(3)
local create=e.create
e.create=function(parent,name)
    if name:find('ability',1,true) then error('construct failed') end
    return create(parent,name)
end
local failing=HoldMarks.new(e)
failing:refresh(plan)
assert(mark('consumable','Bottom') and not mark('ability','Left'))
e.create=create

-- Without a HUD nothing is marked and nothing fails.
hud=nil
assert(HoldMarks.new(e):refresh(plan) and HoldMarks.new(e):place()==false)
print('PASS Hold marks follow Hold keys and their placement')
