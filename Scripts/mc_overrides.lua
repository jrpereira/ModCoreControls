-- Reversible chord gates for native Input Actions replaced by MCC mappings.
local M={}

function M.new(e)
    local marker=assert(e.marker,'override marker required')
    local api={}
    local ownedActions={}
    local function triggers(action)
        local result={}
        local walked=e.each(action.Triggers,function(first,second)
            local trigger=e.unwrap(first)
            if not e.valid(trigger) then trigger=e.unwrap(second) end
            if e.valid(trigger) then result[#result+1]=trigger end
        end)
        assert(walked~=false,'cannot inspect override triggers: ' .. tostring(e.path(action)))
        return result
    end
    local function owned(action,trigger)
        return e.valid(trigger) and e.path(trigger)==e.path(action) .. ':' .. marker
    end
    function api:apply(wanted,playerInput,targets)
        assert(type(wanted)=='table','override action set required')
        local inactive=next(wanted) and e.inactive() or nil
        if inactive then assert(e.valid(inactive),'override chord action unavailable') end
        local changes,snapshots,chords={},{},{}
        local candidates=targets or e.actions()
        -- An owned action that no longer exists took its chord with it.
        for path,action in pairs(ownedActions) do
            if not e.valid(action) then ownedActions[path]=nil end
        end
        local previousOwned={}
        for path,action in pairs(ownedActions) do previousOwned[path]=action end
        local ok,why=pcall(function()
            for _,action in ipairs(candidates) do
                if e.valid(action) then
                    local actionPath=e.path(action)
                    if wanted[actionPath] or ownedActions[actionPath] or targets then
                        local before,after,gate=triggers(action),{},nil
                        local changed=false
                        snapshots[action]=before
                        for _,trigger in ipairs(before) do
                            if owned(action,trigger) then
                                if wanted[actionPath] and not gate then
                                    gate=trigger;after[#after+1]=trigger
                                else changed=true end
                            else after[#after+1]=trigger end
                        end
                        if wanted[actionPath] then
                            local retained=e.construct(action,marker)
                            assert(e.valid(retained),'override chord construction failed: ' .. actionPath)
                            if gate then
                                assert(e.same(gate,retained),'override chord identity changed: ' .. actionPath)
                            else
                                gate=retained;after[#after+1]=gate;changed=true
                            end
                            local previous=e.chord(gate)
                            if not e.same(previous,inactive) then
                                chords[gate]=previous;e.setChord(gate,inactive);changed=true
                            end
                        end
                        if changed then e.setTriggers(action,after);changes[#changes+1]=action end
                        if wanted[actionPath] then ownedActions[actionPath]=action
                        elseif ownedActions[actionPath] then ownedActions[actionPath]=nil end
                    end
                end
            end
            if #changes>0 then assert(e.rebuild(playerInput,changes)~=false,'override rebuild rejected') end
        end)
        if not ok then
            for action,before in pairs(snapshots) do pcall(e.setTriggers,action,before) end
            for gate,previous in pairs(chords) do pcall(e.setChord,gate,previous) end
            pcall(e.rebuild,playerInput,changes)
            ownedActions=previousOwned
            error(why,0)
        end
        return true,#changes
    end
    function api:restoreAll(playerInput)
        local targets={}
        for _,action in pairs(ownedActions) do targets[#targets+1]=action end
        return self:apply({},playerInput,targets)
    end
    function api:hasOwners() return next(ownedActions)~=nil end
    return api
end

return M
