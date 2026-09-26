# Build guide

- [Requirements](#requirements)
- [Source preparation](#source-preparation)
- [Offline tests](#offline-tests)
- [Native input gate ownership](#native-input-gate-ownership)

## Requirements

- Lua 5.4 for source checks and offline tests.
- Python 3 for the documented tooling.
- A compatible UE4SS/Dawnwalker installation for native integration checks.

These are Lua modules; there is no native compilation step in this repository.
Run the commands below from the repository root.

## Source preparation

The [menu generator](../tools/generate_menu.py) reads the declarative
[default layout](../Scripts/templates/default.tpl). Run it only in a development copy:

```sh
python3 tools/generate_menu.py
```

It overwrites both [menu metadata](../mod_settings.ini) and
[control configuration](../config.ini), including existing binding values.
Keep personal configurations out of that copy. This generates defaults; it is
not a configuration migration tool.

## Offline tests

Run the Lua suites from Bash:

```sh
for test in tests/*_test.lua; do
    lua "$test" || exit 1
done
```

Use a Lua 5.4 executable on your PATH. Individual suites can also be run as
`lua tests/<suite>_test.lua` from the repository root.

## Native input gate ownership

Controls suppresses its allowlisted native quickslot actions by attaching an
`InputTriggerChordAction` that requires an unmapped inactive action. Generated
Controls actions and their DLL callbacks provide replacement input behavior.

The host constructs each named `MCC_NativeActionGate` with `RF_Transient |
RF_MarkAsRootSet` (`0xC0`) and verifies its actual internal `RootSet` bit. It
looks up the same object path before construction, so detaching, applying again,
or rebuilding the Lua host reuses the gate. Existing attached gates are also
validated; an old unrooted gate requires a fresh game process.

Ownership intentionally lasts until process exit. The native allowlist bounds
this to one gate per action (at most five with the current list). These roots also
retain their outer action assets and their inactive chord action. They must not
be generalized to per-pawn or unbounded dynamic targets. Merely storing a Lua
wrapper is not an Unreal GC ownership mechanism.

Deactivation removes owned gates from native arrays, preserves foreign triggers,
and requests a mapping rebuild. Detached gates remain rooted and reusable; a
failed rebuild retains them while removal is retried. No root removal is
attempted through unsupported Lua APIs. Shorter-lived ownership would require an
engine-supported strong-reference owner and proven rebuild/GC ordering.

`tests/native_gate_ownership_test.lua` exercises the real host factory with a
fixture for Unreal: root verification, repeated updates, reuse after detach and
Lua-host recreation, failed rebuild retry, and rejection of unrooted legacy or
wrong-class objects. It does not establish actual Unreal GC safety or native
blocking behavior. Validate those in a fresh game process, including map changes,
Apply/deactivate/reactivate, original-input suppression and custom input delivery.
