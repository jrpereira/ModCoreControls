# Build guide

ModCore Controls uses Lua 5.4 and has no native compilation step.

## Generate DMM metadata

Run the generator from the repository root:

```sh
lua5.4 tools/generate_menu.lua
```

The generator writes only the `[Mod]` discovery metadata to `mod_settings.ini`.
The DMM extension reads the shared section, map, and trigger definitions at
runtime. The generator never writes player choices to `config.ini`.

## Offline tests

Run the focused suites from the repository root:

```sh
lua5.4 tests/menu_generation_test.lua
lua5.4 tests/mc_structures_test.lua
lua5.4 tests/mc_menu_test.lua
lua5.4 tests/main_test.lua
lua5.4 tests/mc_input_plan_test.lua
lua5.4 tests/mc_native_callbacks_test.lua
lua5.4 tests/mc_overrides_test.lua
lua5.4 tests/mc_input_context_test.lua
lua5.4 tests/mc_quickslots_test.lua
lua5.4 tests/mc_input_host_test.lua
lua5.4 tests/mc_key_indicators_test.lua
lua5.4 tests/audit_6_integration_test.lua
lua5.4 tests/startup_failure_test.lua
```

The DMM integration test uses the current DMM parser and ModCoreSettings
navigation and presentation decorators:

```sh
DMM_CHOICES_PATH=/path/to/DawnwalkerModMenu/Scripts/choices.lua \
MCS_SCRIPTS_PATH=/path/to/ModCoreSettings/Scripts \
lua5.4 tests/mc_dmm_test.lua
```

`tests/menu_generation_test.lua` invokes the generator, which writes
`mod_settings.ini`. Run it in an isolated copy of the MCC source and manifest;
do not point it at an installed player configuration. The audit integration
suite uses an injected host environment and reports deterministic operation
counts. Native timing, object lifetimes, and frame-time impact require a game
session.

Validate section navigation, map visibility, key capture, Apply, and Restore in
DMM after installing the updated Lua definitions and minimal metadata. In game,
also validate startup attachment, Apply replacement, controller/map transitions,
Tap and Hold delivery, cancellation, and explicit deactivation.
