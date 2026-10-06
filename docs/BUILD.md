# Build guide

## Requirements

Use Lua 5.4. MCC is Lua-only; no compilation is needed. Run commands from this
repository's root. Live integration requires the dependencies in the [README](README.md).

## Offline tests

Run every Lua suite from Bash:

```sh
for test in tests/*_test.lua; do
    lua5.4 "$test" || exit 1
done
```

The DMM integration suite skips unless both paths are supplied. To include it,
set these variables before running the same loop:

```sh
export DMM_CHOICES_PATH="/path/to/DawnwalkerModMenu/Scripts/choices.lua"
export MCS_SCRIPTS_PATH="/path/to/ModCoreSettings/Scripts"
```

A focused declaration check is `lua5.4 tests/mc_menu_test.lua`; input validation
is covered by `lua5.4 tests/mc_input_plan_test.lua`.

## In-game checks

Restart after changing Lua. Check section/map navigation, key capture, Apply and
Restore. Then check exploration/combat transitions, Tap/Hold, cancellation,
HUD indicators and native controls after clearing custom bindings.
Offline fixtures do not establish native timing, object lifetime or frame cost.
