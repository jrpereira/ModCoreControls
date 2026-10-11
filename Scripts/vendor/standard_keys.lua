-- Vendored from ModCoreSettings (owner). Do not edit copies; change the source and re-vendor.
-- The keyboard keys a player bound to one of the game's Enhanced Input actions, read from
-- the Settings key profile. ModCoreSettings' key editor shows them for a row's
-- DefaultControl; a mod that binds them, such as ModCore Controls, copies this file
-- unchanged, so the keys a row shows are the keys that are bound.
--
-- Every function takes an environment e of live-object helpers:
--   valid(object), full(object) -> full name, path(object) -> path without the class,
--   property(object, name), name(FName or string) -> string,
--   each(container, callback): arrays call back (value, index), maps (key, value);
--     returns false when the container cannot be read,
--   actions() -> the live InputActions, profile() -> the player's key profile or nil.
local M={version=1}
-- Where the game keeps its own input actions.
M.GAME_INPUT='/Game/_Dawnwalker/Player/Input/'

function M.shortName(e,object)
    return (e.full(object) or ''):match('([^%.:/%s]+)$')
end

-- The one action among candidates: the only distinct one, or else the only one in the
-- game's input folder. Otherwise nil and why ('ambiguous: <n> actions'), or nil alone
-- when there are none.
function M.choose(e,candidates)
    local distinct,seen={},{}
    for _,action in ipairs(candidates) do
        local key=e.path(action) or action
        if not seen[key] then seen[key]=true;distinct[#distinct+1]=action end
    end
    if #distinct==1 then return distinct[1] end
    if #distinct==0 then return nil end
    local preferred
    for _,action in ipairs(distinct) do
        if (e.path(action) or ''):sub(1,#M.GAME_INPUT)==M.GAME_INPUT then
            if preferred then return nil,'ambiguous: '..#distinct..' actions' end
            preferred=action
        end
    end
    if preferred then return preferred end
    return nil,'ambiguous: '..#distinct..' actions'
end

-- The live action named actionName (its short name), or nil and why.
function M.action(e,actionName,candidates)
    local named={}
    for _,action in ipairs(candidates or e.actions()) do
        if e.valid(action) and M.shortName(e,action)==actionName then named[#named+1]=action end
    end
    local action,why=M.choose(e,named)
    if action then return action end
    if why then return nil,'standard input action '..why..': '..actionName end
    return nil,'standard input action unavailable: '..actionName
end

-- The sorted keyboard keys profile maps to action: entries that name the action itself,
-- or its mappable key settings' name. Gamepad keys and None are left out. nil and why
-- when the profile cannot be read.
function M.keys(e,profile,action)
    local actionPath=e.path(action)
    local mappingName=e.name(e.property(e.property(action,'PlayerMappableKeySettings'),'Name'))
    if mappingName=='' or mappingName=='None' then mappingName=nil end
    local found,readable={},true
    local walked=e.each(e.property(profile,'PlayerMappedKeys') or {},function(first,second)
        -- A map row arrives as (name, row); a plain list as (row, index).
        local row=type(second)=='number' and first or second
        if e.each(e.property(row,'Mappings') or {},function(entry)
            local associated=e.property(entry,'AssociatedInputAction')
            local matches=(associated~=nil and e.valid(associated) and e.path(associated)==actionPath)
                or (mappingName~=nil and e.name(e.property(entry,'MappingName'))==mappingName)
            if matches then
                local keyName=e.name(e.property(e.property(entry,'CurrentKey'),'KeyName'))
                if keyName and keyName~='' and keyName~='None' and not keyName:find('^Gamepad_') then
                    found[keyName]=true
                end
            end
        end)==false then readable=false end
    end)
    if walked==false or not readable then return nil,'key profile could not be read' end
    local result={}
    for keyName in pairs(found) do result[#result+1]=keyName end
    table.sort(result)
    return result
end

-- The keys bound to actionName, or nil and why: 'key profile unavailable' while the
-- profile is not loaded (worth asking again), 'standard control unavailable' when the
-- loaded profile maps no keyboard key to the action. The action is returned third.
function M.resolve(e,actionName)
    local profile=e.profile()
    if not e.valid(profile) then return nil,'key profile unavailable: '..actionName end
    local action,why=M.action(e,actionName)
    if not action then return nil,why end
    local keys,keysWhy=M.keys(e,profile,action)
    if not keys then return nil,keysWhy..': '..actionName,action end
    if #keys==0 then return nil,'standard control unavailable: '..actionName,action end
    return keys,nil,action
end

return M
