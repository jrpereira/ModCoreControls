package.path='Scripts/?.lua;'..package.path
local Gamepad=require('mc_gamepad')

local function text(value) return {ToString=function() return value end} end
local function action(name,description)
    return {IsValid=function() return true end,ActionDescription=text(description or ''),
        GetFName=function() return text(name) end}
end
local function list(values)
    return {ForEach=function(_,callback) for i,value in ipairs(values) do callback(i,value) end end}
end
local function map(pairs_)
    return {ForEach=function(_,callback) for _,pair in ipairs(pairs_) do callback(pair[1],pair[2]) end end}
end
local function key(name) return {KeyName=text(name)} end

local quickslot=action('IA_Quickslot_Left','Quickslot Left')
local dodge=action('IA_Dodge')
local context={IsValid=function() return true end,Mappings=list({
    {Key=key('Gamepad_DPad_Left'),Action=quickslot},
    {Key=key('Gamepad_FaceButton_Right'),Action=dodge},
    {Key=key('One'),Action=quickslot},
})}
local profile={IsValid=function() return true end,PlayerMappedKeys=map({{'row',{Mappings=list({
    {CurrentKey=key('Gamepad_DPad_Left'),AssociatedInputAction=quickslot},
    {CurrentKey=key('Gamepad_DPad_Left'),AssociatedInputAction=action('IA_Map','Map|Zoom')},
})}}})}
local settings={IsValid=function() return true end,GetCurrentKeyProfile=function() return profile end}
local objects={
    EnhancedInputLocalPlayerSubsystem={GetUserSettings=function() return settings end},
    EnhancedPlayerInput={AppliedInputContexts=map({{context,0}})},
}
local e={
    unwrap=function(value) return value end,
    valid=function(value) return value~=nil and (value.IsValid==nil or value:IsValid()) end,
    each=function(values,callback)
        if values then values:ForEach(function(k,v)
            if type(k)=='number' then callback(v) else callback(k,v) end
        end) end
    end,
    first=function(class) return objects[class] end,
}
local rows=Gamepad.read(e)
assert(#rows==#Gamepad.buttons,'every gamepad button is listed')
local byKey={}
for _,row in ipairs(rows) do byKey[row.key]=row end
assert(table.concat(byKey.Gamepad_DPad_Left.actions,',')=='Map Zoom,Quickslot Left',
    'actions from contexts and profile, deduplicated, sorted and menu-safe')
assert(byKey.Gamepad_FaceButton_Right.actions[1]=='Dodge','IA_ prefix dropped without a description')
assert(#byKey.Gamepad_DPad_Up.actions==0 and byKey.Gamepad_DPad_Up.label=='D-Pad Up')
assert(Gamepad.read({first=function() return nil end})==nil,'no player input: nothing to read')
print('PASS gamepad button assignments')
