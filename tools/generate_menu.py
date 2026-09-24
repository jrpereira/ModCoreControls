from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
layout = {}
groups = []
for source_line in (ROOT / 'templates/default.tpl').read_text().splitlines():
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
    section('Setting.' + key, data)
    config.append(f'{key}={default}')
    return key


section('Mod', dict(Id='ModCoreControls', Name='ModCore Controls', Version='0.1.1',
                    Description='Choose Grouped, Flat, or Advanced Actions Layout and configure its controls.'))
section('Category.' + SECTION, dict(mcLevel=3))
section('Category.Standard', dict(VisibleWhen='KEC_AccessMethod', VisibleValues='1|2', mcLevel=3))
section('Category.Group Key', dict(VisibleWhen='KEC_AccessMethod', VisibleValues=0, mcLevel=4))
section('Category.Slot Key', dict(VisibleWhen='KEC_AccessMethod', VisibleValues=0, mcLevel=4))
section('Category.Advanced', dict(VisibleWhen='KEC_AccessMethod', VisibleValues=2, mcLevel=4))
setting('AccessMethod', 'picker', 'Access Method', SECTION, 0,
        PresetValues='0|1|2', PresetLabels='Grouped|Flat|Advanced',
        mcType='tab', mcLevel=1)
for index in range(1, 9):
    prefix = f'Flat{index}'
    group = 'Ability' if index <= 4 else 'Consumable'
    slot = ((index - 1) % 4) + 1
    label = f'{group} {slot}'
    setting(prefix + 'ActivateKey', 'integer', f'{label} Activate', 'Advanced', 0,
            Minimum=0, Maximum=254, Step=1, mcType='keybind')
    key = setting(prefix + 'Key', 'integer', f'Slot {index}', 'Standard',
                  48 + ((index - 1) % 4) + 1,
                  Minimum=0, Maximum=254, Step=1, mcType='keybind')
    setting(prefix + 'Mode', 'picker', f'Slot {index}', 'Standard', 0,
            PresetValues='0|1', PresetLabels='Tap|Hold', mcType='tab', Pair=key)
for index, group in enumerate(('Abilities', 'Consumables'), 1):
    prefix = f'Group{index}'
    key = setting(prefix + 'Key', 'integer', group, 'Group Key',
                  0 if index == 1 else 164,
                  Minimum=0, Maximum=254, Step=1, mcType='keybind')
    setting(prefix + 'Mode', 'picker', group, 'Group Key', -1 if index == 1 else 2,
            PresetValues='2|0|-1' if index == 1 else '2|0',
            PresetLabels='Hold|Tap|Default' if index == 1 else 'Hold|Tap',
            mcType='tab', Pair=key)
for slot in range(1, 5):
    prefix = f'Shared{slot}'
    key = setting(prefix + 'Key', 'integer', f'Slot {slot}', 'Slot Key', 48 + slot,
                  Minimum=0, Maximum=254, Step=1, mcType='keybind')
    setting(prefix + 'Mode', 'picker', f'Slot {slot}', 'Slot Key', 0,
            PresetValues='0|1', PresetLabels='Tap|Hold', mcType='tab', Pair=key)
for index, group in enumerate(('Ability', 'Consumable'), 1):
    for slot in range(1, 5):
        prefix = f'Advanced{index}Slot{slot}'
        label = f'{group} {slot} Override'
        key = setting(prefix + 'Key', 'integer', label,
                      'Advanced', 0, Minimum=0, Maximum=254, Step=1,
                      mcType='keybind')
        setting(prefix + 'Mode', 'picker', label, 'Advanced', 0,
                PresetValues='0|1', PresetLabels='Tap|Hold', mcType='tab', Pair=key)
(ROOT / 'mod_settings.ini').write_text('\n'.join(rows) + '\n')
(ROOT / 'config.ini').write_text('\n'.join(config) + '\n')
