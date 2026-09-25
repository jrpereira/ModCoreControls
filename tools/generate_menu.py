from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
layout = {}
groups = []
for source_line in (ROOT / 'ModCore/templates/default.tpl').read_text().splitlines():
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
    key = 'KEC_' + name
    data = dict(ConfigFile='config.ini', ConfigKey=key, ConfigSection='Controls',
                Default=default, Group=group, Id=key, Label=label, Type=kind)
    data.update(extra)
    # Keep Advanced defaults available to the runtime, but omit its menu rows.
    if group != 'Advanced':
        section('Setting.' + key, data)
    config.append(f'{key}={default}')
    return key


section('Mod', dict(Id='ModCoreControls', Name='ModCore Controls', Version='0.1.1',
                    Description='Choose Grouped or Flat Actions Layout and configure its controls.'))
section('Category.' + SECTION, dict(mcHeading=0))
section('Category.Keyboard & Mouse', dict(mcHeading=0))
for group in ('Default Group', 'Alternative Group'):
    section('Category.' + group, dict(VisibleWhen='KEC_AccessMethod', VisibleValues=0, mcHeading=0))
setting('AccessMethod', 'picker', 'Access Method', SECTION, 0,
        PresetValues='0|1', PresetLabels='Grouped|Flat',
        mcType='tab', mcLevel=1)
for index in range(1, 9):
    prefix = f'Flat{index}'
    key = setting(prefix + 'Key', 'integer', f'Slot {index}', 'Keyboard & Mouse',
                  48 + ((index - 1) % 4) + 1,
                  Minimum=0, Maximum=254, Step=1, mcType='keybind',
                  VisibleWhen='KEC_AccessMethod', VisibleValues=1)
    setting(prefix + 'Mode', 'picker', f'Slot {index}', 'Keyboard & Mouse', 0,
            PresetValues='0|1', PresetLabels='Tap|Hold', mcType='tab', Pair=key,
            VisibleWhen='KEC_AccessMethod', VisibleValues=1)
for index in range(1, 9):
    prefix = f'Flat{index}'
    group = 'Ability' if index <= 4 else 'Consumable'
    slot = ((index - 1) % 4) + 1
    label = f'{group} {slot}'
    setting(prefix + 'ActivateKey', 'integer', f'{label} Activate', 'Advanced', 0,
            Minimum=0, Maximum=254, Step=1, mcType='keybind')
for index, group in enumerate(('Default Group', 'Alternative Group'), 1):
    prefix = f'Group{index}'
    key = setting(prefix + 'Key', 'integer', group, group,
                  0 if index == 1 else 164,
                  Minimum=0, Maximum=254, Step=1, mcType='keybind', mcLevel=4,
                  mcMode='Hold' if index == 2 else None)
    setting(prefix + 'Mode', 'picker', group, group if index == 1 else 'Advanced', -2 if index == 1 else 2,
            PresetValues='2|-2' if index == 1 else '2',
            PresetLabels='Hold|Disabled' if index == 1 else 'Hold',
            mcType='tab', Pair=key)
    for slot in range(1, 5):
        if index == 1:
            prefix = f'Shared{slot}'
            key = setting(prefix + 'Key', 'integer', f'Slot {slot}', group, 48 + slot,
                    Minimum=0, Maximum=254, Step=1, mcType='keybind')
            setting(prefix + 'Mode', 'picker', f'Slot {slot}', group, 0,
                    PresetValues='0|1', PresetLabels='Tap|Hold', mcType='tab', Pair=key)
        else:
            section(f'Setting.KEC_Slot{slot + 4}Reference', dict(
                Id=f'KEC_Slot{slot + 4}Reference', Type='picker',
                Label=f'Slot {slot + 4}', Group=group, Default=0,
                PresetValues='0|1', PresetLabels=f'Slot {slot}|Slot {slot}',
                mcReadOnly=1, mcReferenceLabel=f'Slot {slot}', mcType='tab'))
for index, group in enumerate(('Ability', 'Consumable'), 1):
    for slot in range(1, 5):
        prefix = f'Advanced{index}Slot{slot}'
        label = f'{group} {slot} Override'
        key = setting(prefix + 'Key', 'integer', label,
                      'Advanced', 0, Minimum=0, Maximum=254, Step=1,
                      mcType='keybind')
        setting(prefix + 'Mode', 'picker', label, 'Advanced', 0,
                PresetValues='0|1', PresetLabels='Tap|Hold', mcType='tab', Pair=key)
(ROOT / 'mod_settings.ini').write_text('\n'.join(rows).rstrip() + '\n')
(ROOT / 'config.ini').write_text('\n'.join(config) + '\n')
