local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local root = assert(source:match('^(.*)[/\\]tools[/\\][^/\\]+$')
    or (source:match('^tools[/\\][^/\\]+$') and '.'),
    'cannot locate ModCoreControls root')
local styles = assert(loadfile(root .. '/Scripts/ModCore/control_styles.lua'))()
table.sort(styles, function(left, right) return left.value < right.value end)
assert(styles[1].id == 'grouped' and styles[1].value == 0)
assert(styles[2].id == 'flat' and styles[2].value == 1)

local selector = {
    setting = 'AccessMethod',
    label = 'Control Layout',
    defaultStyle = 'grouped',
    description = 'Grouped uses a group key and shared slot keys. Flat gives each slot its own key.',
}
local sectionName = 'Actions & Quickslots'
local rows = {}
local config = {'[Controls]'}

local function section(name, data)
    rows[#rows + 1] = '[' .. name .. ']'
    local keys = {}
    for key, value in pairs(data) do
        if value ~= nil then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do rows[#rows + 1] = key .. '=' .. tostring(data[key]) end
    rows[#rows + 1] = ''
end

local function setting(name, kind, label, group, defaultValue, extra)
    local key = 'MCC_' .. name
    local data = {
        ConfigFile = 'config.ini', ConfigKey = key, ConfigSection = 'Controls',
        Default = defaultValue, Group = group, Id = key, Label = label, Type = kind,
    }
    for extraKey, value in pairs(extra or {}) do data[extraKey] = value end
    section('Setting.' .. key, data)
    config[#config + 1] = key .. '=' .. tostring(defaultValue)
    return key
end

local function values(items, key)
    local result = {}
    for index, item in ipairs(items) do result[index] = tostring(item[key]) end
    return table.concat(result, '|')
end

section('Mod', {
    Id = 'ModCoreControls', Name = 'Controls', Author = 'Jorge Pereira (kell)', Version = '0.1.1',
    Description = 'Choose Grouped or Flat Actions Layout and configure its controls.',
})
section('Category.' .. sectionName, {mcHeading = 0})
for styleIndex = #styles, 1, -1 do
    local style = styles[styleIndex]
    for _, menuSection in ipairs(style.sections) do
        section('Category.' .. menuSection.label, {
            VisibleWhen = 'MCC_' .. selector.setting,
            VisibleValues = style.value,
            mcHeading = 1,
            mcLevel = menuSection.level,
        })
    end
end

local defaultStyle
for _, style in ipairs(styles) do
    if style.id == selector.defaultStyle then defaultStyle = style end
end
assert(defaultStyle, 'default control style is missing')
setting(selector.setting, 'picker', selector.label, sectionName, defaultStyle.value, {
    PresetValues = values(styles, 'value'),
    PresetLabels = values(styles, 'label'),
    Description = selector.description,
    mcType = 'tab',
    mcLevel = 1,
})

local seenSettings = {}
for styleIndex = #styles, 1, -1 do
    local style = styles[styleIndex]
    for _, menuSection in ipairs(style.sections) do
        for _, control in ipairs(menuSection.controls) do
            assert(control.action or control.actions or control.actionGroup,
                'control action description required: ' .. tostring(control.id))
            local keyDefinition, modeDefinition = control.key, control.mode
            local modes = {}
            for _, option in ipairs(modeDefinition.options) do modes[option.id] = option end
            local defaultMode = assert(modes[modeDefinition.defaultMode],
                'default mode is not an option: ' .. control.id)
            assert(not seenSettings[keyDefinition.setting], 'duplicate setting: ' .. keyDefinition.setting)
            assert(not seenSettings[modeDefinition.setting], 'duplicate setting: ' .. modeDefinition.setting)
            seenSettings[keyDefinition.setting], seenSettings[modeDefinition.setting] = true, true

            local visible = {}
            if style.repeatVisibilityOnSettings then
                visible.VisibleWhen = 'MCC_' .. selector.setting
                visible.VisibleValues = style.value
            end
            if menuSection.controlLevel ~= nil then visible.mcLevel = menuSection.controlLevel end
            visible.Minimum, visible.Maximum, visible.Step = 0, 254, 1
            visible.mcType = 'keybind'
            local key = setting(keyDefinition.setting, 'integer', control.label,
                menuSection.label, keyDefinition.defaultValue, visible)

            local modeExtra = {}
            if style.repeatVisibilityOnSettings then
                modeExtra.VisibleWhen = 'MCC_' .. selector.setting
                modeExtra.VisibleValues = style.value
            end
            if menuSection.controlLevel ~= nil then modeExtra.mcLevel = menuSection.controlLevel end
            modeExtra.PresetValues = values(modeDefinition.options, 'value')
            modeExtra.PresetLabels = values(modeDefinition.options, 'label')
            modeExtra.mcType = 'tab'
            modeExtra.Pair = key
            setting(modeDefinition.setting, 'picker', control.label, menuSection.label,
                defaultMode.value, modeExtra)
        end
    end
end

local function write(path, content)
    local file = assert(io.open(path, 'wb'))
    assert(file:write(content))
    assert(file:close())
end

write(root .. '/mod_settings.ini', table.concat(rows, '\n'):gsub('\n+$', '') .. '\n')
write(root .. '/config.ini', table.concat(config, '\n') .. '\n')
