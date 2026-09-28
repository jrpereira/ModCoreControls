local grouped = {
    id = 'grouped',
    value = 0,
    label = 'Grouped',
    description = 'Select an ability or consumable group, then use four shared positional keys.',
    repeatVisibilityOnSettings = false,
    sections = {
        {
            label = 'Group Keys',
            level = 2,
            controlLevel = 4,
            controls = {
                {
                    id = 'default-group',
                    label = 'Default',
                    purpose = 'Uses the ability group when no alternative selector is active.',
                    actionGroup = 'ability',
                    key = {setting = 'Group1Key', defaultValue = 0, name = 'None'},
                    mode = {
                        setting = 'Group1Mode',
                        defaultMode = 'disabled',
                        options = {
                            {id = 'hold', value = 2, label = 'Hold'},
                            {id = 'disabled', value = -2, label = 'Disabled'},
                        },
                    },
                },
                {
                    id = 'alternative-group',
                    label = 'Alternative',
                    purpose = 'Selects the consumable group; Tap toggles it and Hold selects it while pressed.',
                    actionGroup = 'consumable',
                    key = {setting = 'Group2Key', defaultValue = 164, name = 'LeftAlt'},
                    mode = {
                        setting = 'Group2Mode',
                        defaultMode = 'hold',
                        options = {
                            {id = 'tap', value = 0, label = 'Tap'},
                            {id = 'hold', value = 2, label = 'Hold'},
                        },
                    },
                },
            },
        },
        {
            label = 'Slot Keys',
            level = 2,
            controlLevel = 4,
            controls = {
                {
                    id = 'shared-slot-1',
                    label = 'Slot 1 (or 5)',
                    actions = {default = 'quickslot.ability.left', alternative = 'quickslot.consumable.left'},
                    key = {setting = 'Shared1Key', defaultValue = 49, name = '1'},
                    mode = {setting = 'Shared1Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'shared-slot-2',
                    label = 'Slot 2 (or 6)',
                    actions = {default = 'quickslot.ability.top', alternative = 'quickslot.consumable.top'},
                    key = {setting = 'Shared2Key', defaultValue = 50, name = '2'},
                    mode = {setting = 'Shared2Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'shared-slot-3',
                    label = 'Slot 3 (or 7)',
                    actions = {default = 'quickslot.ability.right', alternative = 'quickslot.consumable.right'},
                    key = {setting = 'Shared3Key', defaultValue = 51, name = '3'},
                    mode = {setting = 'Shared3Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'shared-slot-4',
                    label = 'Slot 4 (or 8)',
                    actions = {default = 'quickslot.ability.bottom', alternative = 'quickslot.consumable.bottom'},
                    key = {setting = 'Shared4Key', defaultValue = 52, name = '4'},
                    mode = {setting = 'Shared4Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
            },
        },
    },
}

local flat = {
    id = 'flat',
    value = 1,
    label = 'Flat',
    description = 'Bind each ability and consumable slot directly to its own key.',
    repeatVisibilityOnSettings = true,
    sections = {
        {
            label = 'Fixed Controls',
            level = 2,
            controls = {
                {
                    id = 'flat-slot-1', label = 'Slot 1', action = 'quickslot.ability.left',
                    key = {setting = 'Flat1Key', defaultValue = 49, name = '1'},
                    mode = {setting = 'Flat1Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'flat-slot-2', label = 'Slot 2', action = 'quickslot.ability.top',
                    key = {setting = 'Flat2Key', defaultValue = 50, name = '2'},
                    mode = {setting = 'Flat2Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'flat-slot-3', label = 'Slot 3', action = 'quickslot.ability.right',
                    key = {setting = 'Flat3Key', defaultValue = 51, name = '3'},
                    mode = {setting = 'Flat3Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'flat-slot-4', label = 'Slot 4', action = 'quickslot.ability.bottom',
                    key = {setting = 'Flat4Key', defaultValue = 52, name = '4'},
                    mode = {setting = 'Flat4Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'flat-slot-5', label = 'Slot 5', action = 'quickslot.consumable.left',
                    key = {setting = 'Flat5Key', defaultValue = 53, name = '5'},
                    mode = {setting = 'Flat5Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'flat-slot-6', label = 'Slot 6', action = 'quickslot.consumable.top',
                    key = {setting = 'Flat6Key', defaultValue = 54, name = '6'},
                    mode = {setting = 'Flat6Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'flat-slot-7', label = 'Slot 7', action = 'quickslot.consumable.right',
                    key = {setting = 'Flat7Key', defaultValue = 55, name = '7'},
                    mode = {setting = 'Flat7Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
                {
                    id = 'flat-slot-8', label = 'Slot 8', action = 'quickslot.consumable.bottom',
                    key = {setting = 'Flat8Key', defaultValue = 56, name = '8'},
                    mode = {setting = 'Flat8Mode', defaultMode = 'tap', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 1, label = 'Hold'},
                    }},
                },
            },
        },
        {
            label = 'Optional',
            level = 2,
            controls = {
                {
                    id = 'preview-alternative',
                    label = 'Preview Alternative',
                    purpose = 'Tap toggles the alternative wheel; Hold shows it only while pressed.',
                    action = 'preview.alternative',
                    key = {setting = 'SlotFlatPreview', defaultValue = 0, name = 'None'},
                    mode = {setting = 'SlotFlatPreviewMode', defaultMode = 'hold', options = {
                        {id = 'tap', value = 0, label = 'Tap'},
                        {id = 'hold', value = 2, label = 'Hold'},
                    }},
                },
            },
        },
    },
}

return {grouped, flat}
