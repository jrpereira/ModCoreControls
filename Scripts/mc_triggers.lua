local M = {}

-- Convert a selected trigger, not the "Tap|Hold" list of available choices.
function M.toEnhancedInput(trigger, sustained)
    assert(trigger == 'Tap' or trigger == 'Hold', 'trigger must be Tap or Hold')
    assert(sustained == nil or type(sustained) == 'boolean', 'sustained must be a boolean')
    if trigger == 'Tap' then return 0 end
    return sustained and 2 or 1
end

return M
