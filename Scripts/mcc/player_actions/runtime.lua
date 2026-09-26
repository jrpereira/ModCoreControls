-- Coordinates generated mappings with reversible suppression of the former
-- MCC actions. The caller passes ready=true only after it has bound callbacks
-- for every generated action; this prevents a partial cutover from stranding
-- player input.
local InputContext = require('mcc.player_actions.input_context')
local Gates = require('mcc.player_actions.action_gates')

return function(e)
    e.input.category = e.category
    local input = InputContext(e.input)
    local native = {}
    local function discoverNative()
        local resolved=e.resolveAll and e.resolveAll(e.nativeTargets) or nil
        local current={}
        for index, name in ipairs(e.nativeTargets) do
            local action=resolved and resolved[name] or (not resolved and e.resolve(name))
            if e.valid(action) then current[#current+1]=action
            elseif index <= (e.nativeTargets.requiredCount or #e.nativeTargets) then
                return nil,'native quickslot action unavailable: '..name
            end
        end
        return current
    end
    local gates = Gates({
        marker = 'MCC_NativeActionGate', valid = e.valid, path = e.path, unwrap = e.unwrap,
        same = e.same, each = e.each, actions = function() return native end,
        retainInactive = e.retainInactive, construct = e.constructGate,
        chord = e.chord, setChord = e.setChord, setTriggers = e.setTriggers, rebuild = e.rebuild,
    })
    local api = {}
    function api:prepare(template, settings)
        return input:configure(template, settings)
    end
    function api:commit(kind, subsystem, nativePriority)
        input:attach(kind, subsystem, nativePriority)
        local ok, why = pcall(function() self:ready() end)
        if not ok then
            input:detach(kind)
            pcall(function() gates:restoreAll() end)
            error(why, 0)
        end
        self.active = self.active or {}
        self.active[kind] = true
        return true
    end
    function api:activate(template, settings, subsystem, kind, nativePriority, ready)
        local actions, plan = self:prepare(template, settings)
        if ready ~= true then return actions, plan, 'bindings_pending' end
        self:commit(kind, subsystem, nativePriority)
        return actions, plan, 'applied'
    end
    function api:ready()
        local current,why=discoverNative()
        if not current then error(why,0) end
        local changed=#current~=#native
        if not changed then
            for index,action in ipairs(current) do
                if not e.valid(native[index]) or not e.same(action,native[index]) then
                    changed=true; break
                end
            end
        end
        if changed and #native>0 then gates:restoreAll() end
        native=current
        gates:update(function() return true end)
        return true
    end
    function api:hasMapping(kind,playerInput)
        return input:hasMapping(kind,playerInput)
    end
    function api:deactivate(kind)
        input:detach(kind)
        self.active = self.active or {}
        self.active[kind] = nil
        if next(self.active) == nil then gates:restoreAll() end
        return true
    end
    return api
end
