# KEngine Controls development

Read `/home/jorge/projects/Gaming/_shared/rules/RULES.md` and relevant shared
procedures before modifying this module. Keep runtime files in `Scripts/`, tests
in `tests/`, and documentation in `docs/`. Do not put personal configuration,
generated builds, logs, or credentials in source control.

KEC owns action identity, control layouts, and input mapping. A consuming mod
owns the behavior invoked by its action callback. KET owns template selection
and visual layout. The bundled UE4SS Lua Event Bridge release owns native
Enhanced Input primitives; there is no separately installed bridge mod.
Preserve player configuration and enablement during installation.
