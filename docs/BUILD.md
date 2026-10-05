# Build guide

ModCore Controls uses Lua 5.4 and has no native compilation step or generated
files. `main.lua` publishes the Controls page to ModCoreSettings at startup, and
ModCoreSettings builds its settings from `Scripts/mcs_page.lua` each time the
menu opens. `Scripts/menu_contributions.lua` is vendored unchanged from
ModCoreSettings (client version 3).

## Offline tests

Run the focused suites from the repository root:

```sh
lua5.4 tests/mc_structures_test.lua
lua5.4 tests/mc_menu_test.lua
lua5.4 tests/main_test.lua
lua5.4 tests/mc_page_publish_test.lua
lua5.4 tests/mc_dmm_validation_test.lua
lua5.4 tests/mc_input_plan_test.lua
lua5.4 tests/mc_native_callbacks_test.lua
lua5.4 tests/mc_overrides_test.lua
lua5.4 tests/mc_override_default_test.lua
lua5.4 tests/mc_input_context_test.lua
lua5.4 tests/mc_events_test.lua
lua5.4 tests/mc_quickslots_test.lua
lua5.4 tests/mc_input_host_test.lua
lua5.4 tests/mc_key_indicators_test.lua
lua5.4 tests/startup_failure_test.lua
```

The DMM integration test uses the current DMM parser and ModCoreSettings'
navigation, presentation, configuration and page hooks wrappers:

```sh
DMM_CHOICES_PATH=/path/to/DawnwalkerModMenu/Scripts/choices.lua \
MCS_SCRIPTS_PATH=/path/to/ModCoreSettings/Scripts \
lua5.4 tests/mc_dmm_test.lua
```

Native timing, object lifetimes, and frame-time impact require a game session.

Validate section navigation, map visibility, key capture, Apply, and Restore in
the menu after installing. In game, also validate startup attachment, Apply
replacement, controller/map transitions, Tap and Hold delivery, cancellation,
and explicit deactivation.
