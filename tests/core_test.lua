package.path = 'Scripts/?.lua;Scripts/?/init.lua;' .. package.path
local Core = require('mc.core')
local installs, closed, delivered = {}, 0, {}
local backend = {install=function(_, plan, emit)
    installs[#installs + 1] = plan
    if #plan == 1 and plan[1].key == 'Bad' then return nil, 'binding rejected' end
    delivered[#delivered + 1] = emit
    return {close=function() closed = closed + 1; return true end}
end}
local controls = Core.new({backend=backend})
controls:registerAction({id='skill.dash', label='Dash', execute=function(event)
    return 'dash:' .. event.key
end})
controls:registerAction({id='skill.parry', label='Parry', execute=function(event)
    return 'parry:' .. event.key
end})
controls:registerLayout({id='layout.direct', label='Direct', bindings={
    ['skill.dash']={key='F10', trigger='Tap'},
    ['skill.parry']={key='F11', trigger='Hold', context='combat'},
}})
controls:registerLayout({id='layout.compact', label='Compact', bindings={
    ['skill.dash']={key='F10', trigger='Hold'},
}})
assert(controls:selectedLayout() == 'layout.direct')
assert(#controls:plan(nil, 'openworld') == 1)
assert(#controls:plan(nil, 'combat') == 2)
assert(controls:activate('combat'))
assert(delivered[1]('skill.dash', {key='F10'}) == 'dash:F10')
assert(controls:selectLayout('layout.compact'))
assert(closed == 1 and installs[2][1].trigger == 'Hold')
local ok, why = controls:configure('skill.dash', {key='Bad', trigger='Tap'})
assert(not ok and why == 'binding rejected')
assert(controls:plan()[1].key == 'F10')
assert(controls:configure('skill.dash', false))
assert(#controls:plan() == 0)
assert(controls:deactivate())
local duplicate = pcall(function()
    controls:registerAction({id='skill.dash', label='Duplicate', execute=function() end})
end)
assert(not duplicate)
print('MCC action/layout core passed')
