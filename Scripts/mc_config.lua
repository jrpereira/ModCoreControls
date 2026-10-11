-- Shared persistence: [ModCoreControls.<section>], numeric keys/triggers.
local M = {}
local function lines(content)
    local out={}
    -- A UTF-8 byte order mark would hide the first section heading.
    content=content:gsub('^\239\187\191','')
    for line in (content:gsub('\r\n','\n'):gsub('\r','\n') .. '\n'):gmatch('(.-)\n') do out[#out+1]=line end
    if out[#out]=='' then table.remove(out) end
    return out
end
local function index(definition)
    local sections,order={},{}
    for _,item in ipairs(definition.settings) do
        if not sections[item.configSection] then sections[item.configSection]={}; order[#order+1]=item.configSection end
        assert(not sections[item.configSection][item.configKey],'duplicate config address')
        sections[item.configSection][item.configKey]=item
    end
    return sections,order
end
-- Configuration never prevents startup: an unreadable or invalid value is left out,
-- so its default applies, and a repeated key keeps its first value.
function M.decode(content,definition)
    local sections=index(definition)
    local values,section={},nil
    for _,line in ipairs(lines(content)) do
        local heading=line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then
            section=heading
        elseif sections[section] then
            local key,raw=line:match('^%s*([^=;#]-)%s*=%s*([^;#]*)')
            local item=key and sections[section][key]
            if item and values[item.id]==nil then
                raw=raw:match('^%s*(.-)%s*$')
                local value
                if item.kind=='keybind' then
                    -- 'default' reads as the declared binding.
                    value=raw:lower()=='default' and item.default or require('mc_menu').keybind(item,raw)
                else
                    value=tonumber(raw)
                    if not require('mc_menu').valid(item,value) then value=nil end
                end
                values[item.id]=value
            end
        end
    end
    return values
end
-- Numbers are written as integers; keybinds as their text.
local function text(value)
    return type(value)=='number' and tostring(math.tointeger(value) or value) or value
end
function M.encode(content,definition,values)
    local sections,order=index(definition)
    local output,seen,written,section={},{},{},nil
    for _,item in ipairs(definition.settings) do
        assert(require('mc_menu').valid(item,values[item.id]),'invalid setting: ' .. item.id)
    end
    local function missing(name)
        for _,item in ipairs(definition.settings) do
            if item.configSection==name and not written[item.id] then
                output[#output+1]=item.configKey .. '=' .. text(values[item.id]); written[item.id]=true
            end
        end
    end
    for _,line in ipairs(lines(content)) do
        local heading=line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then
            if sections[section] then missing(section) end
            section=heading; seen[section]=true
        elseif sections[section] then
            local key=line:match('^%s*([^=;#]-)%s*=')
            local item=key and sections[section][key]
            if item then
                local comment=line:match('([;#].*)$')
                line=key .. '=' .. text(values[item.id]) .. (comment and ' ' .. comment or '')
                written[item.id]=true
            end
        end
        output[#output+1]=line
    end
    if sections[section] then missing(section) end
    for _,name in ipairs(order) do
        if not seen[name] then output[#output+1]='[' .. name .. ']'; missing(name) end
    end
    return table.concat(output,'\n') .. '\n'
end
function M.open(path,definition)
    local function read(filePath)
        local file,why,code=io.open(filePath,'rb')
        if not file then assert(code==2,why); return nil end
        local content=assert(file:read('*a')); assert(file:close()); return content
    end
    local temporary,previous=path .. '.mcc-tmp',path .. '.mcc-previous'
    local function checked(content,name)
        local ok,values=pcall(M.decode,content,definition)
        assert(ok,'unresolved config transaction (' .. name .. ' invalid): ' .. tostring(values))
        return values
    end
    local function recover()
        local destination,staged,prior=read(path),read(temporary),read(previous)
        if destination~=nil then
            local values=checked(destination,path)
            assert(not (staged~=nil and prior~=nil),
                'unresolved config transaction (all files present): ' .. path)
            if staged~=nil then
                checked(staged,temporary)
                assert(os.remove(temporary),'could not remove stale config temporary: ' .. temporary)
            end
            if prior~=nil then
                checked(prior,previous)
                assert(os.remove(previous),'could not remove stale config previous: ' .. previous)
            end
            return destination,values
        end
        if prior~=nil then
            local values=checked(prior,previous)
            if staged~=nil then checked(staged,temporary) end
            assert(os.rename(previous,path),'could not restore previous config: ' .. previous)
            if staged~=nil then
                assert(os.remove(temporary),'could not remove stale config temporary: ' .. temporary)
            end
            return prior,values
        end
        assert(staged==nil,'unresolved initial config transaction: ' .. temporary)
        return nil,M.decode('',definition)
    end
    -- An unresolved save transaction needs review before anything is written, but the
    -- mod still starts on defaults; only saving is refused.
    local recovered,original,initial=pcall(recover)
    if not recovered then
        local why=tostring(original)
        local self={values=M.decode('',definition),recoveryError=why}
        function self:save() error('config unavailable until reviewed: ' .. why,0) end
        return self
    end
    local self={values=initial}
    local publish
    function self:save(values)
        return publish(function() return M.encode(original or '',definition,values) end)
    end
    publish=function(render)
        assert(read(path)==original,'config changed externally; reopen the menu before saving')
        -- A published save can leave only its cleanup file behind.
        local prior=read(previous)
        if prior~=nil then
            assert(read(temporary)==nil and original~=nil,
                'unfinished config transaction needs review')
            checked(prior,previous)
            assert(os.remove(previous),'could not remove stale config previous: ' .. previous)
        end
        local content=render()
        assert(read(temporary)==nil and read(previous)==nil,'unfinished config transaction needs review')
        local file=assert(io.open(temporary,'wb'))
        local ok,why=file:write(content)
        local closed,closeWhy=file:close()
        if not ok or not closed then os.remove(temporary); error(why or closeWhy) end
        if original~=nil then
            local moved,moveWhy=os.rename(path,previous)
            if not moved then os.remove(temporary); error(moveWhy) end
        end
        local renamed,renameWhy=os.rename(temporary,path)
        if not renamed then
            local restored=original==nil or os.rename(previous,path)
            if restored then os.remove(temporary) end
            error(tostring(renameWhy) .. (restored and '; original retained' or '; restore failed: ' .. previous))
        end
        original=content; self.values=M.decode(content,definition)
        if read(previous)~=nil then
            local removed,why=os.remove(previous)
            if not removed then return true,'config committed; previous cleanup pending: ' .. tostring(why) end
        end
        return true
    end
    return self
end
return M
