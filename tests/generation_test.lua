package.path = 'Scripts/?.lua;Scripts/?/init.lua;' .. package.path
local Core = require('kec.core')
local Events = require('kec.events')
local function fixture()
    local installs, calls, deferred = {}, {}, {}
    local events = Events.new()
    local backend = {}
    function backend:install(_, emit)
        local installation = {emit=emit, closeOk=true}
        function installation:close() return self.closeOk, 'close failed' end
        installs[#installs + 1] = installation
        -- A backend may deliver synchronously while installing.
        assert(emit('dash', {}) == false)
        if self.failInstall then return nil, 'install failed' end
        return installation
    end
    local controls = Core.new({backend=backend, events=events})
    controls:registerAction({id='dash', label='Dash', execute=function(event, context)
        calls[#calls + 1] = {event=event, context=context}
        deferred[#deferred + 1] = function()
            return context == nil or context.isValidGeneration()
        end
        return 'delivered'
    end})
    controls:registerLayout({id='default', label='Default', bindings={
        dash={key='F10', trigger='Tap'},
    }})
    return controls, backend, installs, calls, deferred, events
end

-- Queued events and retained consumer work are revoked; rebinding cannot revive them.
do
    local c, _, installs, calls, deferred, events = fixture()
    local phases = 0
    events:subscribe('ControlActionTriggered', function() phases = phases + 1 end)
    assert(c:activate('combat'))
    local event = {key='F10'}
    assert(installs[1].emit('dash', event) == 'delivered')
    assert(calls[1].event == event and deferred[1]())
    assert(c:deactivate())
    assert(not deferred[1]())
    for _, phase in ipairs({'Started', 'Triggered', 'Completed', 'Canceled'}) do
        assert(installs[1].emit('dash', {phase=phase}) == false)
    end
    assert(#calls == 1 and phases == 1)
    assert(c:activate('combat'))
    assert(not deferred[1]())
    assert(installs[1].emit('dash', {}) == false)
    assert(installs[2].emit('dash', {}) == 'delivered')
    assert(c:configure('dash', {key='F11', trigger='Tap'}))
    assert(not deferred[2]())
    assert(installs[2].emit('dash', {}) == false)
    assert(installs[3].emit('dash', {}) == 'delivered')
    assert(deferred[3]())
end

-- Failed installation and retirement preserve old work and reject candidate work.
do
    local c, backend, installs, calls, deferred = fixture()
    assert(c:activate('combat'))
    assert(installs[1].emit('dash', {}) == 'delivered')
    backend.failInstall = true
    local ok, why = c:configure('dash', {key='F11', trigger='Tap'})
    assert(not ok and why == 'install failed')
    assert(c:plan()[1].key == 'F10' and deferred[1]())
    assert(installs[2].emit('dash', {}) == false)
    backend.failInstall = false
    installs[1].closeOk = false
    ok, why = c:activate('other')
    assert(not ok and why == 'close failed')
    assert(installs[3].emit('dash', {}) == false)
    assert(installs[1].emit('dash', {}) == 'delivered' and deferred[1]())
    ok, why = c:deactivate()
    assert(not ok and why == 'close failed' and deferred[1]())
    installs[1].closeOk = true
    assert(c:deactivate() and not deferred[1]())
    assert(c:deactivate())
end

-- Lifecycle listeners may retire a generation between phase emission and execution.
do
    local c, _, installs, calls, _, events = fixture()
    events:subscribe('ControlActionTriggered', function() assert(c:deactivate()) end)
    assert(c:activate('combat'))
    assert(installs[1].emit('dash', {}) == false)
    assert(#calls == 0)
    assert(c:dispatch('dash', {}) == 'delivered')
    assert(#calls == 1 and calls[1].context == nil)
end
print('KEC generation lifecycle passed')
