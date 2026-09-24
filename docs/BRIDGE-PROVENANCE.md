# Bundled UE4SS Lua Event Bridge

- Upstream final release: `v1.0.1` (2026-09-20)
- Release page: https://github.com/jrpereira/UE4SSLuaEventBridge/releases/tag/v1.0.1
- Asset: `UE4SSLuaEventBridge-v1.0.1.zip`
- Asset SHA-256: `7a67bcd2bdd2d320ac7885668d0f6960aa4bd0e676ae75c78cf65e6ca6f47fd8`
- Embedded `dlls/main.dll` SHA-256: `25a03337b61f886db79ccc6deeb298b1ba1720053874b4d82ce8798e832ea2db`
- Lua API: `UE4SSLuaEventBridge`, capability API 4.

The release archive's `_UE4SSLuaEventBridge/dlls/main.dll` is copied byte for
byte into `_ModCore_Controls/dlls/main.dll`. Its `enabled.txt` is represented by
KEC's own marker. The release's legacy-folder migration runs only from the
original `_UE4SSLuaEventBridge` location; under `_ModCore_Controls` it returns
without changing sibling folders. The old live bridge folder must be disabled
when KEC is installed to avoid loading the same native component twice.
