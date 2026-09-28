package.path = 'Scripts/?.lua;' .. package.path
local Config = require('mcc.quickslot_config')
local values = {}
for line in io.lines('config.ini') do
    local key, raw = line:match('^(MCC_[%w_]+)=(%-?%d+)$')
    if key then values[key] = tonumber(raw) end
end
local grouped = Config.decode(values)
assert(grouped.access == 1)
assert(grouped.groups['1'].mode == -2 and grouped.groups['2'].mode == 2)
assert(grouped.groups['2'].key == 164 and grouped.shared[1].key == 49)
assert(grouped.assignments.flat[5] == 5)
values.MCC_AccessMethod = 1
local flat = Config.decode(values)
assert(flat.access == 0 and flat.direct['2'][1].key == 53
    and flat.direct['2'][4].key == 56)
assert(flat.preview.key == 0 and flat.preview.mode == 2)
values.MCC_SlotFlatPreview = 80
values.MCC_SlotFlatPreviewMode = 2
assert(Config.decode(values).preview.key == 80 and Config.decode(values).preview.mode == 2)
values.MCC_SlotFlatPreviewMode = 1
assert(not pcall(Config.decode, values), 'preview accepts only Tap or Hold')
values.MCC_SlotFlatPreviewMode = 0
values.MCC_SlotFlatPreview = 0
values.MCC_AccessMethod = 2
assert(not pcall(Config.decode, values), 'unsupported access methods must fail')
values.MCC_AccessMethod = 0
values.MCC_Group1Mode = -1
assert(not pcall(Config.decode, values), 'retired group modes must fail')
values.MCC_Group1Mode = -2
assert(Config.decode(values).groups['2'].mode == 2)
values.MCC_Group2Mode = 0
assert(Config.decode(values).groups['2'].mode == 0)
values.MCC_Group2Mode = 1
assert(not pcall(Config.decode, values), 'Grouped Alternative accepts only Tap or Hold')
values.MCC_Group2Mode = 2
print('MCC menu config accepts current Grouped and Flat settings only')
