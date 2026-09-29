local source=debug.getinfo(1,'S').source:gsub('^@','')
local root=assert(source:match('^(.*)[/\\]tools[/\\][^/\\]+$')
    or (source:match('^tools[/\\]') and '.'), 'cannot locate Controls root')
package.path=root .. '/Scripts/?.lua;' .. package.path
local content=require('mc_dmm').manifest()
local file=assert(io.open(root .. '/mod_settings.ini','wb'))
assert(file:write(content)); assert(file:close())
-- User config is initialized and saved by the menu paths, never by this tool.
