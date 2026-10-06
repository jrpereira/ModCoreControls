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
-- Renamed map IDs per section. Old keys move to the new ID unless the new key
-- already exists, in which case the stale old line is dropped.
local renamedMaps={['ModCoreControls.actions']={flat='global'}}
-- Maps once were alternatives chosen by map=<ID>. They now coexist: the choice
-- is dropped with the entries of every map it did not select, so no saved key
-- activates silently. Default is the base map and keeps its entries. Removed
-- maps and keys are dropped whenever they appear.
local coexisting={['ModCoreControls.actions']={base='default',removedMaps={advanced=true},
    removedKeys={['global.FixedGroupFocus2.key']=true,['global.FixedGroupFocus2.trigger']=true}}}
local function coexist(content)
    local selected,section={},nil
    for _,line in ipairs(lines(content)) do
        local heading=line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section=heading
        else
            local key,raw=line:match('^%s*([^=;#]-)%s*=%s*([^;#]*)')
            if key=='map' and coexisting[section] then selected[section]=raw:match('^%s*(.-)%s*$') end
        end
    end
    local output,changed={},false
    section=nil
    for _,line in ipairs(lines(content)) do
        local heading=line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section=heading
        elseif coexisting[section] then
            local rule,key=coexisting[section],line:match('^%s*([^=;#]-)%s*=')
            local prefix=key and key:match('^([^.]+)%.')
            if key=='map' or (key and rule.removedKeys[key]) or (prefix and rule.removedMaps[prefix])
                or (prefix and selected[section] and prefix~=rule.base and prefix~=selected[section]) then
                line=nil
            end
        end
        if line then output[#output+1]=line else changed=true end
    end
    if not changed then return content end
    return table.concat(output,'\n') .. '\n'
end
local function rename(content)
    local function renamed(section,key,raw)
        local maps=renamedMaps[section]
        if not maps then return nil end
        if key=='map' then
            local value=maps[raw:match('^%s*(.-)%s*$')]
            if value then return 'map',value end
            return nil
        end
        local prefix,rest=key:match('^([^.]+)(%..+)$')
        return prefix and maps[prefix] and maps[prefix] .. rest or nil
    end
    local present,section={},nil
    for _,line in ipairs(lines(content)) do
        local heading=line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section=heading
        else
            local key=line:match('^%s*([^=;#]-)%s*=')
            if key then present[(section or '') .. '\0' .. key]=true end
        end
    end
    local output,changed={},false
    section=nil
    for _,line in ipairs(lines(content)) do
        local heading=line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section=heading
        else
            local key,raw=line:match('^%s*([^=;#]-)%s*=%s*([^;#]*)')
            local newKey,newValue
            if key then newKey,newValue=renamed(section,key,raw) end
            if newKey=='map' then
                local comment=line:match('([;#].*)$')
                line='map=' .. newValue .. (comment and ' ' .. comment or '')
                changed=true
            elseif newKey then
                changed=true
                if present[section .. '\0' .. newKey] then line=nil
                else line=line:gsub('^(%s*)' .. key:gsub('%p','%%%0'),'%1' .. newKey,1) end
            end
        end
        if line then output[#output+1]=line end
    end
    if not changed then return content end
    return table.concat(output,'\n') .. '\n'
end
-- Maps that moved to another section carry their saved lines along; a line
-- already present at the destination wins over the moved one.
local moved={{from='ModCoreControls.actions',to='ModCoreControls.module',prefix='default'}}
local function relocate(content)
    for _,move in ipairs(moved) do
        local carried,present,output,section={}, {}, {}, nil
        for _,line in ipairs(lines(content)) do
            local heading=line:match('^%s*%[([^%]]+)%]%s*$')
            if heading then section=heading
            else
                local key=line:match('^%s*([^=;#]-)%s*=')
                if section==move.to and key then present[key]=true end
            end
        end
        section=nil
        local target
        for _,line in ipairs(lines(content)) do
            local heading=line:match('^%s*%[([^%]]+)%]%s*$')
            if heading then section=heading;output[#output+1]=line
                if section==move.to then target=#output end
            else
                local key=line:match('^%s*([^=;#]-)%s*=')
                if section==move.from and key and key:match('^([^.]+)%.')==move.prefix then
                    if not present[key] then carried[#carried+1]=line end
                else output[#output+1]=line end
            end
        end
        if #carried>0 or #output~=#lines(content) then
            if target then
                -- Append to the end of the destination section.
                local finish=#output
                for i=target+1,#output do
                    if output[i]:match('^%s*%[([^%]]+)%]%s*$') then finish=i-1;break end
                end
                for offset,line in ipairs(carried) do table.insert(output,finish+offset,line) end
            elseif #carried>0 then
                output[#output+1]='[' .. move.to .. ']'
                for _,line in ipairs(carried) do output[#output+1]=line end
            end
            content=table.concat(output,'\n') .. '\n'
        end
    end
    return content
end
function M.migrate(content) return relocate(coexist(rename(content))) end
-- Configuration never prevents startup: an unreadable or invalid value is left out,
-- so its default applies, and a repeated key keeps its first value.
function M.decode(content,definition)
    content=M.migrate(content)
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
    content=M.migrate(content)
    M.decode(content,definition)
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
    -- Persist renamed map keys once so the settings menu, which reads config.ini
    -- directly, finds them under their current names.
    local publish
    local migration
    if original~=nil and M.migrate(original)~=original then
        migration=function() return publish(function() return M.migrate(original) end) end
    end
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
        if original~=nil and read(previous)~=nil then
            local removed,why=os.remove(previous)
            if not removed then return true,'config committed; previous cleanup pending: ' .. tostring(why) end
        end
        return true
    end
    if migration then
        local ok,why=pcall(migration)
        self.migrationError=not ok and tostring(why) or nil
    end
    return self
end
return M
