-- Windows virtual-key values used by DMM key capture, converted to Unreal names.
local names={
    [0]='None',[0x01]='LeftMouseButton',[0x02]='RightMouseButton',[0x04]='MiddleMouseButton',
    [0x05]='ThumbMouseButton',[0x06]='ThumbMouseButton2',[0x08]='BackSpace',[0x09]='Tab',
    [0x0D]='Enter',[0x20]='SpaceBar',[0x21]='PageUp',[0x22]='PageDown',[0x23]='End',
    [0x24]='Home',[0x25]='Left',[0x26]='Up',[0x27]='Right',[0x28]='Down',
    [0x2D]='Insert',[0x2E]='Delete',[0x5B]='LeftCommand',[0x5C]='RightCommand',
    [0xA0]='LeftShift',[0xA1]='RightShift',[0xA2]='LeftControl',[0xA3]='RightControl',
    [0xA4]='LeftAlt',[0xA5]='RightAlt',[0xDC]='Backslash',
}
local digits={'Zero','One','Two','Three','Four','Five','Six','Seven','Eight','Nine'}
for number=0,9 do names[0x30+number]=digits[number+1] end
for code=string.byte('A'),string.byte('Z') do names[code]=string.char(code) end
for number=1,12 do names[0x6F+number]='F' .. number end
return { toName=function(value) return names[tonumber(value)] end }
