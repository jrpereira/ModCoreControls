assert(loadfile('Scripts/main.lua'))()
assert(type(ModCoreControls) == 'table')
assert(type(ModCoreControls.addSection) == 'function')
assert(type(ModCoreControls.addSectionMap) == 'function')
assert(ModCoreControls.openMenu == nil and ModCoreControls.closeMenu == nil)
assert(ModCoreControls.new == nil and ModCoreControls.quickslotHost == nil)

print('PASS focused MCC entry point exposes section and map registration')
