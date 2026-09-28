from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
layout = {}
groups = []
for source_line in (ROOT / 'Scripts/templates/default.tpl').read_text().splitlines():
    line = source_line.split('#', 1)[0].strip()
    if line:
        key, value = line.split(':', 1)
        if key.strip() == 'group':
            groups.append([part.strip() for part in value.split('|')])
        else:
            layout[key.strip()] = value.strip()
assert layout['title'] == 'Basic Slots'
SECTION = layout['section']
ABILITY_SLOTS = [slot.strip() for slot in next(group for group in groups if group[0] == 'ability')[7].split(',')]
CONSUMABLE_SLOTS = [slot.strip() for slot in next(group for group in groups if group[0] == 'consumable')[7].split(',')]
assert ABILITY_SLOTS == CONSUMABLE_SLOTS == ['Left', 'Top', 'Right', 'Bottom']
rows = []
config = ['[Controls]']


def section(name, data):
    rows.append(f'[{name}]')
    for key in sorted(data):
        if data[key] is not None:
            rows.append(f'{key}={data[key]}')
    rows.append('')


def setting(name, kind, label, group, default, **extra):
    key = 'MCC_' + name
    data = dict(ConfigFile='config.ini', ConfigKey=key, ConfigSection='Controls',
                Default=default, Group=group, Id=key, Label=label, Type=kind)
    data.update(extra)
    section('Setting.' + key, data)
    config.append(f'{key}={default}')
    return key


section('Mod', dict(Id='ModCoreControls', Name='Controls', Author='Jorge Pereira (kell)', Version='0.1.1',
                    Description='Choose Grouped or Flat Actions Layout and configure its controls.'))
section('Category.' + SECTION, dict(mcHeading=0))
for group in ('Fixed Controls', 'Optional'):
    section('Category.' + group, dict(VisibleWhen='MCC_AccessMethod', VisibleValues=1,
                                      mcHeading=1, mcLevel=2))
for group in ('Group Keys', 'Slot Keys'):
    section('Category.' + group, dict(VisibleWhen='MCC_AccessMethod', VisibleValues=0, mcHeading=1, mcLevel=2))
setting('AccessMethod', 'picker', 'Control Layout', SECTION, 0,
        PresetValues='0|1', PresetLabels='Grouped|Flat',
        Description='Grouped uses a group key and shared slot keys. Flat gives each slot its own key.',
        mcType='tab', mcLevel=1)
for index in range(1, 9):
    prefix = f'Flat{index}'
    key = setting(prefix + 'Key', 'integer', f'Slot {index}', 'Fixed Controls',
                  48 + index,
                  Minimum=0, Maximum=254, Step=1, mcType='keybind',
                  VisibleWhen='MCC_AccessMethod', VisibleValues=1)
    setting(prefix + 'Mode', 'picker', f'Slot {index}', 'Fixed Controls', 0,
            PresetValues='0|1', PresetLabels='Tap|Hold', mcType='tab', Pair=key,
            VisibleWhen='MCC_AccessMethod', VisibleValues=1)
preview = setting('SlotFlatPreview', 'integer', 'Preview Alternative', 'Optional', 0,
                  Minimum=0, Maximum=254, Step=1, mcType='keybind',
                  VisibleWhen='MCC_AccessMethod', VisibleValues=1)
setting('SlotFlatPreviewMode', 'picker', 'Preview Alternative', 'Optional', 2,
        PresetValues='0|2', PresetLabels='Tap|Hold', mcType='tab', Pair=preview,
        VisibleWhen='MCC_AccessMethod', VisibleValues=1)
for index, label in enumerate(('Default', 'Alternative'), 1):
    prefix = f'Group{index}'
    key = setting(prefix + 'Key', 'integer', label, 'Group Keys',
                  0 if index == 1 else 164,
                  Minimum=0, Maximum=254, Step=1, mcType='keybind', mcLevel=4)
    if index == 1:
        setting(prefix + 'Mode', 'picker', label, 'Group Keys', -2,
                PresetValues='2|-2', PresetLabels='Hold|Disabled',
                mcType='tab', Pair=key, mcLevel=4)
    else:
        setting(prefix + 'Mode', 'picker', label, 'Group Keys', 2,
                PresetValues='0|2', PresetLabels='Tap|Hold',
                mcType='tab', Pair=key, mcLevel=4)
for slot in range(1, 5):
    prefix = f'Shared{slot}'
    label = f'Slot {slot} (or {slot + 4})'
    key = setting(prefix + 'Key', 'integer', label, 'Slot Keys', 48 + slot,
                  Minimum=0, Maximum=254, Step=1, mcType='keybind', mcLevel=4)
    setting(prefix + 'Mode', 'picker', label, 'Slot Keys', 0,
            PresetValues='0|1', PresetLabels='Tap|Hold', mcType='tab', Pair=key, mcLevel=4)
(ROOT / 'mod_settings.ini').write_text('\n'.join(rows).rstrip() + '\n')
(ROOT / 'config.ini').write_text('\n'.join(config) + '\n')
