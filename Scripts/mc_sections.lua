local M = { sections = {}, order = {}, sealed = false }

function M.addSection(section, description)
    assert(not M.sealed, 'section registration closed after definition')
    assert(type(section) == 'string' and section:match('%S'), 'section must be a non-empty string')
    assert(type(description) == 'string', 'description must be a string')
    assert(M.sections[section] == nil, 'section already exists: ' .. section)
    local entry = { description = description, sets = {} }
    M.sections[section] = entry
    M.order[#M.order + 1] = section
    return entry
end

function M.seal() M.sealed=true end

for _, section in ipairs({ 'actions', 'movement', 'system' }) do
    M.addSection(section, '')
end

return M
