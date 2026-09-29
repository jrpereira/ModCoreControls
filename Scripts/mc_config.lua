-- Shared persistence: [ModCoreControls.<section>], map=<map ID>, numeric keys/triggers.
local M = {}
local function lines(content)
    local out={}
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
local function stored(item,value) return item.storedValues and item.storedValues[value] or tostring(value) end
function M.decode(content,definition)
    local sections=index(definition)
    local values,seen,section={},{},nil
    for _,line in ipairs(lines(content)) do
        local heading=line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then
            section=heading
            if sections[section] then assert(not seen[section],'duplicate config section: ' .. section); seen[section]=true end
        elseif sections[section] then
            local key,raw=line:match('^%s*([^=;#]-)%s*=%s*([^;#]*)')
            local item=key and sections[section][key]
            if item then
                assert(values[item.id]==nil,'duplicate config key: ' .. key)
                raw=raw:match('^%s*(.-)%s*$')
                local value
                if item.storedValues then
                    for number,name in pairs(item.storedValues) do if name==raw then value=number end end
                else value=tonumber(raw) end
                assert(require('mc_menu').valid(item,value),'invalid config value: ' .. key)
                values[item.id]=value
            end
        end
    end
    return values
end
function M.encode(content,definition,values)
    M.decode(content,definition)
    local sections,order=index(definition)
    local output,seen,written,section={},{},{},nil
    for _,item in ipairs(definition.settings) do
        assert(require('mc_menu').valid(item,values[item.id]),'invalid setting: ' .. item.id)
    end
    local function missing(name)
        for _,item in ipairs(definition.settings) do
            if item.configSection==name and not written[item.id] then
                output[#output+1]=item.configKey .. '=' .. stored(item,values[item.id]); written[item.id]=true
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
                line=key .. '=' .. stored(item,values[item.id]) .. (comment and ' ' .. comment or '')
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
    local original,initial=recover()
    local self={values=initial}
    function self:save(values)
        assert(read(path)==original,'config changed externally; reopen the menu before saving')
        -- A published save can leave only its cleanup file behind.
        local prior=read(previous)
        if prior~=nil then
            assert(read(temporary)==nil and original~=nil,
                'unfinished config transaction needs review')
            checked(prior,previous)
            assert(os.remove(previous),'could not remove stale config previous: ' .. previous)
        end
        local content=M.encode(original or '',definition,values)
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
        if original~=nil and read(previous)~=nil then
            local removed,why=os.remove(previous)
            if not removed then return true,'config committed; previous cleanup pending: ' .. tostring(why) end
        end
        return true
    end
    return self
end
return M
