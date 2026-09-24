package.path = 'Scripts/?.lua;' .. package.path
local Config = require('kec.quickslot_config')
local values = {}
for line in io.lines('config.ini') do
    local key, raw = line:match('^(KEC_[%w_]+)=(%-?%d+)$')
    if key then values[key] = tonumber(raw) end
end
local grouped = Config.decode(values)
assert(grouped.access == 1)
assert(grouped.groups['1'].mode == -1 and grouped.groups['2'].key == 164)
assert(grouped.shared[1].key == 49)
assert(grouped.direct['1'][1].activateKey == 0)
values.KEC_Flat1ActivateKey = 164
assert(Config.decode(values).direct['1'][1].activateKey == 164)
values.KEC_Flat1ActivateKey = 0
assert(grouped.assignments.flat[5] == 5)
assert(grouped.assignments.advanced['2'][4] == 8)
values.KEC_AccessMethod = 1
assert(Config.decode(values).access == 0)
values.KEC_AccessMethod = 2
assert(Config.decode(values).access == 2)
values.KEC_Flat1Action = 9 -- retired key in an older config is ignored
assert(Config.decode(values).assignments.flat[1] == 1)
print('KEC menu config derives directional assignments for Grouped, Flat, and Advanced')
