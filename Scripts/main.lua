local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate KEC Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$') or
    (scripts == 'Scripts' and '.'), 'cannot locate KEC mod folder')
package.path = scripts .. '/?.lua;' .. package.path
local ok, err = pcall(function()
    local layouts = require('kec.layout_templates')
    ModCoreControls = {
        new = require('kec.core').new,
        newTopology = require('kec.topology').new,
        loadLayout = layouts.load,
        defaultLayout = function() return layouts.load(root .. '/templates/default.tpl') end,
        skillLayout = function() return layouts.load(root .. '/templates/skill_slots.tpl') end,
        flexiLayout = function() return layouts.load(root .. '/templates/flexi_slots.tpl') end,
        activeGroups = layouts.activeGroups,
        resolveLayout = layouts.resolve,
        flexiGroups = layouts.flexiGroups,
        readGameSlots = require('kec.game_slots').read,
        bridgeBackend = require('kec.bridge_backend').new,
        events = require('kec.events').shared(),
        subscribe = require('kec.event_transport').subscribe,
    }
    if type(ExecuteInGameThread) == 'function' then
        local function log(message)
            print('[ModCoreControls] ' .. tostring(message) .. '\n')
        end
        local category = {contexts={'combat','openworld'}, actions={
            {type='Ability',slot='Left'}, {type='Ability',slot='Top'},
            {type='Ability',slot='Right'}, {type='Ability',slot='Bottom'},
            {type='Consumable',slot='Left'}, {type='Consumable',slot='Top'},
            {type='Consumable',slot='Right'}, {type='Consumable',slot='Bottom'},
        }}
        local template = {name='Native Quickslots',category='player.quickslots',
            contexts=category.contexts}
        local host = require('kec.player_actions.ue4ss_host').new(
            ExecuteInGameThread, log, category)
        local service = require('kec.player_actions.quickslot_service').new()
        local function apply()
            local settings = require('kec.quickslot_config').read(root .. '/config.ini')
            settings.PrimaryWheel = 1
            local active, why = host:apply(template, settings, service)
            if not active then log('Quickslot controls pending: ' .. tostring(why)) end
        end
        ModCoreControls.quickslotHost = host
        if ModRef and type(FindAllOf) == 'function' then
            local Transport = require('kec.event_transport')
            ModCoreControls.events:setPublisher(Transport.publisher(function()
                local ok, controllers = pcall(FindAllOf, 'BP_PlayerController_C')
                if not ok or type(controllers) ~= 'table' then return nil end
                for _, controller in ipairs(controllers) do
                    local called, valid = pcall(function() return controller:IsValid() end)
                    if called and valid == true then return controller end
                end
            end))
        end
        apply()
        local mods = assert(root:match('^(.*)[/\\][^/\\]+$'), 'cannot locate Mods folder')
        package.path = mods .. '/_ModCore_Settings/Scripts/?.lua;' .. package.path
        local present, settingsApi = pcall(require, 'settings_api')
        if present and ModRef and type(RegisterConsoleCommandHandler) == 'function'
            and type(settingsApi.subscribe) == 'function' then
            settingsApi.subscribe('ModCoreControls', function()
                ExecuteInGameThread(function()
                    local refreshed, why = pcall(apply)
                    if not refreshed then log('Quickslot Apply failed: ' .. tostring(why)) end
                end)
            end)
        else
            log('Apply notifications unavailable; controls will load from config on restart.')
        end
    end
end)
if not ok then
    print('[ModCoreControls] startup failed: ' .. tostring(err) .. '\n')
else
    print('[ModCoreControls] 0.1.0 loaded; quickslot controls active independently of visual templates\n')
end
