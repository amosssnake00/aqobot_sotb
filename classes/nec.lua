local mq = require 'mq'
local class = require('classes.classbase')
local logger = require('utils.logger')
local timer = require('libaqo.timer')
local common = require('common')
local constants = require('constants')
local config = require('interface.configuration')
local abilities = require('ability')
local mode = require('mode')
local state = require('state')
local widgets = require('libaqo.widgets')

local Necromancer = class:new()

function Necromancer:init()
    self.classOrder = { 'assist', 'aggro', 'mash', 'debuff', 'burn', 'cast', 'recover', 'rez', 'buff', 'rest',
        'managepet' }
    self.spellRotations = { standard = {}, short = {}, custom = {} }
    self:initBase('NEC')

    self:initClassOptions()
    self:loadSettings()
    self:initSpellLines()
    self:initSpellRotations()
    self:initBurns()
    self:initAbilities()
    self:addCommonAbilities()

    self.neccount = 1
    self.debuffTimer = timer:new(30000)
end

function Necromancer:initClassOptions()
    self:addOption('STOPPCT', 'DoT Stop Pct', 0, nil, 'Percent HP to stop refreshing DoTs on mobs', 'inputint', nil,
        'StopPct', 'int')
    self:addOption('USEDEBUFF', 'Debuff', true, nil, 'Debuff targets with scent', 'checkbox', nil, 'UseDebuff', 'bool')
    self:addOption('USESNARE', 'Use snare', true, nil, 'User snare spell', 'checkbox', nil, 'UseSnare', 'bool')
    if not state.emu then
        self:addOption('USEBUFFSHIELD', 'Buff Shield', false, nil,
            'Keep shield buff up. Replaces corruption DoT.', 'checkbox', nil, 'UseBuffShield', 'bool')
    end
    self:addOption('USEMANATAP', 'Mana Drain', false, nil, 'Use group mana drain dot. Replaces Ignite DoT.', 'checkbox',
        nil, 'UseManaTap', 'bool')
    self:addOption('USEREZ', 'Use Rez', true, nil, 'Use Convergence AA to rez group members', 'checkbox', nil, 'UseRez',
        'bool')
    self:addOption('USEFD', 'Feign Death', true, nil, 'Use FD AA\'s to reduce aggro', 'checkbox', nil, 'UseFD', 'bool')
    if not state.emu then
        self:addOption('USEINSPIRE', 'Inspire Ally', true, nil, 'Use Inspire Ally pet buff', 'checkbox',
            nil, 'UseInspire', 'bool')
    end
    self:addOption('USEDISPEL', 'Use Dispel', true, nil, 'Dispel mobs with Eradicate Magic AA', 'checkbox', nil,
        'UseDispel', 'bool')
    self:addOption('USEWOUNDS', 'Use Wounds', true, nil, 'Use wounds DoT', 'checkbox', nil, 'UseWounds', 'bool')
    self:addOption('MULTIDOT', 'Multi DoT', false, nil, 'DoT all mobs', 'checkbox', nil, 'MultiDoT', 'bool')
    self:addOption('MULTICOUNT', 'Multi DoT #', 3, nil, 'Number of mobs to rotate through when multi-dot is enabled',
        'inputint', nil, 'MultiCount', 'int')
    self:addOption('USENUKES', 'Use Nukes', true, nil, 'Toggle use of nukes', 'checkbox', nil, 'UseNukes', 'bool')
    self:addOption('USEDOTS', 'Use DoTs', true, nil, 'Toggle use of DoTs, in case mobs are just dying too fast',
        'checkbox', nil, 'UseDoTs', 'bool')
    self:addOption('USELICH', 'Use Lich', true, nil,
        'Toggle use of lich, incase you\'re just farming and don\'t really need it', 'checkbox', nil, 'UseLich', 'bool')
    self:addOption('BURNPROC', 'Burn on Proc', false, nil, 'Toggle use of burns once proliferation dot lands', 'checkbox',
        nil, 'BurnProc', 'bool')
    self:addOption('SWAPSPELLS', 'Combat Spell Swap', true, nil,
        'Toggle swapping of spells during combat with standard spell rotation', 'checkbox', nil, 'SwapSpells', 'bool')
    self:addOption('USEPUSTULES', 'Use Pustules', false, nil, 'Toggle use of Necrotic Pustules proc buff', 'checkbox',
        nil, 'UsePustules', 'bool')
    self:addOption('USEDMF', 'Use Dead Man Floating', false, nil, 'Toggle use of DMF spell/aa', 'checkbox', nil, 'UseDMF',
        'bool')
end

Necromancer.SpellLines = {
    { -- strongest fire dot. Slot 1
        Group = 'pyreshort',

        Spells =
        {
            'Pyre of Illandrin',       -- [[NEC/124 - Mana: 21758 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 32 1: Decrease Current HP by 18842 per tick ]]
            'Pyre of Va Xakra',        -- [[NEC/119 - Mana: 18013 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 29 1: Decrease Current HP by 17080 per tick ]]
            'Pyre of Klraggek',        -- [[NEC/114 - Mana: 15344 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 26 1: Decrease Current HP by 14754 per tick ]]
            'Pyre of the Shadewarden', -- [[NEC/109 - Mana: 12774 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 23 1: Decrease Current HP by 12166 per tick ]]
            'Pyre of Jorobb',          -- [[NEC/104 - Mana: 10635 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 20 1: Decrease Current HP by 10031 per tick ]]
            'Pyre of Marnek',          -- [[NEC/99 - Mana: 8854 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 17 1: Decrease Current HP by 8271 per tick ]]
            'Pyre of Hazarak',         -- [[NEC/94 - Mana: 7371 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 14 1: Decrease Current HP by 6820 per tick ]]
            'Pyre of Nos',             -- [[NEC/89 - Mana: 6137 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 11 1: Decrease Current HP by 5624 per tick ]]
            'Soul Reaper\'s Pyre',     -- [[NEC/84 - Mana: 4314 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 8 1: Decrease Current HP by 3924 per tick ]]
            'Dread Pyre',              -- [[NEC/70 - Mana: 1093 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Dread Pyre 1 1: Decrease Current HP by 956 per tick ]]
            'Funeral Pyre of Kelador', -- [[NEC/60 - Mana: 470 - Cast: 3s - Recast 1,5s - Duration: 48s+ - Resist: Fire -100 - Target: Single- Effects: 1: Decrease Current HP by 310 per tick ]]
            'Ignite Blood',            -- [[SHD/61 NEC/47 - Mana: 218 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Fire -100 - Target: Single- Effects: 1: Decrease Current HP by 125 per tick ]]
            'Boil Blood',              -- [[SHD/53 NEC/28 - Mana: 136 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Fire -100 - Target: Single- Effects: 1: Decrease Current HP by 67 per tick ]]
            'Heat Blood',              -- [[SHD/28 NEC/10 - Mana: 88 - Cast: 3s - Recast 4s - Duration: 36s+ - Resist: Fire -100 - Target: Single- Effects: 1: Decrease Current HP by 43 per tick ]]
        },


    },

    { -- main magic dot. Slot 2
        Group = 'magic',

        Spells =
        {
            'Extermination',  -- [[NEC/122 - Mana: 11700 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 57 1: Increase Curse Counter by 40 2: Decrease Current HP by 11002 per tick ]]
            'Extinction',     -- [[NEC/117 - Mana: 9687 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 51 1: Increase Curse Counter by 36 2: Decrease Current HP by 9973 per tick ]]
            'Oblivion',       -- [[NEC/112 - Mana: 8173 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 45 1: Increase Curse Counter by 35 2: Decrease Current HP by 8614 per tick ]]
            'Inevitable End', -- [[NEC/107 - Mana: 6764 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 39 1: Increase Curse Counter by 32 2: Decrease Current HP by 7102 per tick ]]
            'Annihilation',   -- [[NEC/102 - Mana: 5590 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 33 1: Increase Curse Counter by 30 2: Decrease Current HP by 5847 per tick ]]
            'Termination',    -- [[NEC/97 - Mana: 4697 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 27 1: Increase Curse Counter by 30 2: Decrease Current HP by 4894 per tick ]]
            'Doom',           -- [[NEC/92 - Mana: 3666 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 21 1: Increase Curse Counter by 30 2: Decrease Current HP by 3805 per tick ]]
            'Demise',         -- [[NEC/87 - Mana: 2749 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 15 1: Increase Curse Counter by 30 2: Decrease Current HP by 2842 per tick ]]
            'Mortal Coil',    -- [[NEC/82 - Mana: 2178 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 9 1: Increase Curse Counter by 30 2: Decrease Current HP by 2243 per tick ]]
            'Dark Nightmare', -- [[NEC/67 - Mana: 585 - Cast: 3s - Recast 3s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 1 1: Increase Curse Counter by 30 2: Decrease Current HP by 591 per tick ]]
            'Horror',         -- [[NEC/63 - Mana: 450 - Cast: 3s - Recast 6s T4 - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Increase Curse Counter by 24 2: Decrease Current HP by 450 per tick ]]

        },


    },

    { -- main poison dot. Slot 3
        Group = 'venom',

        Spells =
        {
            'Luggald Venom',         -- [[NEC/125 - Mana: 12946 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Kedgefish Venom 56 1: Increase Poison Counter by 27 2: Decrease Current HP by 12318 per tick ]]
            'Hemorrhagic Venom',     -- [[NEC/120 - Mana: 10718 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Kedgefish Venom 50 1: Increase Poison Counter by 24 2: Decrease Current HP by 11166 per tick ]]
            'Crystal Crawler Venom', -- [[NEC/115 - Mana: 9064 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Kedgefish Venom 44 1: Increase Poison Counter by 22 2: Decrease Current HP by 9646 per tick ]]
            'Polybiad Venom',        -- [[NEC/110 - Mana: 7492 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Kedgefish Venom 38 1: Increase Poison Counter by 20 2: Decrease Current HP by 7953 per tick ]]
            'Glistenwing Venom',     -- [[NEC/105 - Mana: 6193 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Kedgefish Venom 32 1: Increase Poison Counter by 18 2: Decrease Current HP by 6558 per tick ]]
            'Binaesa Venom',         -- [[NEC/100 - Mana: 5119 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Kedgefish Venom 26 1: Increase Poison Counter by 18 2: Decrease Current HP by 5408 per tick ]]
            'Naeya Venom',           -- [[NEC/95 - Mana: 4231 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Kedgefish Venom 20 1: Increase Poison Counter by 18 2: Decrease Current HP by 4459 per tick ]]
            'Argendev\'s Venom',     -- [[NEC/90 - Mana: 3497 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Kedgefish Venom 14 1: Increase Poison Counter by 18 2: Decrease Current HP by 3677 per tick ]]
            'Slitheren Venom',       -- [[NEC/85 - Mana: 2884 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Kedgefish Venom 8 1: Increase Poison Counter by 18 2: Decrease Current HP by 3032 per tick ]]
            'Chaos Venom',           -- [[NEC/70 - Mana: 566 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 1 1: Increase Poison Counter by 18 2: Decrease Current HP by 473 per tick ]]
            'Blood of Thule',        -- [[NEC/65 - Mana: 436 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -50 - Target: Single- Effects: Push: 0,5 1: Increase Poison Counter by 9 2: Decrease Current HP by 360 per tick ]]
            'Venom of the Snake',    -- [[SHM/37 NEC/34 BST/52 - Mana: 203 - Cast: 3s - Recast 1,5s - Duration: 36s+ - Resist: Poison - Target: Single- Effects: Stacking: Blood of Saryrn 3 1: Increase Poison Counter by 7 2: Decrease Current HP by 33 3: Decrease Current HP by 220 per tick ]]
            'Poison Bolt',           -- [[NEC/4 - Mana: 18 - Cast: 2s - Recast 1,5s - Duration: 24s+ - Resist: Poison - Target: Single- Effects: Push: 0,5 1: Increase Poison Counter by 1 2: Decrease Current HP by 6 3: Decrease Current HP by 10 per tick ]]
        },


    },

    { -- secondary poison dot. Slot 4
        Group = 'haze',

        Spells =
        {
            'Uncia\'s Pallid Haze',       -- [[NEC/124 - Mana: 8774 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -75 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 32 1: Increase Poison Counter by 27 2: Decrease Current HP by 9169 per tick ]]
            'Zelnithak\'s Pallid Haze',   -- [[NEC/119 - Mana: 7264 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -75 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 29 1: Increase Poison Counter by 24 2: Decrease Current HP by 8311 per tick ]]
            'Dracnia\'s Pallid Haze',     -- [[NEC/114 - Mana: 6128 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -75 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 26 1: Increase Poison Counter by 22 2: Decrease Current HP by 7179 per tick ]]
            'Bomoda\'s Pallid Haze',      -- [[NEC/109 - Mana: 5053 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -75 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 23 1: Increase Poison Counter by 20 2: Decrease Current HP by 5919 per tick ]]
            'Plexipharia\'s Pallid Haze', -- [[NEC/104 - Mana: 4172 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -75 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 20 1: Increase Poison Counter by 18 2: Decrease Current HP by 4881 per tick ]]
            'Halstor\'s Pallid Haze',     -- [[NEC/99 - Mana: 3444 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -75 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 17 1: Increase Poison Counter by 18 2: Decrease Current HP by 4025 per tick ]]
            'Ivrikdal\'s Pallid Haze',    -- [[NEC/94 - Mana: 2783 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -75 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 14 1: Increase Poison Counter by 18 2: Decrease Current HP by 3252 per tick ]]
            'Arachne\'s Pallid Haze',     -- [[NEC/89 - Mana: 2217 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -75 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 11 1: Increase Poison Counter by 18 2: Decrease Current HP by 2588 per tick ]]
            'Fellid\'s Pallid Haze',      -- [[NEC/84 - Mana: 1764 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Poison -75 - Target: Single- Effects: Stacking: Visziaj's Pallid Haze 8 1: Increase Poison Counter by 18 2: Decrease Current HP by 2059 per tick ]]
            'Venom of Anguish',           -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
        },


    },

    { -- lifetap dot. Slot 5
        Group = 'grasp',

        Spells =
        {
            'Helmsbane\'s Grasp',     -- [[NEC/122 - Mana: 17748 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 56 3: Decrease Current HP by 9097 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 30253 ]]
            'The Protector\'s Grasp', -- [[NEC/117 - Mana: 14693 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 50 3: Decrease Current HP by 8247 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 24946 ]]
            'Tserrina\'s Grasp',      -- [[NEC/112 - Mana: 12456 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 44 3: Decrease Current HP by 7124 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 20571 ]]
            'Bomoda\'s Grasp',        -- [[NEC/107 - Mana: 9965 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 38 3: Decrease Current HP by 5619 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 16225 ]]
            'Plexipharia\'s Grasp',   -- [[NEC/102 - Mana: 8135 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 32 3: Decrease Current HP by 4530 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 13080 ]]
            'Halstor\'s Grasp',       -- [[NEC/97 - Mana: 6641 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 26 3: Decrease Current HP by 3652 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 10545 ]]
            'Ivrikdal\'s Grasp',      -- [[NEC/92 - Mana: 5421 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 20 3: Decrease Current HP by 2944 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 8501 ]]
            'Arachne\'s Grasp',       -- [[NEC/87 - Mana: 4425 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 14 3: Decrease Current HP by 2373 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 6852 ]]
            'Fellid\'s Grasp',        -- [[NEC/82 - Mana: 3540 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 8 3: Decrease Current HP by 1873 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 5408 ]]
            'Ancient: Curse of Mori', -- [[NEC/70 - Mana: 625 - Cast: 3s - Recast 6s T5 - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: Stacking: Curse of Mortality 2 1: Increase Curse Counter by 30 2: Decrease Current HP by 639 per tick ]]
            'Fang of Death',          -- [[NEC/68 - Mana: 750 - Cast: 6s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dyn`leth's Grasp 1 3: Decrease Current HP by 370 per tick 4: Return 82,5% of Spell Damage as HP, Max Per Hit: 1068 ]]
        },


    },

    { -- lifetap dot. Slot 6
        Group = 'leech',

        Spells =
        {
            'Ghastly Leech',  -- [[NEC/121 - Mana: 16210 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dark Leech 14 Recourse: Ghastly Leech Recourse 3: Decrease Current HP by 8500 per tick ]]
            'Twilight Leech', -- [[NEC/120 - Mana: 13420 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dark Leech 11 Recourse: Twilight Leech Recourse 3: Decrease Current HP by 7705 per tick ]]
            'Frozen Leech',   -- [[NEC/115 - Mana: 11350 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dark Leech 8 Recourse: Frozen Leech Recourse 3: Decrease Current HP by 6656 per tick ]]
            'Ashen Leech',    -- [[NEC/110 - Mana: 7592 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dark Leech 5 Recourse: Ashen Leech Recourse 3: Decrease Current HP by 4844 per tick ]]
            'Dark Leech',     -- [[NEC/100 - Mana: 4180 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Magic -200 - Target: Single- Effects: Stacking: Dark Leech 2 Recourse: Dark Leech Recourse 3: Decrease Current HP by 2146 per tick ]]
            'Vampiric Curse', -- [[SHD/57 NEC/29 - Mana: 144 - Cast: 4s - Recast 10s - Duration: 54s+ - Resist: Magic -200 - Target: Single- Effects: 3: Decrease Current HP by 21 per tick 4: Return 100% of Spell Damage as HP, Max Per Hit: 74 ]]
            'Leech',          -- [[NEC/9 - Mana: 72 - Cast: 2,4s - Recast 10s - Duration: 54s+ - Resist: Magic -200 - Target: Single- Effects: 3: Decrease Current HP by 8 per tick 4: Return 100% of Spell Damage as HP, Max Per Hit: 28 ]]
        },


    },

    { -- Mana Drain. Slot 7
        Group = 'manatap',

        Spells =
        {
            'Mind Disintegrate',  -- [[NEC/124 - Mana: 3324 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Mind Disintegrate Recourse 3: Decrease Current Mana by 5030 ]]
            'Mind Atrophy',       -- [[NEC/119 - Mana: 2752 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Mind Atrophy Recourse 3: Decrease Current Mana by 4148 ]]
            'Mind Erosion',       -- [[NEC/114 - Mana: 2345 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Mind Erosion Recourse 3: Decrease Current Mana by 3420 ]]
            'Mind Excoriation',   -- [[NEC/109 - Mana: 1876 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Mind Excoriation Recourse 3: Decrease Current Mana by 2297 ]]
            'Mind Extraction',    -- [[NEC/104 - Mana: 1562 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Mind Extraction Recourse 3: Decrease Current Mana by 1894 ]]
            'Mind Strip',         -- [[NEC/99 - Mana: 1375 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Mind Strip Recourse 3: Decrease Current Mana by 1636 ]]
            'Mind Abrasion',      -- [[NEC/94 - Mana: 1267 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Mind Abrasion Recourse 3: Decrease Current Mana by 1319 ]]
            'Thought Flay',       -- [[NEC/89 - Mana: 1119 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Thought Flay Recourse 3: Decrease Current Mana by 1034 ]]
            'Mind Decomposition', -- [[NEC/84 - Mana: 1143 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Mind Decomposition Recourse 3: Decrease Current Mana by 587 ]]
            'Mind Flay',          -- [[NEC/70 - Mana: 700 - Cast: 6s - Recast 60s T11 - Duration: 0s - Resist: Disease -200 - Target: Single- Effects: Recourse: Mind Flay Recourse 3: Decrease Current Mana by 360 ]]
        },


    },

    { -- Damage absorb shield. Slot 8
        Group = 'shield',

        Spells =
        {
            'Shield of Inescapability', -- [[NEC/122 WIZ/122 MAG/122 ENC/122 - Mana: 4258 - Cast: 4,5s - Recast 1,5s - Duration: 75m+ - Resist: n/a - Target: Self- Effects: 1: Absorb Spell Damage: 60% over 32000, Total: 374000 2: Absorb Melee Damage: 75% over 51000, Total: 630000 ]]
            'Shield of Inevitability',  -- [[NEC/117 WIZ/117 MAG/117 ENC/117 - Mana: 3445 - Cast: 4,5s - Recast 1,5s - Duration: 90m+ - Resist: n/a - Target: Self- Effects: 1: Absorb Spell Damage: 60% over 30000, Total: 271000 2: Absorb Melee Damage: 75% over 46000, Total: 511000 ]]
            'Shield of Destiny',        -- [[NEC/112 WIZ/112 MAG/112 ENC/112 - Mana: 2935 - Cast: 4,5s - Recast 1,5s - Duration: 90m+ - Resist: n/a - Target: Self- Effects: 1: Absorb Spell Damage: 60% over 30000, Total: 245261 2: Absorb Melee Damage: 75% over 35000, Total: 364667 ]]
            'Shield of Order',          -- [[NEC/107 WIZ/107 MAG/107 ENC/107 - Mana: 1174 - Cast: 4,5s - Recast 1,5s - Duration: 90m+ - Resist: n/a - Target: Self- Effects: 1: Absorb Spell Damage: 60% over 15000, Total: 211866 2: Absorb Melee Damage: 75% over 23000, Total: 191521 ]]
            'Shield of Consequence',    -- [[NEC/102 WIZ/102 MAG/102 ENC/102 - Mana: 977 - Cast: 4,5s - Recast 1,5s - Duration: 90m+ - Resist: n/a - Target: Self- Effects: 1: Absorb Spell Damage: 60% over 12000, Total: 146668 2: Absorb Melee Damage: 75% over 12000, Total: 112304 ]]
            'Shield of Fate',           -- [[NEC/97 WIZ/97 MAG/97 ENC/97 - Mana: 860 - Cast: 4,5s - Recast 1,5s - Duration: 90m+ - Resist: n/a - Target: Self- Effects: 1: Absorb Spell Damage: 60% over 8000, Total: 123750 2: Absorb Melee Damage: 75% over 10000, Total: 94756 ]]
        },


    },

    { -- Alliance. Slot 9
        Group = 'alliance',

        Spells =
        {
            'Malevolent Conjunction', -- [[NEC/117 - Mana: 23521 - Cast: 3s - Recast 60s T21 - Duration: 18s+ - Resist: Magic -15 - Target: Single- Effects: Stacking: Malevolent Alliance 13 Max Hits: 4 Matching Spells 1: Increase Spell Damage Taken by 54886 (v484, After Crit) 2: Limit Target: Single 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Level: 111 6: Limit Max Level: 125 (lose 100% per level) 7: Limit Min Duration: 18s 8: Limit Min Mana Cost: 10 9: Limit Effect: Current HP less than -1950 10: Limit Caster Class: NEC 11: Limit Caster: Exclude Self 12: Cast: Malevolent Resolution IV Azia if Max Hits Used ]]
            'Malevolent Coalition',   -- [[NEC/114 - Mana: 19031 - Cast: 3s - Recast 60s T21 - Duration: 18s+ - Resist: Magic -10 - Target: Single- Effects: Stacking: Malevolent Alliance 10 Max Hits: 4 Matching Spells 1: Increase Spell Damage Taken by 45257 (v484, After Crit) 2: Limit Target: Single 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Level: 106 6: Limit Max Level: 120 (lose 100% per level) 7: Limit Min Duration: 18s 8: Limit Min Mana Cost: 10 9: Limit Effect: Current HP less than -1950 10: Limit Caster Class: NEC 11: Limit Caster: Exclude Self 12: Cast: Malevolent Resolution III Azia if Max Hits Used ]]
            'Malevolent Covenant',    -- [[NEC/107 - Mana: 15756 - Cast: 3s - Recast 60s T21 - Duration: 18s+ - Resist: Magic -10 - Target: Single- Effects: Stacking: Malevolent Alliance 4 Max Hits: 4 Matching Spells 1: Increase Spell Damage Taken by 37318 (v484, After Crit) 2: Limit Target: Single 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Level: 101 6: Limit Max Level: 115 (lose 100% per level) 7: Limit Min Duration: 18s 8: Limit Min Mana Cost: 10 9: Limit Effect: Current HP less than -1760 10: Limit Caster Class: NEC 11: Limit Caster: Exclude Self 12: Cast: Malevolent Resolution if Max Hits Used ]]
            'Malevolent Alliance',    -- [[NEC/102 - Mana: 13243 - Cast: 3s - Recast 60s T21 - Duration: 18s+ - Resist: Magic -10 - Target: Single- Effects: Stacking: Malevolent Alliance 1 Max Hits: 4 Matching Spells 1: Increase Spell Damage Taken by 32237 (v484, After Crit) 2: Limit Target: Single 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Level: 96 6: Limit Max Level: 115 (lose 100% per level) 7: Limit Min Duration: 18s 8: Limit Min Mana Cost: 10 9: Limit Effect: Current HP less than -1600 10: Limit Caster Class: NEC 11: Limit Caster: Exclude Self 12: Cast: Malevolent Fulmination if Max Hits Used ]]

        },


    },

    { -- manadrain dot. Slot 7/8/9 if any of alliance or shield or manatap are disabled.
        Group = 'ignite',

        Spells =
        {
            'Ignite Remembrance', -- [[NEC/124 - Mana: 4628 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by up to 7834 (7,2 HP per 1 Target Mana) 2: Decrease Current HP by 7169 per tick ]]
            'Ignite Cognition',   -- [[NEC/119 - Mana: 3831 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by up to 6409 (6,5 HP per 1 Target Mana) 2: Decrease Current HP by 5911 per tick ]]
            'Ignite Intellect',   -- [[NEC/114 - Mana: 3264 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by up to 5021 (5,9 HP per 1 Target Mana) 2: Decrease Current HP by 4874 per tick ]]
            'Ignite Memories',    -- [[NEC/109 - Mana: 2611 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by up to 2776 (5,4 HP per 1 Target Mana) 2: Decrease Current HP by 4019 per tick ]]
            'Ignite Synapses',    -- [[NEC/104 - Mana: 2174 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by up to 1781 (4,2 HP per 1 Target Mana) 2: Decrease Current HP by 3314 per tick ]]
            'Ignite Thoughts',    -- [[NEC/99 - Mana: 1914 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by up to 1468 (4 HP per 1 Target Mana) 2: Decrease Current HP by 2863 per tick ]]
            'Ignite Potential',   -- [[NEC/94 - Mana: 1764 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by up to 877 (3,2 HP per 1 Target Mana) 2: Decrease Current HP by 2361 per tick ]]
            'Thoughtburn',        -- [[NEC/89 - Mana: 1481 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by up to 650 (3,2 HP per 1 Target Mana) 2: Decrease Current HP by 1724 per tick ]]
            'Ignite Energy',      -- [[NEC/84 - Mana: 898 - Cast: 3s - Recast 1,5s - Duration: 30s+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by up to 314 (3,2 HP per 1 Target Mana) 2: Decrease Current HP by 950 per tick ]]

        },


    },

    { -- Slot 8/9 if any of alliance or shield are disabled
        Group = 'scourge',

        Spells =
        {
            'Scourge of Destiny', -- [[NEC/108 - Mana: 2585 - Cast: 3s - Recast 12s T18 - Duration: 42s+ - Resist: Magic -60 - Target: Single- Effects: Stacking: Scourge of Fates 4 1: Increase Curse Counter by 30 2: Decrease Current HP by 4527 per tick (If Not Vampire or Undead) 3: Decrease Current HP by 7109 per tick (If Vampire or Undead) ]]
            'Scourge of Fates',   -- [[NEC/97 - Mana: 1365 - Cast: 3s - Recast 12s T18 - Duration: 42s+ - Resist: Magic -60 - Target: Single- Effects: Stacking: Scourge of Fates 1 1: Increase Curse Counter by 30 2: Decrease Current HP by 2347 per tick (If Not Vampire or Undead) 3: Decrease Current HP by 3685 per tick (If Vampire or Undead) ]]
            'Eternities Torment', -- [[NEC/27 - Mana: 140 - Cast: 3s - Recast 1,5s - Duration: 2,1m+ - Resist: Magic -100 - Target: Undead- Effects: 1: Decrease Current HP by 30 per tick ]]
        },


    },

    { -- Slot 9 when none of mana tap, alliance or shield enabled
        Group = 'corruption',

        Spells =
        {
            'Deterioration', -- [[NEC/122 - Mana: 3468 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Corruption -10 - Target: Single- Effects: 1: Decrease Current HP by 3864 per tick (If Not Plant) 2: Decrease Current HP by 9632 per tick (If Plant) 3: Increase Poison Counter by 36 ]]
            'Decomposition', -- [[NEC/117 - Mana: 2871 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Corruption -10 - Target: Single- Effects: 1: Decrease Current HP by 3187 per tick (If Not Plant) 2: Decrease Current HP by 7942 per tick (If Plant) 3: Increase Poison Counter by 32 ]]
            'Miasma',        -- [[NEC/112 - Mana: 2446 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Corruption -10 - Target: Single- Effects: 1: Decrease Current HP by 2628 per tick (If Not Plant) 2: Decrease Current HP by 6549 per tick (If Plant) 3: Increase Poison Counter by 29 ]]
            'Effluvium',     -- [[NEC/107 - Mana: 2038 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Corruption -10 - Target: Single- Effects: 1: Decrease Current HP by 2167 per tick (If Not Plant) 2: Decrease Current HP by 5400 per tick (If Plant) 3: Increase Poison Counter by 26 ]]
            'Liquefaction',  -- [[NEC/102 - Mana: 1697 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Corruption -10 - Target: Single- Effects: 1: Decrease Current HP by 1787 per tick (If Not Plant) 2: Decrease Current HP by 4452 per tick (If Plant) 3: Increase Poison Counter by 24 ]]
            'Dissolution',   -- [[NEC/97 - Mana: 1494 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Corruption -5 - Target: Single- Effects: 1: Decrease Current HP by 1544 per tick (If Not Plant) 2: Decrease Current HP by 2650 per tick (If Plant) 3: Increase Poison Counter by 24 ]]
            'Mortification', -- [[NEC/92 - Mana: 1377 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Corruption -5 - Target: Single- Effects: 1: Decrease Current HP by 1273 per tick (If Not Plant) 2: Decrease Current HP by 2186 per tick (If Plant) 3: Increase Poison Counter by 24 ]]
            'Fetidity',      -- [[NEC/87 - Mana: 1075 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Corruption -5 - Target: Single- Effects: 1: Decrease Current HP by 846 per tick (If Not Plant) 2: Decrease Current HP by 1452 per tick (If Plant) 3: Increase Poison Counter by 24 ]]
            'Putrescence',   -- [[NEC/82 - Mana: 860 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Corruption -5 - Target: Single- Effects: 1: Decrease Current HP by 615 per tick (If Not Plant) 2: Decrease Current HP by 1056 per tick (If Plant) ]]
        },


    },

    { -- Slot 10
        Group = 'composite',

        Spells =
        {
            'Ecliptic Paroxysm',   -- [[NEC/116 - Mana: 21600 - Cast: 3s - Recast 60s T20 - Duration: 6s+ - Resist: Unresistable - Target: Single- Effects: 1: Cast: Highest Rank of Group - Ecliptic Paroxysm (v470) 2: Decrease Current HP by 1 per tick 3: Stacking: Twincast Blocker ]]
            'Composite Paroxysm',  -- [[NEC/111 - Mana: 18783 - Cast: 3s - Recast 60s T20 - Duration: 6s+ - Resist: Unresistable - Target: Single- Effects: 1: Cast: Highest Rank of Group - Composite Paroxysm (v470) 2: Decrease Current HP by 1 per tick 3: Stacking: Twincast Blocker ]]
            'Dissident Paroxysm',  -- [[NEC/106 - Mana: 16333 - Cast: 3s - Recast 60s T20 - Duration: 6s+ - Resist: Unresistable - Target: Single- Effects: 1: Cast: Highest Rank of Group - Dissident Paroxysm (v470) 2: Decrease Current HP by 1 per tick 3: Stacking: Twincast Blocker ]]
            'Dichotomic Paroxysm', -- [[NEC/101 - Mana: 14203 - Cast: 3s - Recast 60s T20 - Duration: 6s+ - Resist: Unresistable - Target: Single- Effects: 1: Cast: Highest Rank of Group - Dichotomic Paroxysm (v470) 2: Decrease Current HP by 1 per tick 3: Stacking: Twincast Blocker ]]
        },


    },

    { -- Slot 11
        Group = 'combodisease',

        Spells =
        {
            'Fleshrot\'s Grip of Decay', -- [[NEC/120 - Mana: 400 - Cast: 3s - Recast 24s T5 - Duration: 6s+ - Resist: Unresistable - Target: Single- Effects: Hate: -1 1: Cast: Highest Rank of Group - Fleshrot's Decay (v470) 2: Cast: Highest Rank of Group - Grip of Quietus (v470) 3: Decrease Current HP by 1 per tick 4: Stacking: Twincast Blocker ]]
            'Danvid\'s Grip of Decay',   -- [[NEC/115 - Mana: 350 - Cast: 3s - Recast 24s T5 - Duration: 6s+ - Resist: Unresistable - Target: Single- Effects: Hate: -1 1: Cast: Highest Rank of Group - Danvid's Decay (v470) 2: Cast: Highest Rank of Group - Grip of Zorglim (v470) 3: Decrease Current HP by 1 per tick 4: Stacking: Twincast Blocker ]]
            'Mourgis\' Grip of Decay',   -- [[NEC/110 - Mana: 250 - Cast: 3s - Recast 24s T5 - Duration: 6s+ - Resist: Unresistable - Target: Single- Effects: Hate: -1 1: Cast: Highest Rank of Group - Mourgis' Decay (v470) 2: Cast: Highest Rank of Group - Grip of Kraz (v470) 3: Decrease Current HP by 1 per tick ]]
            'Livianus\' Grip of Decay',  -- [[NEC/104 - Mana: 200 - Cast: 3s - Recast 24s T6 - Duration: 6s+ - Resist: Unresistable - Target: Single- Effects: Hate: -1 1: Cast: Highest Rank of Group - Livianus' Decay (v470) 2: Cast: Highest Rank of Group - Grip of Jabaum (v470) 3: Decrease Current HP by 1 per tick ]]

        },


    },

    { -- Slot 12
        Group = 'wounds',

        Spells =
        {
            'Putrefying Wounds',  -- [[NEC/125 - Mana: 9995 - Cast: 3s - Recast 1,5s - Duration: 96s+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 29 1: Decrease Current HP by 6764 per tick 4: Increase Curse Counter by 27 7: Cast: Putrefying Proliferation on Duration Fade ]]
            'Infected Wounds',    -- [[NEC/120 - Mana: 8275 - Cast: 3s - Recast 1,5s - Duration: 96s+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 26 1: Decrease Current HP by 5853 per tick 4: Increase Curse Counter by 24 7: Cast: Infected Proliferation on Duration Fade ]]
            'Septic Wounds',      -- [[NEC/115 - Mana: 6982 - Cast: 3s - Recast 1,5s - Duration: 96s+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 23 1: Decrease Current HP by 5056 per tick 4: Increase Curse Counter by 22 7: Cast: Septic Proliferation on Duration Fade ]]
            'Cytotoxic Wounds',   -- [[NEC/110 - Mana: 5757 - Cast: 3s - Recast 1,5s - Duration: 96s+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 20 1: Decrease Current HP by 4159 per tick 4: Increase Curse Counter by 20 7: Cast: Cytotoxic Proliferation on Duration Fade ]]
            'Mortiferous Wounds', -- [[NEC/105 - Mana: 4541 - Cast: 3s - Recast 1,5s - Duration: 96s+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 17 1: Decrease Current HP by 3204 per tick 7: Cast: Violent Proliferation on Duration Fade ]]
            'Pernicious Wounds',  -- [[NEC/100 - Mana: 3432 - Cast: 3s - Recast 1,5s - Duration: 96s+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 14 1: Decrease Current HP by 2318 per tick 7: Cast: Violent Proliferation on Duration Fade ]]
            'Necrotizing Wounds', -- [[NEC/95 - Mana: 2594 - Cast: 3s - Recast 1,5s - Duration: 96s+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 11 1: Decrease Current HP by 1764 per tick 7: Cast: Violent Necrosis on Duration Fade ]]
            'Splirt',             -- [[NEC/90 - Mana: 1847 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 8 11: Decrease Current HP by 87 per tick (Growing to 1759 @ 88/tick) ]]
            'Splart',             -- [[NEC/85 - Mana: 1375 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 5 11: Decrease Current HP by 63 per tick (Growing to 1279 @ 64/tick) ]]
            'Splort',             -- [[NEC/80 - Mana: 914 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -100 - Target: Single- Effects: Stacking: Necrotizing Wounds 2 11: Decrease Current HP by 39 per tick (Growing to 799 @ 40/tick) ]]
        },


    },

    { -- Slot 12 no wounds, raid spells
        Group = 'pyrelong',

        Spells =
        {
            'Pyre of the Abandoned', -- [[NEC/123 - Mana: 10068 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 56 1: Decrease Current HP by 8167 per tick ]]
            'Pyre of the Neglected', -- [[NEC/118 - Mana: 8336 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 50 1: Decrease Current HP by 7403 per tick ]]
            'Pyre of the Wretched',  -- [[NEC/113 - Mana: 7101 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 44 1: Decrease Current HP by 6394 per tick ]]
            'Pyre of the Fereth',    -- [[NEC/108 - Mana: 5966 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 38 1: Decrease Current HP by 5272 per tick ]]
            'Pyre of the Lost',      -- [[NEC/103 - Mana: 5012 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 32 1: Decrease Current HP by 4348 per tick ]]
            'Pyre of the Forsaken',  -- [[NEC/98 - Mana: 4211 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 26 1: Decrease Current HP by 3586 per tick ]]
            'Pyre of the Piq\'a',    -- [[NEC/93 - Mana: 3459 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 20 1: Decrease Current HP by 2853 per tick ]]
            'Pyre of the Bereft',    -- [[NEC/88 - Mana: 2840 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 14 1: Decrease Current HP by 2270 per tick ]]
            'Pyre of the Forgotten', -- [[NEC/83 - Mana: 2333 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 8 1: Decrease Current HP by 1806 per tick ]]
            'Pyre of Mori',          -- [[NEC/69 - Mana: 560 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Pyre of Mori 1 1: Decrease Current HP by 419 per tick ]]
            'Night Fire',            -- [[NEC/65 - Mana: 572 - Cast: 3s - Recast 1,5s - Duration: 54s+ - Resist: Fire -100 - Target: Single- Effects: 1: Decrease Current HP by 335 per tick ]]
        },


    },

    { -- Slot 12 no wounds, raid spells (swapped with pyrelong automatically)
        Group = 'fireshadow',

        Spells =
        {
            'Raging Shadow',      -- [[NEC/125 - Mana: 8884 - Cast: 3s - Recast 1,5s - Duration: 84s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Searing Shadow 28 1: Increase Spell Damage Taken by 1133 (v297, Before Crit) 2: Decrease Current HP by 8549 per tick 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Mana Cost: 10 6: Limit Type: Exclude Combat Skills 7: Limit Target: Lifetap ]]
            'Scalding Shadow',    -- [[NEC/120 - Mana: 7355 - Cast: 3s - Recast 1,5s - Duration: 84s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Searing Shadow 25 1: Increase Spell Damage Taken by 934 (v297, Before Crit) 2: Decrease Current HP by 7749 per tick 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Mana Cost: 10 6: Limit Type: Exclude Combat Skills 7: Limit Target: Lifetap ]]
            'Broiling Shadow',    -- [[NEC/115 - Mana: 6265 - Cast: 3s - Recast 1,5s - Duration: 84s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Searing Shadow 22 1: Increase Spell Damage Taken by 677 (v297, Before Crit) 2: Decrease Current HP by 6694 per tick 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Mana Cost: 10 6: Limit Type: Exclude Combat Skills 7: Limit Target: Lifetap ]]
            'Burning Shadow',     -- [[NEC/110 - Mana: 5166 - Cast: 3s - Recast 1,5s - Duration: 84s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Searing Shadow 19 1: Increase Spell Damage Taken by 484 (v297, Before Crit) 2: Decrease Current HP by 5519 per tick 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Mana Cost: 10 6: Limit Type: Exclude Combat Skills 7: Limit Target: Lifetap ]]
            'Smouldering Shadow', -- [[NEC/105 - Mana: 4300 - Cast: 3s - Recast 1,5s - Duration: 84s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Searing Shadow 16 1: Increase Spell Damage Taken by 351 (v297, Before Crit) 2: Decrease Current HP by 4550 per tick 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Mana Cost: 10 6: Limit Type: Exclude Combat Skills 7: Limit Target: Lifetap ]]
            'Coruscating Shadow', -- [[NEC/100 - Mana: 3546 - Cast: 3s - Recast 1,5s - Duration: 84s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Searing Shadow 13 1: Increase Spell Damage Taken by 303 (v297, Before Crit) 2: Decrease Current HP by 3751 per tick 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Mana Cost: 10 6: Limit Type: Exclude Combat Skills 7: Limit Target: Lifetap ]]
            'Blazing Shadow',     -- [[NEC/95 - Mana: 2887 - Cast: 3s - Recast 1,5s - Duration: 84s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Searing Shadow 10 1: Increase Spell Damage Taken by 250 (v297, Before Crit) 2: Decrease Current HP by 3024 per tick 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Mana Cost: 10 6: Limit Type: Exclude Combat Skills 7: Limit Target: Lifetap ]]
            'Blistering Shadow',  -- [[NEC/90 - Mana: 2320 - Cast: 3s - Recast 1,5s - Duration: 84s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Searing Shadow 7 1: Increase Spell Damage Taken by 207 (v297, Before Crit) 2: Decrease Current HP by 2402 per tick 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Mana Cost: 10 6: Limit Type: Exclude Combat Skills 7: Limit Target: Lifetap ]]
            'Scorching Shadow',   -- [[NEC/85 - Mana: 1447 - Cast: 3s - Recast 1,5s - Duration: 84s+ - Resist: Fire -100 - Target: Single- Effects: Stacking: Searing Shadow 4 1: Increase Spell Damage Taken by 171 (v297, Before Crit) 2: Decrease Current HP by 1502 per tick 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Min Mana Cost: 10 6: Limit Type: Exclude Combat Skills 7: Limit Target: Lifetap ]]
        },


    },

    { -- Slot 12 no wounds, group spells
        Group = 'swarm',

        Spells =
        {
            'Call Skeleton Thrall', -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Call Skeleton Mass',   -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Call Skeleton Horde',  -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Call Skeleton Army',   -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Call Skeleton Mob',    -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Call Skeleton Throng', -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Call Skeleton Host',   -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Call Skeleton Crush',  -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Call Skeleton Swarm',  -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
        },


    },

    { -- Slot 13
        Group = 'synergy',

        Spells =
        {
            'Decree for Blood',       -- [[NEC/125 - Mana: 4310 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Decree for Blood Recourse 1: Decrease Current HP by 36181 ]]
            'Proclamation for Blood', -- [[NEC/120 - Mana: 3568 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Proclamation for Blood Recourse 1: Decrease Current HP by 29834 ]]
            'Assert for Blood',       -- [[NEC/115 - Mana: 2683 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Assert for Blood Recourse 1: Decrease Current HP by 18040 ]]
            'Refute for Blood',       -- [[NEC/110 - Mana: 2146 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Refute for Blood Recourse 1: Decrease Current HP by 14229 ]]
            'Impose for Blood',       -- [[NEC/105 - Mana: 1787 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Impose for Blood Recourse 1: Decrease Current HP by 11732 ]]
            'Impel for Blood',        -- [[NEC/100 - Mana: 1574 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Impel for Blood Recourse 1: Decrease Current HP by 10134 ]]
            'Provocation for Blood',  -- [[NEC/95 - Mana: 1285 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Provocation for Blood Recourse 1: Decrease Current HP by 6030 ]]
            'Compel for Blood',       -- [[NEC/90 - Mana: 1094 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Compel for Blood Recourse 1: Decrease Current HP by 4369 ]]
            'Exigency for Blood',     -- [[NEC/85 - Mana: 872 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Exigency of Blood Recourse 1: Decrease Current HP by 3166 ]]
            'Call for Blood',         -- [[NEC/68 - Mana: 568 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: Recourse: Call for Blood Recourse 1: Decrease Current HP by 1770 ]]
        },


    },


    -- TODO: need to work these in when combo is an expansion behind
    {
        Group = 'decay',
        Spells =
        {
            'Goremand\'s Decay', -- [[NEC/121 - Mana: 9006 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 56 1: Increase Disease Counter by 27 2: Decrease Current HP by 10403 per tick ]]
            'Fleshrot\'s Decay', -- [[NEC/116 - Mana: 7457 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 50 1: Increase Disease Counter by 24 2: Decrease Current HP by 9430 per tick ]]
            'Danvid\'s Decay',   -- [[NEC/111 - Mana: 6413 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 44 1: Increase Disease Counter by 22 2: Decrease Current HP by 8146 per tick ]]
            'Mourgis\' Decay',   -- [[NEC/106 - Mana: 5390 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 38 1: Increase Disease Counter by 20 2: Decrease Current HP by 6716 per tick ]]
            'Livianus\' Decay',  -- [[NEC/101 - Mana: 4531 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 32 1: Increase Disease Counter by 18 2: Decrease Current HP by 5537 per tick ]]
            'Wuran\'s Decay',    -- [[NEC/96 - Mana: 3809 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 26 1: Increase Disease Counter by 18 2: Decrease Current HP by 4566 per tick ]]
            'Ulork\'s Decay',    -- [[NEC/91 - Mana: 3202 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 20 1: Increase Disease Counter by 18 2: Decrease Current HP by 3451 per tick ]]
            'Folasar\'s Decay',  -- [[NEC/86 - Mana: 2691 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 14 1: Increase Disease Counter by 18 2: Decrease Current HP by 2609 per tick ]]
            'Megrima\'s Decay',  -- [[NEC/81 - Mana: 2211 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 8 1: Increase Disease Counter by 18 2: Decrease Current HP by 2085 per tick ]]
            'Chaos Plague',      -- [[NEC/66 - Mana: 443 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Eranon's Decay 1 1: Increase Disease Counter by 18 2: Decrease Current HP by 292 per tick ]]
            'Dark Plague',       -- [[NEC/61 - Mana: 340 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease -50 - Target: Single- Effects: 1: Increase Disease Counter by 9 2: Decrease Current HP by 222 per tick ]]
            'Asystole',          -- [[SHD/60 NEC/40 - Mana: 98 - Cast: 3s - Recast 1,5s - Duration: 42s+ - Resist: Disease - Target: Single- Effects: 1: Increase Disease Counter by 4 2: Decrease STR by 40 3: Decrease AC by 4 to 5, Based on Class 4: Decrease Current HP by 62 per tick ]]
            'Scourge',           -- [[SHM/31 NEC/35 - Mana: 199 - Cast: 3s - Recast 1,5s - Duration: 72s+ - Resist: Disease - Target: Single- Effects: Stacking: Breath of Ultor 3 1: Increase Disease Counter by 4 2: Decrease Current HP by 98 per tick 3: Decrease Current HP by 58 ]]
            'Heart Flutter',     -- [[SHD/36 NEC/13 - Mana: 41 - Cast: 3s - Recast 7s - Duration: 36s+ - Resist: Disease - Target: Single- Effects: 2: Decrease STR by 20 3: Decrease AC by 2 to 2, Based on Class 4: Decrease Current HP by 24 per tick ]]
        },
        Options = {
            opt = 'USEDOTS',
            Gem = function(lvl) return lvl <= 60 and 2 or nil end
        }
    },

    {
        Group = 'grip',
        Spells =
        {
            'Grip of Terrastride', -- [[NEC/121 - Mana: 6522 - Cast: 3s - Recast 1,5s - Duration: 60s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Grip of Mori 20 1: Increase Disease Counter by 27 2: Decrease STR by 284 3: Decrease AC by 48 to 64, Based on Class 4: Decrease Current HP by 8775 per tick ]]
            'Grip of Quietus',     -- [[NEC/116 - Mana: 5400 - Cast: 3s - Recast 1,5s - Duration: 60s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Grip of Mori 17 1: Increase Disease Counter by 24 2: Decrease STR by 234 3: Decrease AC by 40 to 53, Based on Class 4: Decrease Current HP by 7592 per tick ]]
            'Grip of Zorglim',     -- [[NEC/111 - Mana: 4556 - Cast: 3s - Recast 1,5s - Duration: 60s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Grip of Mori 14 1: Increase Disease Counter by 22 2: Decrease STR by 203 3: Decrease AC by 29 to 38, Based on Class 4: Decrease Current HP by 6558 per tick ]]
            'Grip of Kraz',        -- [[NEC/106 - Mana: 3706 - Cast: 3s - Recast 1,5s - Duration: 60s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Grip of Mori 11 1: Increase Disease Counter by 20 2: Decrease STR by 175 3: Decrease AC by 23 to 30, Based on Class 4: Decrease Current HP by 5287 per tick ]]
            'Grip of Jabaum',      -- [[NEC/101 - Mana: 2825 - Cast: 3s - Recast 1,5s - Duration: 60s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Grip of Mori 8 1: Increase Disease Counter by 18 2: Decrease STR by 139 3: Decrease AC by 18 to 23, Based on Class 4: Decrease Current HP by 3996 per tick ]]
            'Grip of Zalikor',     -- [[NEC/96 - Mana: 2196 - Cast: 3s - Recast 1,5s - Duration: 60s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Grip of Mori 5 1: Increase Disease Counter by 18 2: Decrease STR by 131 3: Decrease AC by 16 to 22, Based on Class 4: Decrease Current HP by 3067 per tick ]]
            'Grip of Zargo',       -- [[NEC/91 - Mana: 1141 - Cast: 3s - Recast 1,5s - Duration: 60s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Grip of Mori 2 1: Increase Disease Counter by 18 2: Decrease STR by 116 3: Decrease AC by 14 to 18, Based on Class 4: Decrease Current HP by 1582 per tick ]]
            'Grip of Mori',        -- [[NEC/67 - Mana: 325 - Cast: 3s - Recast 1,5s - Duration: 60s+ - Resist: Disease -50 - Target: Single- Effects: Stacking: Grip of Mori 1 1: Increase Disease Counter by 18 2: Decrease STR by 70 3: Decrease AC by 8 to 11, Based on Class 4: Decrease Current HP by 207 per tick ]]

        },
        Options = { opt = 'USEDOTS' }
    },

    {
        Group = 'aedisease',
        Spells =
        {
            'Infectious Cloud', -- [[SHM/15 NEC/15 - Mana: 78 - Cast: 2,75s - Recast 1,5s - Duration: 2,1m+ - Resist: Disease - Target: Target AE (4)- Effects: 1: Increase Disease Counter by 1 2: Decrease Current HP by 5 per tick 3: Decrease Current HP by 20 ]]
            'Disease Cloud',    -- [[SHD/5 NEC/1 - Mana: 10 - Cast: 1,5s - Recast 6s - Duration: 6m+ - Resist: Disease - Target: Single- Effects: 1: Increase Disease Counter by 1 2: Decrease Current HP by 5 3: Decrease Current HP by 1 per tick ]]
        },
        Options = { opt = 'USEDOTS' }
    },

    -- Lifetaps
    {
        Group = 'tapee',
        Spells =
        {
            'Soullash',   -- [[NEC/123 - Mana: 4704 - Cast: 3s - Recast 12,5s T17 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: 1: Decrease Current HP by 25661 2: Return 80% of Spell Damage as HP 3: Cast: Coagulated Essence (2% Chance) (v340) ]]
            'Soulflay',   -- [[NEC/118 - Mana: 3894 - Cast: 3s - Recast 12,5s T17 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: 1: Decrease Current HP by 21159 2: Return 80% of Spell Damage as HP 3: Cast: Coagulated Essence (2% Chance) (v340) ]]
            'Soulgouge',  -- [[NEC/113 - Mana: 2928 - Cast: 3s - Recast 12,5s T17 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: 1: Decrease Current HP by 12794 2: Return 80% of Spell Damage as HP 3: Cast: Coagulated Essence (2% Chance) (v340) ]]
            'Soulsiphon', -- [[NEC/108 - Mana: 2342 - Cast: 3s - Recast 12,5s T17 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: 1: Decrease Current HP by 9284 2: Return 80% of Spell Damage as HP 3: Cast: Coagulated Essence (2% Chance) (v340) ]]
            'Soulrend',   -- [[NEC/103 - Mana: 1949 - Cast: 3s - Recast 12,5s T17 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: 1: Decrease Current HP by 7655 2: Return 80% of Spell Damage as HP 3: Cast: Coagulated Essence (2% Chance) (v340) ]]
            'Soulrip',    -- [[NEC/98 - Mana: 1716 - Cast: 3s - Recast 12,5s T17 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: 1: Decrease Current HP by 6612 2: Return 80% of Spell Damage as HP 3: Cast: Coagulated Essence (2% Chance) (v340) ]]
            'Soulspike',  -- [[NEC/67 - Mana: 563 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 1204 ]]
        }
    },
    -- unused
    {
        Group = 'tap',
        Spells =
        {
            'Maraud Essence',             -- [[NEC/116 - Mana: 2911 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 13569 ]]
            'Draw Essence',               -- [[NEC/111 - Mana: 2189 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 8205 ]]
            'Consume Essence',            -- [[NEC/106 - Mana: 1824 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 6766 ]]
            'Hemorrhage Essence',         -- [[NEC/101 - Mana: 1519 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 5579 ]]
            'Plunder Essence',            -- [[NEC/96 - Mana: 1277 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 4498 ]]
            'Bleed Essence',              -- [[NEC/91 - Mana: 1177 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 3709 ]]
            'Divert Essence',             -- [[NEC/86 - Mana: 993 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 2722 ]]
            'Drain Essence',              -- [[NEC/81 - Mana: 864 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 2152 ]]
            'Touch of Night',             -- [[NEC/59 - Mana: 382 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 708 ]]
            'Deflux',                     -- [[NEC/54 - Mana: 299 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 535 ]]
            'Ancient: Touch of Orshilak', -- [[NEC/70 - Mana: 598 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 1300 ]]
            'Drain Soul',                 -- [[SHD/60 NEC/48 - Mana: 248 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 406 ]]
            'Drain Spirit',               -- [[SHD/57 NEC/39 - Mana: 213 - Cast: 3,2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 314 ]]
            'Spirit Tap',                 -- [[SHD/55 NEC/26 - Mana: 152 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 210 ]]
            'Siphon Life',                -- [[SHD/51 NEC/20 - Mana: 115 - Cast: 2,75s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 150 ]]
            'Lifedraw',                   -- [[SHD/29 NEC/12 - Mana: 86 - Cast: 2s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 105 ]]
            'Lifespike',                  -- [[SHD/15 NEC/3 - Mana: 13 - Cast: 1,5s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 12 ]]
            'Lifetap',                    -- [[SHD/8 NEC/1 - Mana: 8 - Cast: 1,5s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Lifetap- Effects: 1: Decrease Current HP by 6 ]]

        },
        Options = { Gem = function(lvl) return lvl <= 60 and 7 or nil end }
    },
    -- unused
    {
        Group = 'tapduration',
        Spells =
        {
            'Saryrn\'s Kiss',  -- [[NEC/62 - Mana: 550 - Cast: 6s - Recast 1,5s - Duration: 60s+ - Resist: Magic -200 - Target: Single- Effects: 3: Decrease Current HP by 200 per tick 4: Return 100% of Spell Damage as HP, Max Per Hit: 700 ]]
            'Vexing Mordinia', -- [[NEC/57 - Mana: 495 - Cast: 5,5s - Recast 1,5s - Duration: 54s+ - Resist: Magic -200 - Target: Single- Effects: 3: Decrease Current HP by 122 per tick 4: Return 100% of Spell Damage as HP, Max Per Hit: 427 ]]
        },
        Options = { Gem = function(lvl) return lvl <= 60 and 8 or nil end }
    },
    -- unused
    {
        Group = 'tapsummon',
        Spells =
        {
            'Vollmondnacht Orb', -- [[NEC/96 - Mana: 1363 - Cast: 1,25s - Recast 5s T9 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: Recourse: Vollmondnacht Orb Recourse 1: Decrease Current HP by 4467 ]]
            'Dusternacht Orb',   -- [[NEC/91 - Mana: 1256 - Cast: 1,25s - Recast 5s T9 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: Recourse: Dusternacht Orb Recourse 1: Decrease Current HP by 3684 ]]
            'Dunkelnacht Orb',   -- [[NEC/86 - Mana: 1153 - Cast: 1,25s - Recast 5s T9 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: Recourse: Dunkelnacht Orb Recourse 1: Decrease Current HP by 2706 ]]
            'Finsternacht Orb',  -- [[NEC/81 - Mana: 922 - Cast: 1,25s - Recast 5s T9 - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: Recourse: Finsternacht Orb Recourse 1: Decrease Current HP by 1968 ]]
            'Shadow Orb',        -- [[NEC/69 - Mana: 600 - Cast: 4s - Recast 1,5s - Duration: 0s - Resist: Magic -200 - Target: Single- Effects: Recourse: Shadow Orb Recourse 1: Decrease Current HP by 1100 ]]
        }
    },
    -- unused
    -- Wounds proc
    {
        Group = 'proliferation',
        Spells =
        {
            'Infected Proliferation',   -- [[NEC/120 - Mana: 10 - Cast: 0s - Recast 6s - Duration: 24s+ - Resist: Magic -100 - Target: Single- Effects: 1: Decrease Current HP by 19822 per tick ]]
            'Septic Proliferation',     -- [[NEC/115 - Mana: 10 - Cast: 0s - Recast 6s - Duration: 24s+ - Resist: Magic -100 - Target: Single- Effects: 1: Decrease Current HP by 17123 per tick ]]
            'Cyclotoxic Proliferation', -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Violent Proliferation',    -- [[NEC/105 - Mana: 10 - Cast: 0s - Recast 6s - Duration: 24s+ - Resist: Magic -100 - Target: Single- Effects: 1: Decrease Current HP by 11642 per tick ]]
            'Violent Necrosis',         -- [[NEC/95 - Mana: 10 - Cast: 0s - Recast 6s - Duration: 24s+ - Resist: Magic -100 - Target: Single- Effects: 1: Decrease Current HP by 8293 per tick ]]
        }
    },

    -- combo dots
    {
        Group = 'chaotic',
        Spells =
        {
            'Chaotic Fetor',        -- [[NEC/123 - Mana: 4573 - Cast: 3s - Recast 6s T14 - Duration: 0s - Resist: Unresistable - Target: Single- Effects: 1: Cast: Chaotic Fetor Chance (v374) 2: Cast: Highest Rank of Group - Scent of The Realm (v470) ]]
            'Chaotic Acridness',    -- [[NEC/118 - Mana: 3786 - Cast: 3s - Recast 6s T14 - Duration: 0s - Resist: Unresistable - Target: Single- Effects: 1: Cast: Chaotic Acridness Chance (v374) 2: Cast: Highest Rank of Group - Scent of The Grave (v470) ]]
            'Chaotic Miasma',       -- [[NEC/113 - Mana: 3226 - Cast: 3s - Recast 6s T14 - Duration: 0s - Resist: Unresistable - Target: Single- Effects: 1: Cast: Chaotic Miasma Chance (v374) 2: Cast: Highest Rank of Group - Scent of Mortality (v470) ]]
            'Chaotic Effluvium',    -- [[NEC/108 - Mana: 2688 - Cast: 3s - Recast 6s T14 - Duration: 0s - Resist: Unresistable - Target: Single- Effects: 1: Cast: Chaotic Effluvium Chance (v374) 2: Cast: Highest Rank of Group - Scent of Extinction (v470) ]]
            'Chaotic Liquefaction', -- [[NEC/103 - Mana: 2292 - Cast: 3s - Recast 6s T14 - Duration: 0s - Resist: Unresistable - Target: Single- Effects: 1: Cast: Chaotic Liquefaction Chance (v374) 2: Cast: Highest Rank of Group - Scent of Dread (v470) ]]
            'Chaotic Corruption',   -- [[NEC/98 - Mana: 1924 - Cast: 3s - Recast 6s T14 - Duration: 0s - Resist: Unresistable - Target: Single- Effects: 1: Cast: Chaotic Corruption Chance (v374) 2: Cast: Highest Rank of Group - Scent of Dread (v470) ]]
            'Chaotic Contagion',    -- [[NEC/93 - Mana: 1773 - Cast: 3s - Recast 6s T14 - Duration: 0s - Resist: Unresistable - Target: Single- Effects: 1: Cast: Chaotic Contagion Chance (v374) 2: Cast: Highest Rank of Group - Scent of Nightfall (v470) ]]
        },
        Options = {
            opt = 'USEDOTS',
            emu = false
        }
    },
    -- unused
    -- sphere
    {
        Group = 'sphere',
        Spells =
        {
            'Remote Sphere of Rot',       -- [[NEC/118 - Mana: 9389 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Target Ring AE- Effects: 1: Aura Effect: Rot Effect (PCIObNecS24L118EchoDmgPulseRk1) ]]
            'Remote Sphere of Withering', -- [[NEC/113 - Mana: 7922 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Target Ring AE- Effects: 1: Aura Effect: Withering Effect (PCIObNecS23L113EchoDmgPulseRk1) ]]
            'Remote Sphere of Blight',    -- [[NEC/109 - Mana: 6532 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Target Ring AE- Effects: 1: Aura Effect: Blight Effect (PCIObNecS22L109EchoDmgPulseRk1) ]]
            'Remote Sphere of Decay',     -- [[NEC/104 - Mana: 5386 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Target Ring AE- Effects: 1: Aura Effect: Decay Effect (PCIObNecS21L104EchoDmgPulseRk1) ]]
            'Echo of Dissolution',        -- [[NEC/103 - Mana: 3534 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Target Ring AE- Effects: 1: Aura Effect: Dissolution Effect (PCIObNecS21L103EchoDmgPulseRk1) ]]
            'Sphere of Dissolution',      -- [[NEC/98 - Mana: 2253 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: 1: Aura Effect: Dissolution Effect (PCIObNecS20L098AuraDmgPulseRk1) ]]
            'Sphere of Withering',        -- [[NEC/93 - Mana: 1857 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: 1: Aura Effect: Withering Effect (PCIObNecS19L093AuraDmgPulseRk1) ]]
            'Sphere of Blight',           -- [[NEC/88 - Mana: 1531 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: 1: Aura Effect: Blight Effect (PCIObNecS18L088AuraDmgPulseRk1) ]]
            'Withering Decay',            -- [[NEC/83 - Mana: 1263 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: 1: Aura Effect: Withering Decay Effect (PCIObNecS17L083AuraDmgPulseRk1) ]]
        },
        Options = { emu = false }
    },
    -- unused
    {
        Group = 'dispel',
        Spells =
        { 'Cancel Magic'
        },
        Options = {
            debuff = true,
            dispel = true,
            opt = 'USEDISPEL'
        }
    },

    -- Nukes
    {
        Group = 'venin',
        Spells =
        { 'Necrotizing Venin',     -- [[NEC/121 - Mana: 3316 - Cast: 1s - Recast 6,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 28644 2: Cast: Coagulated Essence on Killshot (20% Chance) ]]
            'Embalming Venin',     -- [[NEC/116 - Mana: 2745 - Cast: 1s - Recast 6,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 23619 2: Cast: Coagulated Essence on Killshot (20% Chance) ]]
            'Searing Venin',       -- [[NEC/111 - Mana: 2064 - Cast: 1s - Recast 6,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 14282 2: Cast: Coagulated Essence on Killshot (20% Chance) ]]
            'Effluvial Venin',     -- [[NEC/106 - Mana: 1720 - Cast: 1s - Recast 6,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 11777 2: Cast: Coagulated Essence on Killshot (20% Chance) ]]
            'Liquefying Venin',    -- [[NEC/101 - Mana: 1433 - Cast: 1s - Recast 6,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 9710 2: Cast: Coagulated Essence on Killshot (20% Chance) ]]
            'Dissolving Venin',    -- [[NEC/96 - Mana: 1262 - Cast: 1s - Recast 6,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 8389 2: Cast: Coagulated Essence on Killshot (10% Chance) ]]
            'Decaying Venin',      -- [[NEC/91 - Mana: 1163 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 5615 2: Cast: Coagulated Essence on Killshot (5% Chance) ]]
            'Blighted Venin',      -- [[NEC/86 - Mana: 982 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 4123 2: Cast: Coagulated Essence on Killshot (5% Chance) ]]
            'Withering Venin',     -- [[NEC/81 - Mana: 854 - Cast: 3s - Recast 5,25s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 3259 2: Cast: Coagulated Essence on Killshot (5% Chance) ]]
            'Acikin',              -- [[NEC/66 - Mana: 556 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 1823 ]]
            'Neurotoxin',          -- [[NEC/61 - Mana: 445 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 1325 ]]
            'Torbas\' Acid Blast', -- [[NEC/32 - Mana: 147 - Cast: 3,5s - Recast 1,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 332 ]]
            'Shock of Poison',     -- [[NEC/21 - Mana: 99 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: Poison - Target: Single- Effects: 1: Decrease Current HP by 210 ]]
        },
        Options = {
            opt = 'USENUKES',
            Gem = function(lvl) return lvl <= 60 and 5 or nil end
        }
    },

    {
        Group = 'undeadnuke',
        Spells =
        {
            'Dismiss Undead', -- [[CLR/23 PAL/46 SHD/49 NEC/28 - Mana: 63 - Cast: 2,5s - Recast 1,5s - Duration: 0s - Resist: Magic -50 - Target: Undead- Effects: 1: Decrease Current HP by 211 ]]
            'Expulse Undead', -- [[CLR/13 PAL/30 SHD/39 NEC/19 - Mana: 36 - Cast: 2s - Recast 1,5s - Duration: 0s - Resist: Magic -50 - Target: Undead- Effects: 1: Decrease Current HP by 106 ]]
            'Ward Undead',    -- [[CLR/4 PAL/14 SHD/18 NEC/6 - Mana: 5 - Cast: 1,5s - Recast 1,5s - Duration: 0s - Resist: Magic - Target: Undead- Effects: 1: Decrease Current HP by 12 ]]
        },
        Options = { opt = 'USENUKES' }
    },

    {
        Group = 'pbaenuke',
        Spells =
        {
            'Word of Spirit', -- [[CLR/26 SHD/45 NEC/27 - Mana: 133 - Cast: 3,5s - Recast 9s - Duration: 0s - Resist: Magic - Target: Caster PB (30)- Effects: Push: 1 1: Decrease Current HP by 104 ]]
            'Word of Shadow', -- [[CLR/19 NEC/20 - Mana: 85 - Cast: 2,75s - Recast 9s - Duration: 0s - Resist: Magic - Target: Caster PB (30)- Effects: Push: 1 1: Decrease Current HP by 58 ]]
        },
        Options = { opt = 'USEAOE' }
    },

    -- Debuffs
    {
        Group = 'scentterris',
        Spells =
        {
            'Scent of Terris', -- [[NEC/52 - Mana: 200 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Poison - Target: Single- Effects: 1: Increase Poison Counter by 9 2: Decrease Fire Resist by 36 3: Decrease Poison Resist by 36 4: Decrease Disease Resist by 36 ]]
        }
    },
    -- AA only
    {
        Group = 'scentmortality',
        Spells =
        {
            'Scent of The Realm',  -- [[NEC/122 - Mana: 774 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Disease -200 - Target: Single- Effects: 1: Increase Spell Damage Taken by 837 (v297, Before Crit) 2: Decrease Disease Resist by 135 3: Limit Max Level: 128 (lose 10% per level) 4: Limit Effect: Current HP 5: Limit Resist: Disease 6: Decrease Poison Resist by 135 7: Limit Type: Detrimental 8: Limit Type: Exclude Combat Skills 9: Increase Disease Counter by 27 10: Limit Resist: Poison ]]
            'Scent of The Grave',  -- [[NEC/117 - Mana: 673 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Disease -200 - Target: Single- Effects: 1: Increase Spell Damage Taken by 690 (v297, Before Crit) 2: Decrease Disease Resist by 129 3: Limit Max Level: 123 (lose 10% per level) 4: Limit Effect: Current HP 5: Limit Resist: Disease 6: Decrease Poison Resist by 129 7: Limit Type: Detrimental 8: Limit Type: Exclude Combat Skills 9: Increase Disease Counter by 24 10: Limit Resist: Poison ]]
            'Scent of Mortality',  -- [[NEC/112 - Mana: 504 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Disease -200 - Target: Single- Effects: 1: Increase Spell Damage Taken by 501 (v297, Before Crit) 2: Decrease Disease Resist by 123 3: Limit Max Level: 118 (lose 10% per level) 4: Limit Effect: Current HP 5: Limit Resist: Disease 6: Decrease Poison Resist by 123 7: Limit Type: Detrimental 8: Limit Type: Exclude Combat Skills 9: Increase Disease Counter by 22 10: Limit Resist: Poison ]]
            'Scent of Extinction', -- [[NEC/107 - Mana: 403 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Disease -200 - Target: Single- Effects: 1: Increase Spell Damage Taken by 364 (v297, Before Crit) 2: Decrease Disease Resist by 117 3: Limit Max Level: 113 (lose 10% per level) 4: Limit Effect: Current HP 5: Limit Resist: Disease 6: Decrease Poison Resist by 117 7: Limit Type: Detrimental 8: Limit Type: Exclude Combat Skills 9: Increase Disease Counter by 20 10: Limit Resist: Poison ]]
            'Scent of Dread',      -- [[NEC/97 - Mana: 350 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Disease -200 - Target: Single- Effects: 1: Increase Spell Damage Taken by 264 (v297, Before Crit) 2: Decrease Disease Resist by 105 3: Limit Max Level: 108 (lose 10% per level) 4: Limit Effect: Current HP 5: Limit Resist: Disease 6: Decrease Poison Resist by 105 7: Limit Type: Detrimental 8: Limit Type: Exclude Combat Skills 9: Increase Disease Counter by 18 10: Limit Resist: Poison ]]
            'Scent of Nightfall',  -- [[NEC/92 - Mana: 325 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Disease -200 - Target: Single- Effects: 1: Increase Spell Damage Taken by 1% to 2% (v296, Before Crit) 2: Decrease Disease Resist by 91 3: Limit Max Level: 95 (lose 10% per level) 4: Limit Effect: Current HP 5: Limit Resist: Disease 6: Decrease Poison Resist by 91 7: Limit Type: Detrimental 8: Limit Type: Exclude Combat Skills 9: Increase Disease Counter by 18 10: Limit Resist: Poison ]]
            'Scent of Doom',       -- [[NEC/87 - Mana: 275 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Disease -200 - Target: Single- Effects: 1: Increase Spell Damage Taken by 1% (v296, Before Crit) 2: Decrease Disease Resist by 83 3: Limit Max Level: 90 (lose 10% per level) 4: Limit Effect: Current HP 5: Limit Resist: Disease 6: Decrease Poison Resist by 83 7: Limit Type: Detrimental 8: Limit Type: Exclude Combat Skills 9: Increase Disease Counter by 18 ]]
            'Scent of Gloom',      -- [[NEC/82 - Mana: 250 - Cast: 3,5s - Recast 6s - Duration: 14m+ - Resist: Disease -200 - Target: Single- Effects: 1: Increase Spell Damage Taken by 1% (v296, Before Crit) 2: Decrease Disease Resist by 72 3: Limit Max Level: 85 (lose 10% per level) 4: Limit Effect: Current HP 5: Limit Resist: Disease 6: Decrease Poison Resist by 72 7: Limit Type: Detrimental 8: Limit Type: Exclude Combat Skills 9: Increase Disease Counter by 18 ]]
            'Scent of Midnight',   -- [[NEC/68 - Mana: 250 - Cast: 3,5s - Recast 6s - Duration: 14m+ - Resist: Disease -200 - Target: Single- Effects: 1: Increase Disease Counter by 18 2: Decrease Disease Resist by 55 6: Decrease Poison Resist by 55 ]]
            'Scent of Shadow',     -- [[NEC/21 - Mana: 100 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Poison - Target: Single- Effects: 1: Increase Poison Counter by 4 2: Decrease Fire Resist by 18 3: Decrease Poison Resist by 18 4: Decrease Disease Resist by 18 ]]
            'Scent of Dusk',       -- [[NEC/10 - Mana: 50 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: Poison - Target: Single- Effects: 1: Increase Poison Counter by 1 2: Decrease Fire Resist by 9 3: Decrease Poison Resist by 9 4: Decrease Disease Resist by 9 ]]

        }
    },

    {
        Group = 'snare',
        Spells =
        {
            'Afflicted Darkness',   -- [[NEC/124 - Mana: 1738 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by 1506 per tick 2: Decrease Movement Speed by 75% ]]
            'Harrowing Darkness',   -- [[NEC/119 - Mana: 1439 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by 1242 per tick 2: Decrease Movement Speed by 75% ]]
            'Tormenting Darkness',  -- [[NEC/114 - Mana: 1226 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by 1024 per tick 2: Decrease Movement Speed by 75% ]]
            'Gnawing Darkness',     -- [[NEC/109 - Mana: 1022 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by 743 per tick 2: Decrease Movement Speed by 75% ]]
            'Grasping Darkness',    -- [[NEC/104 - Mana: 851 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by 612 per tick 2: Decrease Movement Speed by 75% ]]
            'Clutching Darkness',   -- [[NEC/99 - Mana: 749 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by 555 per tick 2: Decrease Movement Speed by 75% ]]
            'Viscous Darkness',     -- [[NEC/94 - Mana: 690 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by 403 per tick 2: Decrease Movement Speed by 75% ]]
            'Tenuous Darkness',     -- [[NEC/89 - Mana: 539 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by 268 per tick 2: Decrease Movement Speed by 75% ]]
            'Clawing Darkness',     -- [[NEC/84 - Mana: 378 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -30 - Target: Single- Effects: 1: Decrease Current HP by 171 per tick 2: Decrease Movement Speed by 75% ]]
            'Desecrating Darkness', -- [[NEC/68 - Mana: 248 - Cast: 3s - Recast 1,5s - Duration: 2m+ - Resist: Magic -20 - Target: Single- Effects: 1: Decrease Current HP by 96 per tick 2: Decrease Movement Speed by 75% ]]
            'Cascading Darkness',   -- [[SHD/59 NEC/47 - Mana: 300 - Cast: 3s - Recast 1,5s - Duration: 96s+ - Resist: Magic - Target: Single- Effects: 1: Decrease Current HP by 72 per tick 2: Decrease Movement Speed by 60% ]]
            'Dooming Darkness',     -- [[SHD/44 NEC/27 - Mana: 120 - Cast: 3s - Recast 1,5s - Duration: 90s+ - Resist: Magic - Target: Single- Effects: 1: Decrease Current HP by 20 per tick 2: Decrease Movement Speed by 59% ]]
            'Engulfing Darkness',   -- [[SHD/20 NEC/11 - Mana: 60 - Cast: 2s - Recast 4s - Duration: 60s+ - Resist: Magic - Target: Single- Effects: 1: Decrease Current HP by 11 per tick 2: Decrease Movement Speed by 40% ]]
            'Clinging Darkness',    -- [[SHD/11 NEC/4 - Mana: 20 - Cast: 1,75s - Recast 4s - Duration: 48s+ - Resist: Magic - Target: Single- Effects: 1: Decrease Current HP by 8 per tick 2: Decrease Movement Speed by 30% ]]

        },
        Options = {
            opt = 'USESNARE',
            Gem = function(lvl) return lvl <= 60 and 4 or nil end
        }
    },
    -- unused
    -- {Group='undeadslow', Spells={'Shackle of Bone'}, Options={opt='USESLOW', debuff=true,}},


    -- Buffs
    {
        Group = 'lich',
        Spells =
        {
            'Realmside',                     -- [[NEC/124 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 75m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Scorched Skeletal Form (v374) 2: Increase Current Mana by 689 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 663 per tick ]]
            'Lunaside',                      -- [[NEC/119 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Scorched Skeletal Form (v374) 2: Increase Current Mana by 568 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 547 per tick ]]
            'Gloomside',                     -- [[NEC/114 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Scorched Skeletal Form (v374) 2: Increase Current Mana by 468 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 450 per tick ]]
            'Contraside',                    -- [[NEC/109 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Scorched Skeletal Form (v374) 2: Increase Current Mana by 283 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 255 per tick ]]
            'Forgottenside',                 -- [[NEC/104 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Scorched Skeletal Form (v374) 2: Increase Current Mana by 233 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 210 per tick ]]
            'Forsakenside',                  -- [[NEC/99 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Scorched Skeletal Form (v374) 2: Increase Current Mana by 211 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 190 per tick ]]
            'Shadowside',                    -- [[NEC/94 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Scorched Skeletal Form (v374) 2: Increase Current Mana by 177 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 159 per tick ]]
            'Darkside',                      -- [[NEC/89 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Sebilisian Form (v374) 2: Increase Current Mana by 133 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 119 per tick ]]
            'Netherside',                    -- [[NEC/84 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Sebilisian Form (v374) 2: Increase Current Mana by 106 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 93 per tick ]]
            'Ancient: Allure of Extinction', -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Dark Possession',               -- [[NEC/70 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Mottled Skeletal Form (v374) 2: Increase Current Mana by 65 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 57 per tick ]]
            'Grave Pact',                    -- [[NEC/70 - Mana: 5 - Cast: 3s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Bloodbone Skeletal Form (v374) 2: Increase Current Mana by 72 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 60 per tick ]]
            'Ancient: Seduction of Chaos',   -- [[NEC/65 - Mana: 5 - Cast: 3s - Recast 6s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Mottled Skeletal Form (v374) 2: Increase Current Mana by 60 per tick 4: Ultravision 5: See Invisible 7: Decrease Current HP by 50 per tick ]]
            'Call of Bones',                 -- [[NEC/31 - Mana: 5 - Cast: 3s - Recast 6s - Duration: 60m+ - Resist: n/a - Target: Self- Effects: 1: Cast: Icebone Skeletal Form (v374) 2: Increase Current Mana by 8 per tick 4: Ultravision 7: Decrease Current HP by 11 per tick ]]
            'Allure of Death',               -- [[NEC/18 - Mana: 5 - Cast: 3s - Recast 6s - Duration: 14m+ - Resist: n/a - Target: Self- Effects: 2: Increase Current Mana by 4 per tick 7: Decrease Current HP by 6 per tick ]]
            'Dark Pact',                     -- [[NEC/6 - Mana: 5 - Cast: 3s - Recast 6s - Duration: 7,5m+ - Resist: n/a - Target: Self- Effects: 2: Increase Current Mana by 2 per tick 7: Decrease Current HP by 3 per tick ]]
        },
        Options = { opt = 'USELICH', nodmz = true, selfbuff = true }
    },

    {
        Group = 'flesh',
        Spells =
        {
            'Flesh to Toxin',  -- [[NEC/119 - Mana: 811 - Cast: 3s - Recast 0s - Duration: 72m+ - Resist: n/a - Target: Self- Effects: Max Hits: 24 Matching Spells 1: Cast: Burning Toxin on Spell Use (Base1=200) e.g. Cast Time 2s=50% 3s=67% 4s=100% 5s=100% 2: Limit Max Level: 130 (lose 100% per level) 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Decrease Current HP by 1815 per tick 6: Limit Min Level: 109 7: Limit Min Casting Time: 1s 8: Limit Min Mana Cost: 100 9: Limit Min Duration: 12s ]]
            'Flesh to Venom',  -- [[NEC/109 - Mana: 691 - Cast: 3s - Recast 0s - Duration: 72m+ - Resist: n/a - Target: Self- Effects: Max Hits: 24 Matching Spells 1: Cast: Burning Venom on Spell Use (Base1=200) e.g. Cast Time 2s=50% 3s=67% 4s=100% 5s=100% 2: Limit Max Level: 120 (lose 100% per level) 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Decrease Current HP by 1097 per tick 6: Limit Min Level: 99 7: Limit Min Casting Time: 1s 8: Limit Min Mana Cost: 100 9: Limit Min Duration: 12s ]]
            'Flesh to Poison', -- [[NEC/99 - Mana: 581 - Cast: 3s - Recast 0s - Duration: 72m+ - Resist: n/a - Target: Self- Effects: Stacking: Flesh to Poison 1 Max Hits: 24 Matching Spells 1: Cast: Burning Poison on Spell Use (Base1=200) e.g. Cast Time 2s=50% 3s=67% 4s=100% 5s=100% 2: Limit Max Level: 110 (lose 100% per level) 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Decrease Current HP by 958 per tick 6: Limit Min Level: 94 7: Limit Min Casting Time: 1s 8: Limit Min Mana Cost: 100 9: Limit Min Duration: 12s ]]

        },
        Options = { emu = false }
    },

    {
        Group = 'rune',
        Spells =
        {
            'Golemskin',    -- [[NEC/123 - Mana: 2391 - Cast: 5s - Recast 1,5s - Duration: 2,5h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 89000 6: Increase Current Mana by 32 per tick ]]
            'Carrion Skin', -- [[NEC/118 - Mana: 1935 - Cast: 5s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 73433 6: Increase Current Mana by 27 per tick ]]
            'Frozen Skin',  -- [[NEC/113 - Mana: 1648 - Cast: 5s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 60550 6: Increase Current Mana by 24 per tick ]]
            'Ashen Skin',   -- [[NEC/108 - Mana: 1373 - Cast: 5s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 43936 6: Increase Current Mana by 17 per tick ]]
            'Deadskin',     -- [[NEC/103 - Mana: 1143 - Cast: 5s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 30416 6: Increase Current Mana by 15 per tick ]]
            'Zombieskin',   -- [[NEC/98 - Mana: 1007 - Cast: 5s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 22070 6: Increase Current Mana by 11 per tick ]]
            'Ghoulskin',    -- [[NEC/93 - Mana: 928 - Cast: 5s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 10969 6: Increase Current Mana by 9 per tick ]]
            'Grimskin',     -- [[NEC/88 - Mana: 809 - Cast: 5s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 3052 6: Increase Current Mana by 8 per tick ]]
            'Corpseskin',   -- [[NEC/83 - Mana: 735 - Cast: 5s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 1744 6: Increase Current Mana by 4 per tick ]]
            'Dull Pain',    -- [[NEC/69 - Mana: 450 - Cast: 5s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Self- Effects: 1: Absorb Damage: 100%, Total: 975 6: Increase Current Mana by 3 per tick ]]

        }
    },
    -- unused
    {
        Group = 'tapproc',
        Spells =
        {
            'Bestow Ruin',      -- [[NEC/123 - Mana: 1949 - Cast: 0,5s - Recast 42s - Duration: 60s+ - Resist: n/a - Target: Self- Effects: Stacking: Bestowed Lifedrains 25 Max Hits: 7 Matching Spells 1: Cast: Bestow Ruin Strike on Spell Use (Base1=1000) e.g. Cast Time 2s=100% 3s=100% 4s=100% 5s=100% 2: Limit Min Mana Cost: 10 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Max Level: 125 (lose 10% per level) 6: Limit Type: Exclude Combat Skills ]]
            'Bestow Rot',       -- [[NEC/118 - Mana: 1613 - Cast: 0,5s - Recast 42s - Duration: 60s+ - Resist: n/a - Target: Self- Effects: Stacking: Bestowed Lifedrains 22 Max Hits: 7 Matching Spells 1: Cast: Bestow Rot Strike on Spell Use (Base1=1000) e.g. Cast Time 2s=100% 3s=100% 4s=100% 5s=100% 2: Limit Min Mana Cost: 10 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Max Level: 120 (lose 10% per level) 6: Limit Type: Exclude Combat Skills ]]
            'Bestow Dread',     -- [[NEC/113 - Mana: 1374 - Cast: 0,5s - Recast 42s - Duration: 60s+ - Resist: n/a - Target: Self- Effects: Stacking: Bestowed Lifedrains 19 Max Hits: 7 Matching Spells 1: Cast: Bestowed Dread Strike on Spell Use (Base1=1000) e.g. Cast Time 2s=100% 3s=100% 4s=100% 5s=100% 2: Limit Min Mana Cost: 10 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Max Level: 115 (lose 10% per level) 6: Limit Type: Exclude Combat Skills ]]
            'Bestow Relife',    -- [[NEC/108 - Mana: 1099 - Cast: 0,5s - Recast 42s - Duration: 60s+ - Resist: n/a - Target: Self- Effects: Stacking: Bestowed Lifedrains 16 Max Hits: 7 Matching Spells 1: Cast: Bestowed Relife Strike on Spell Use (Base1=1000) e.g. Cast Time 2s=100% 3s=100% 4s=100% 5s=100% 2: Limit Min Mana Cost: 10 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Max Level: 110 (lose 10% per level) 6: Limit Type: Exclude Combat Skills ]]
            'Bestow Doom',      -- [[NEC/103 - Mana: 915 - Cast: 0,5s - Recast 42s - Duration: 60s+ - Resist: n/a - Target: Self- Effects: Stacking: Bestowed Lifedrains 13 Max Hits: 7 Matching Spells 1: Cast: Bestowed Doom Strike on Spell Use (Base1=1000) e.g. Cast Time 2s=100% 3s=100% 4s=100% 5s=100% 2: Limit Min Mana Cost: 10 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Max Level: 105 (lose 10% per level) 6: Limit Type: Exclude Combat Skills ]]
            'Bestow Mortality', -- [[NEC/98 - Mana: 805 - Cast: 0,5s - Recast 42s - Duration: 60s+ - Resist: n/a - Target: Self- Effects: Stacking: Bestowed Lifedrains 10 Max Hits: 7 Matching Spells 1: Cast: Bestowed Mortality Strike on Spell Use (Base1=1000) e.g. Cast Time 2s=100% 3s=100% 4s=100% 5s=100% 2: Limit Min Mana Cost: 10 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Max Level: 100 (lose 10% per level) ]]
            'Bestow Decay',     -- [[NEC/93 - Mana: 742 - Cast: 0,5s - Recast 42s - Duration: 60s+ - Resist: n/a - Target: Self- Effects: Stacking: Bestowed Lifedrains 7 Max Hits: 7 Matching Spells 1: Cast: Bestowed Decay Strike on Spell Use (Base1=1000) e.g. Cast Time 2s=100% 3s=100% 4s=100% 5s=100% 2: Limit Min Mana Cost: 10 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Max Level: 95 (lose 10% per level) ]]
            'Bestow Unlife',    -- [[NEC/88 - Mana: 626 - Cast: 0,5s - Recast 42s - Duration: 60s+ - Resist: n/a - Target: Self- Effects: Stacking: Bestowed Lifedrains 4 Max Hits: 7 Matching Spells 1: Cast: Bestow Unlife Strike on Spell Use (Base1=1000) e.g. Cast Time 2s=100% 3s=100% 4s=100% 5s=100% 2: Limit Min Mana Cost: 10 3: Limit Effect: Current HP 4: Limit Type: Detrimental 5: Limit Max Level: 90 (lose 10% per level) ]]
            'Bestow Undeath',   -- [[NEC/83 - Mana: 459 - Cast: 3s - Recast 42s - Duration: 60s+ - Resist: n/a - Target: Self- Effects: Stacking: Bestowed Lifedrains 1 Max Hits: 7 Matching Spells 1: Cast: Bestow Undeath Cast Proc on Spell Use (Base1=1000) e.g. Cast Time 2s=100% 3s=100% 4s=100% 5s=100% 2: Limit Min Mana Cost: 10 3: Limit Effect: Current HP 4: Limit Type: Detrimental ]]

        },
        Options = { emu = false }
    },
    -- unused
    {
        Group = 'defensiveproc',
        Spells =
        {
            'Necrotic Cysts',    -- [[NEC/99 - Mana: 768 - Cast: 3s - Recast 1,5s - Duration: 3m+ - Resist: n/a - Target: Single- Effects: Max Hits: 5 Defensive Proc Casts 1: Add Defensive Proc: Cyst Explosion with 400% Rate Mod ]]
            'Necrotic Sores',    -- [[NEC/94 - Mana: 708 - Cast: 3s - Recast 1,5s - Duration: 3m+ - Resist: n/a - Target: Single- Effects: Max Hits: 5 Defensive Proc Casts 1: Add Defensive Proc: Sore Explosion with 400% Rate Mod ]]
            'Necrotic Boils',    -- [[NEC/89 - Mana: 592 - Cast: 3s - Recast 1,5s - Duration: 3m+ - Resist: n/a - Target: Single- Effects: Max Hits: 5 Defensive Proc Casts 1: Add Defensive Proc: Boil Explosion with 400% Rate Mod ]]
            'Necrotic Pustules', -- [[NEC/84 - Mana: 490 - Cast: 3s - Recast 1,5s - Duration: 3m+ - Resist: n/a - Target: Single- Effects: Max Hits: 5 Defensive Proc Casts 1: Add Defensive Proc: Pustule Explosion with 400% Rate Mod ]]
        },
        Options = {
            opt = 'USEPUSTULES',
            classes = {
                WAR = true,
                PAL = true,
                SHD = true
            },
            singlebuff = true,
            alias = 'NECROTIC',
            combatbuffothers = true
        }
    },

    {
        Group = 'reflect',
        Spells =
        {
            'Mirror', -- [[NEC/98 WIZ/98 MAG/98 ENC/98 - Mana: 375 - Cast: 1,5s - Recast 2m T8 - Duration: 12s+ - Resist: n/a - Target: Self- Effects: 1: Increase Chance to Reflect Spell by 65% with up to 65% Base Damage ]]
        }
    },

    {
        Group = 'hpbuff',
        Spells =
        {
            'Shield of Memories', -- [[NEC/121 WIZ/121 MAG/121 ENC/121 - Mana: 2582 - Cast: 9s - Recast 1,5s - Duration: 2,5h+ - Resist: n/a - Target: Self- Effects: 1: Increase Max HP by 14224 2: Increase AC by 175 to 231, Based on Class 3: Stacking: Block new spell if slot 1 is 'HP Buff' and < 15224 6: Increase Magic Resist by 164 ]]
            'Shadow Guard',       -- [[NEC/66 - Mana: 455 - Cast: 12s - Recast 1,5s - Duration: 90m+ - Resist: n/a - Target: Self- Effects: 1: Increase Max HP by 390 2: Increase AC by 10 to 14, Based on Class 3: Stacking: Block new spell if slot 1 is 'HP Buff' and < 1390 6: Increase Magic Resist by 40 ]]
            'Shield of Maelin',   -- [[NEC/64 WIZ/64 MAG/64 ENC/64 - Mana: 300 - Cast: 12s - Recast 1,5s - Duration: 90m+ - Resist: n/a - Target: Self- Effects: 1: Increase Max HP by 350 2: Increase AC by 8 to 11, Based on Class 3: Stacking: Block new spell if slot 1 is 'HP Buff' and < 1350 6: Increase Magic Resist by 40 ]]
            'Greater Shielding',  -- [[NEC/33 WIZ/33 MAG/32 ENC/31 - Mana: 120 - Cast: 6s - Recast 1,5s - Duration: 54m+ - Resist: n/a - Target: Self- Effects: 1: Increase Max HP by 100 2: Increase AC by 5 to 6, Based on Class 6: Increase Magic Resist by 16 ]]
            'Major Shielding',    -- [[NEC/24 WIZ/23 MAG/24 ENC/23 - Mana: 80 - Cast: 5s - Recast 1,5s - Duration: 45m+ - Resist: n/a - Target: Self- Effects: 1: Increase Max HP by 75 2: Increase AC by 4 to 5, Based on Class 6: Increase Magic Resist by 14 ]]
            'Shielding',          -- [[NEC/16 WIZ/15 MAG/16 ENC/16 - Mana: 50 - Cast: 5s - Recast 1,5s - Duration: 36m+ - Resist: n/a - Target: Self- Effects: 1: Increase Max HP by 50 2: Increase AC by 3 to 4, Based on Class 6: Increase Magic Resist by 12 ]]
            'Lesser Shielding',   -- [[NEC/8 WIZ/6 MAG/5 ENC/6 - Mana: 25 - Cast: 4s - Recast 1,5s - Duration: 27m+ - Resist: n/a - Target: Self- Effects: 1: Increase Max HP by 30 2: Increase AC by 2 to 2, Based on Class 6: Increase Magic Resist by 10 ]]
            'Minor Shielding',    -- [[NEC/1 WIZ/1 MAG/1 ENC/1 - Mana: 10 - Cast: 2,5s - Recast 1,5s - Duration: 27m+ - Resist: n/a - Target: Self- Effects: 1: Increase Max HP by 10 2: Increase AC by 1 to 1, Based on Class ]]
        },
        Options = { selfbuff = false }
    },
    -- pre-unity, dont use, prefer shm buffs
    {
        Group = 'dmf',
        Spells =
        {
            'Dead Men Floating', -- [[NEC/45 - Mana: 375 - Cast: 9s - Recast 6s - Duration: 72m+ - Resist: n/a - Target: Target Group- Effects: 1: Enduring Breath 2: See Invisible 3: Levitate 7: Increase Poison Resist by 70 ]]
        },
        Options = {
            opt = 'USEDMF',
            alias = 'DMF',
            selfbuff = function()
                return not mq.TLO.Me.AltAbility('Dead Men Floating')() and
                    not mq.TLO.Me.AltAbility('Perfected Dead Men Floating')()
            end
        }
    },

    -- Pet spells
    {
        Group = 'pet',
        Spells =
        {
            'Merciless Assassin',    -- [[NEC/125 - Mana: 1863 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS25L125Spec2 ]]
            'Unrelenting Assassin',  -- [[NEC/120 - Mana: 1620 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS24L120Spec2 ]]
            'Restless Assassin',     -- [[NEC/115 - Mana: 1620 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS23L115Spec2 ]]
            'Reliving Assassin',     -- [[NEC/110 - Mana: 1350 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS22L110Spec2 ]]
            'Revived Assassin',      -- [[NEC/105 - Mana: 1134 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS21L105Spec2Snw ]]
            'Unearthed Assassin',    -- [[NEC/100 - Mana: 1031 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS20L100Spec2Snw ]]
            'Reborn Assassin',       -- [[NEC/95 - Mana: 950 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS19L095Spec2Snw ]]
            'Raised Assassin',       -- [[NEC/90 - Mana: 900 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS18L090Spec2Snw ]]
            'Unliving Murderer',     -- [[NEC/85 - Mana: 800 - Cast: 6s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS17L085Spec2Snw ]]
            'Dark Assassin',         -- [[NEC/70 - Mana: 800 - Cast: 16s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS14L070Spec2Snw ]]
            'Child of Bertoxxulous', -- [[NEC/65 - Mana: 800 - Cast: 16s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS13L065Spec2Snw ]]
            'Legacy of Zek',
            'Emissary of Thule',     -- [[NEC/59 - Mana: 650 - Cast: 16s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS12L059Spec2Snw ]]
            'Servant of Bones',      -- [[NEC/56 - Mana: 525 - Cast: 15s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS12L056Skel2Char ]]
            'Minion of Shadows',     -- [[NEC/53 - Mana: 525 - Cast: 14s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS11L053Skel2Char ]]
            'Invoke Death',          -- [[SHD/64 NEC/48 - Mana: 490 - Cast: 16s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS10L048Skel2Char ]]
            'Cackling Bones',        -- [[SHD/58 NEC/44 - Mana: 450 - Cast: 15s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS09L044Skel2 ]]
            'Invoke Shadow',         -- [[NEC/33 - Mana: 340 - Cast: 13s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS07L033Skel2 ]]
            'Malignant Dead',        -- [[SHD/52 NEC/39 - Mana: 390 - Cast: 14s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS08L039Skel2 ]]
            'Summon Dead',           -- [[SHD/46 NEC/29 - Mana: 290 - Cast: 12s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS06L029Skel2 ]]
            'Haunting Corpse',       -- [[NEC/24 - Mana: 240 - Cast: 11s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS05L024Skel2 ]]
            'Animate Dead',          -- [[SHD/38 NEC/20 - Mana: 200 - Cast: 10s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS04L020Skel2 ]]
            'Restless Bones',        -- [[SHD/30 NEC/16 - Mana: 160 - Cast: 9s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS04L016Skel2Ice ]]
            'Convoke Shadow',        -- [[SHD/22 NEC/12 - Mana: 120 - Cast: 8s - Recast 11s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS03L012Skel2Ice ]]
            'Bone Walk',             -- [[SHD/14 NEC/8 - Mana: 80 - Cast: 7s - Recast 9,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS02L008Skel2Ice ]]
            'Leering Corpse',        -- [[SHD/7 NEC/4 - Mana: 40 - Cast: 6s - Recast 9,5s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS01L004Skel2Ice ]]
            'Cavorting Bones',       -- [[NEC/1 - Mana: 15 - Cast: 5s - Recast 4s - Duration: 0s - Resist: n/a - Target: Self- Effects: Consumes: Bone Chips x 1 1: Summon Pet: PCPetNecS01L001Skel2Ice ]]

        },
        Options = { postcast = function() common.petClicky() end }
    },

    {
        Group = 'pethaste',
        Spells =
        {
            'Sigil of Putrefaction',      -- [[NEC/122 - Mana: 1100 - Cast: 4,5s - Recast 1,5s - Duration: 75m+ - Resist: n/a - Target: Pet- Effects: 2: Increase Hit Damage by 25% (v185) 3: Increase STR by 556 4: Increase Melee Haste by 85% 6: Increase AC by 56 to 74, Based on Class ]]
            'Sigil of Undeath',           -- [[NEC/117 - Mana: 875 - Cast: 4,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 2: Increase Hit Damage by 25% (v185) 3: Increase STR by 458 4: Increase Melee Haste by 85% 6: Increase AC by 46 to 61, Based on Class ]]
            'Sigil of Decay',             -- [[NEC/112 - Mana: 725 - Cast: 4,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 2: Increase Hit Damage by 25% (v185) 3: Increase STR by 396 4: Increase Melee Haste by 85% 6: Increase AC by 38 to 50, Based on Class ]]
            'Sigil of the Arcron',        -- [[NEC/107 - Mana: 604 - Cast: 4,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 2: Increase Hit Damage by 23% (v185) 3: Increase STR by 342 4: Increase Melee Haste by 85% 6: Increase AC by 28 to 36, Based on Class ]]
            'Sigil of the Doomscale',     -- [[NEC/102 - Mana: 525 - Cast: 4,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 2: Increase Hit Damage by 21% (v185) 3: Increase STR by 282 4: Increase Melee Haste by 85% 6: Increase AC by 20 to 26, Based on Class ]]
            'Sigil of the Sundered',      -- [[NEC/97 - Mana: 500 - Cast: 4,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 2: Increase Hit Damage by 19% (v185) 3: Increase STR by 244 4: Increase Melee Haste by 85% 6: Increase AC by 17 to 23, Based on Class ]]
            'Sigil of the Preternatural', -- [[NEC/92 - Mana: 450 - Cast: 4,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 2: Increase Hit Damage by 16% (v185) 3: Increase STR by 201 4: Increase Melee Haste by 70% 6: Increase AC by 14 to 19, Based on Class ]]
            'Sigil of the Moribund',      -- [[NEC/87 - Mana: 385 - Cast: 4,5s - Recast 30s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 2: Increase Hit Damage by 14% (v185) 3: Increase STR by 151 4: Increase Melee Haste by 70% 6: Increase AC by 10 to 13, Based on Class ]]
            'Glyph of Darkness',          -- [[NEC/67 - Mana: 350 - Cast: 6,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 2: Increase Hit Damage by 5% (v185) 3: Increase STR by 84 4: Increase Melee Haste by 70% 6: Increase AC by 5 to 7, Based on Class ]]
            'Augment Death',              -- [[SHD/60 NEC/35 - Mana: 200 - Cast: 6,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 3: Increase STR by 45 4: Increase Melee Haste by 55% 6: Increase AC by 3 to 4, Based on Class ]]
            'Intensify Death',            -- [[NEC/23 - Mana: 50 - Cast: 6,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 3: Increase STR by 33 4: Increase Melee Haste by 30% 6: Increase AC by 2 to 2, Based on Class ]]
            'Focus Death',                -- [[NEC/11 - Mana: 35 - Cast: 6,5s - Recast 1,5s - Duration: 60m+ - Resist: n/a - Target: Pet- Effects: 3: Increase STR by 20 4: Increase Melee Haste by 15% 6: Increase AC by 1 to 2, Based on Class ]]
        },
        Options = { petbuff = true }
    },

    {
        Group = 'petheal',
        Spells =
        {
            'Bracing Revival',  -- [[NEC/123 - Mana: 4442 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Pet- Effects: 1: Increase Current HP by 65849 2: Decrease Disease Counter by 82 3: Decrease Poison Counter by 82 4: Decrease Curse Counter by 82 5: Decrease Corruption Counter by 63 ]]
            'Frigid Salubrity', -- [[NEC/118 - Mana: 3677 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Pet- Effects: 1: Increase Current HP by 54297 2: Decrease Disease Counter by 81 3: Decrease Poison Counter by 81 4: Decrease Curse Counter by 81 5: Decrease Corruption Counter by 62 ]]
            'Icy Revival',      -- [[NEC/113 - Mana: 3131 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Pet- Effects: 1: Increase Current HP by 42826 2: Decrease Disease Counter by 79 3: Decrease Poison Counter by 79 4: Decrease Curse Counter by 79 5: Decrease Corruption Counter by 59 ]]
            'Algid Renewal',    -- [[NEC/108 - Mana: 2505 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Pet- Effects: 1: Increase Current HP by 31958 2: Decrease Disease Counter by 77 3: Decrease Poison Counter by 77 4: Decrease Curse Counter by 77 5: Decrease Corruption Counter by 53 ]]
            'Icy Mending',      -- [[NEC/103 - Mana: 2085 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Pet- Effects: 1: Increase Current HP by 18709 2: Decrease Disease Counter by 74 3: Decrease Poison Counter by 74 4: Decrease Curse Counter by 74 5: Decrease Corruption Counter by 50 ]]
            'Algid Mending',    -- [[NEC/98 - Mana: 1837 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Pet- Effects: 1: Increase Current HP by 15793 2: Decrease Disease Counter by 70 3: Decrease Poison Counter by 70 4: Decrease Curse Counter by 70 5: Decrease Corruption Counter by 46 ]]
            'Chilled Mending',  -- [[NEC/93 - Mana: 1629 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Pet- Effects: 1: Increase Current HP by 8128 2: Decrease Disease Counter by 62 3: Decrease Poison Counter by 62 4: Decrease Curse Counter by 62 5: Decrease Corruption Counter by 40 ]]
            'Gelid Mending',    -- [[NEC/88 - Mana: 1079 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Pet- Effects: 1: Increase Current HP by 4702 2: Decrease Disease Counter by 51 3: Decrease Poison Counter by 51 4: Decrease Curse Counter by 51 5: Decrease Corruption Counter by 20 ]]
            'Icy Stitches',     -- [[NEC/83 - Mana: 574 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Pet- Effects: 1: Increase Current HP by 3078 2: Decrease Disease Counter by 46 3: Decrease Poison Counter by 46 4: Decrease Curse Counter by 46 5: Decrease Corruption Counter by 18 ]]
            'Dark Salve',       -- [[NEC/69 - Mana: 358 - Cast: 3,75s - Recast 1,5s T7 - Duration: 0s - Resist: n/a - Target: Undead- Effects: 1: Increase Current HP by 1645 2: Decrease Disease Counter by 28 3: Decrease Poison Counter by 28 4: Decrease Curse Counter by 28 ]]
            'Renew Bones',      -- [[NEC/26 - Mana: 64 - Cast: 3s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Undead- Effects: 1: Increase Current HP by 175 2: Decrease Disease Counter by 10 3: Decrease Poison Counter by 10 4: Decrease Curse Counter by 10 ]]
            'Mend Bones',       -- [[NEC/7 - Mana: 15 - Cast: 2s - Recast 1,5s - Duration: 0s - Resist: n/a - Target: Undead- Effects: 1: Increase Current HP by 32 2: Decrease Disease Counter by 10 3: Decrease Poison Counter by 10 4: Decrease Curse Counter by 10 ]]
        }
    },
    -- unused
    {
        Group = 'petaegis',
        Spells =
        {
            'Aegis of Valorforged', -- [[NEC/124 MAG/124 BST/124 - Mana: 1638 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet- Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 72000 ]]
            'Aegis of Rumblecrush', -- [[NEC/119 MAG/119 BST/119 - Mana: 1357 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet- Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 59500 ]]
            'Aegis of Orfur',       -- [[NEC/114 MAG/114 BST/114 - Mana: 1157 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet- Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 49100 ]]
            'Aegis of Zeklor',      -- [[NEC/109 MAG/109 BST/109 - Mana: 964 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet- Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 35600 ]]
            'Aegis of Japac',       -- [[NEC/104 MAG/104 BST/104 - Mana: 802 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet- Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 24620 ]]
            'Aegis of Nefori',      -- [[NEC/99 MAG/99 BST/99 - Mana: 707 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet- Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 20772 ]]
            'Phantasmal Ward',      -- [[NEC/98 - Mana: 500 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet- Effects: Max Hits: 65 Incoming Hit Attempts 1: Increase Chance to Avoid Melee by 50% ]]
            'Bulwark of Calliav',   -- [[NEC/69 - Mana: 500 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet- Effects: 1: Absorb 4 Hits or Spells, Max Per Hit: 15635 ]]
        }
    },
    -- unused
    {
        Group = 'petshield',
        Spells =
        {
            'Cascading Runeshield',  -- [[NEC/122 - Mana: 4339 - Cast: 1s - Recast 18s T16 - Duration: 18s+ - Resist: n/a - Target: Pet- Effects: 2: Absorb Damage: 100%, Total: 56040 4: Cast: Azia Runeshield on Fade ]]
            'Cascading Shadeshield', -- [[NEC/117 - Mana: 3592 - Cast: 1s - Recast 18s T16 - Duration: 18s+ - Resist: n/a - Target: Pet- Effects: 2: Absorb Damage: 100%, Total: 46209 4: Cast: Azia Shadeshield on Fade ]]
            'Cascading Dreadshield', -- [[NEC/112 - Mana: 3060 - Cast: 1s - Recast 18s T16 - Duration: 18s+ - Resist: n/a - Target: Pet- Effects: 2: Absorb Damage: 100%, Total: 38103 4: Cast: Azia Dreadshield on Fade ]]
            'Cascading Deathshield', -- [[NEC/107 - Mana: 2448 - Cast: 1s - Recast 18s T16 - Duration: 18s+ - Resist: n/a - Target: Pet- Effects: 2: Absorb Damage: 100%, Total: 27648 4: Cast: Azia Deathshield on Fade ]]
            'Cascading Doomshield',  -- [[NEC/102 - Mana: 2037 - Cast: 1s - Recast 18s T16 - Duration: 18s+ - Resist: n/a - Target: Pet- Effects: 2: Absorb Damage: 100%, Total: 16718 4: Cast: Azia Doomshield on Fade ]]
            'Cascading Boneshield',  -- [[NEC/97 - Mana: 1794 - Cast: 1s - Recast 18s T16 - Duration: 18s+ - Resist: n/a - Target: Pet- Effects: 2: Absorb Damage: 100%, Total: 11232 4: Cast: Azia Boneshield on Fade ]]
            'Cascading Bloodshield', -- [[NEC/92 - Mana: 1653 - Cast: 1s - Recast 18s - Duration: 18s+ - Resist: n/a - Target: Pet- Effects: 2: Absorb Damage: 100%, Total: 4478 4: Cast: Azia Bloodshield on Fade ]]
            'Cascading Deathshield', -- [[NEC/107 - Mana: 2448 - Cast: 1s - Recast 18s T16 - Duration: 18s+ - Resist: n/a - Target: Pet- Effects: 2: Absorb Damage: 100%, Total: 27648 4: Cast: Azia Deathshield on Fade ]]
        }
    },
    -- unused
    {
        Group = 'petillusion',
        Spells =
        {
            'Form of Mottled Bone', -- [[NEC/56 - Mana: 70 - Cast: 3s - Recast 1,5s - Duration: 2h+ - Resist: n/a - Target: Pet- Effects: 1: Illusion: Drybone Skeleton ]]
        }
    },

    {
        Group = 'inspire',
        Spells =
        {
            'Instill Ally',   -- [[NEC/125 - Mana: 1502 - Cast: 0,5s - Recast 18s - Duration: 3m+ - Resist: n/a - Target: Pet- Effects: 1: Cast: Gift of Congealed Essence Chance X on Fade 4: Add Melee Proc: Instilled Lifeclaw with 200% Rate Mod 5: Buff Blocker B (220) ]]
            'Inspire Ally',   -- [[NEC/120 - Mana: 1243 - Cast: 0,5s - Recast 18s - Duration: 3m+ - Resist: n/a - Target: Pet- Effects: 1: Cast: Gift of Congealed Essence Chance X on Fade 4: Add Melee Proc: Inspired Lifeclaw with 200% Rate Mod 5: Buff Blocker B (190) ]]
            'Incite Ally',    -- [[NEC/115 - Mana: 1058 - Cast: 0,5s - Recast 18s - Duration: 3m+ - Resist: n/a - Target: Pet- Effects: 1: Cast: Gift of Congealed Essence Chance X on Fade 4: Add Melee Proc: Incited Lifeclaw with 200% Rate Mod 5: Buff Blocker B (175) ]]
            'Infuse Ally',    -- [[NEC/110 - Mana: 882 - Cast: 0,5s - Recast 18s - Duration: 3m+ - Resist: n/a - Target: Pet- Effects: 1: Cast: Gift of Congealed Essence Chance on Fade 4: Add Melee Proc: Infused Lifeclaw with 200% Rate Mod 5: Buff Blocker B (160) ]]
            'Imbue Ally',     -- [[NEC/105 - Mana: 734 - Cast: 0,5s - Recast 18s - Duration: 3m+ - Resist: n/a - Target: Pet- Effects: 1: Cast: Gift of Coagulated Essence Chance on Fade 4: Add Melee Proc: Imbued Lifeclaw with 200% Rate Mod 5: Buff Blocker B (130) ]]
            'Sanction Ally',  -- [[NEC/100 - Mana: 646 - Cast: 0,5s - Recast 18s - Duration: 3m+ - Resist: n/a - Target: Pet- Effects: Max Hits: 10 Outgoing Hit Successes 1: Cast: Necromantic Oversurge on Fade 4: Add Melee Proc: Sanctioned Lifeclaw with 100% Rate Mod 5: Buff Blocker B (100) ]]
            'Empower Ally',   -- [[NEC/95 - Mana: 595 - Cast: 0,5s - Recast 18s - Duration: 3m+ - Resist: n/a - Target: Pet- Effects: Max Hits: 10 Outgoing Hit Successes 1: Cast: Necromantic Oversurge on Fade 4: Add Melee Proc: Empowered Lifeclaw with 100% Rate Mod 5: Buff Blocker B (70) ]]
            'Energize Ally',  -- [[NEC/90 - Mana: 485 - Cast: 0,5s - Recast 18s - Duration: 3m+ - Resist: n/a - Target: Pet- Effects: Max Hits: 10 Outgoing Hit Successes 1: Cast: Necromantic Oversurge on Fade 4: Add Melee Proc: Energized Lifeclaw with 100% Rate Mod 5: Buff Blocker B (40) ]]
            'Necrotize Ally', -- [[NEC/85 - Mana: 420 - Cast: 0,5s - Recast 12s - Duration: 3m - Resist: n/a - Target: Pet- Effects: 1: Cast: Necromantic Oversurge on Fade 5: Buff Blocker B (10) ]]

        },
        Options = { petbuff = true, emu = false }
    }

}

Necromancer.compositeNames = {
    ['Ecliptic Paroxysm'] = true,
    ['Composite Paroxysm'] = true,
    ['Dissident Paroxysm'] = true,
    ['Dichotomic Paroxysm'] = true
}
Necromancer.allDPSSpellGroups = { 'pyreshort', 'magic', 'venom', 'haze', 'grasp', 'leech', 'manatap', 'alliance',
    'ignite', 'scourge', 'corruption',
    'composite', 'combodisease', 'wounds', 'pyrelong', 'fireshadow', 'swarm', 'synergy', 'decay', 'grip', 'tapee', 'tap',
    'tapsummon', 'chaotic', 'sphere', 'venin', 'snare' }

function Necromancer:initSpellRotations()
    self:initBYOSCustom()
    self.spellRotations.standard = {}
    self.spellRotations.short = {}
    -- entries in the dots table are pairs of {spell id, spell name} in priority order
    if state.emu then table.insert(self.spellRotations.standard, self.spells.decay) end
    table.insert(self.spellRotations.standard, self.spells.alliance)
    table.insert(self.spellRotations.standard, self.spells.wounds)
    table.insert(self.spellRotations.standard, self.spells.composite)
    table.insert(self.spellRotations.standard, self.spells.pyreshort)
    table.insert(self.spellRotations.standard, self.spells.venom)
    table.insert(self.spellRotations.standard, self.spells.magic)
    table.insert(self.spellRotations.standard, self.spells.combodisease)
    table.insert(self.spellRotations.standard, self.spells.haze)
    table.insert(self.spellRotations.standard, self.spells.grasp)
    table.insert(self.spellRotations.standard, self.spells.fireshadow)
    table.insert(self.spellRotations.standard, self.spells.leech)
    table.insert(self.spellRotations.standard, self.spells.pyrelong)
    table.insert(self.spellRotations.standard, self.spells.synergy)
    table.insert(self.spellRotations.standard, self.spells.ignite)
    table.insert(self.spellRotations.standard, self.spells.scourge)
    table.insert(self.spellRotations.standard, self.spells.corruption)
    table.insert(self.spellRotations.standard, self.spells.manatap)

    table.insert(self.spellRotations.short, self.spells.swarm)
    table.insert(self.spellRotations.short, self.spells.alliance)
    table.insert(self.spellRotations.short, self.spells.composite)
    table.insert(self.spellRotations.short, self.spells.pyreshort)
    table.insert(self.spellRotations.short, self.spells.venom)
    table.insert(self.spellRotations.short, self.spells.magic)
    table.insert(self.spellRotations.short, self.spells.synergy)
    table.insert(self.spellRotations.short, self.spells.manatap)
    table.insert(self.spellRotations.short, self.spells.combodisease)
    table.insert(self.spellRotations.short, self.spells.haze)
    table.insert(self.spellRotations.short, self.spells.grasp)
    table.insert(self.spellRotations.short, self.spells.fireshadow)
    table.insert(self.spellRotations.short, self.spells.leech)
    table.insert(self.spellRotations.short, self.spells.pyrelong)
    table.insert(self.spellRotations.short, self.spells.ignite)
end

Necromancer.Abilities = {
    {
        Type = 'Item',
        Name = mq.TLO.InvSlot('Chest').Item.Name(),
        Options = { first = true }
    },
    { -- buff, 5 minute CD
        Type = 'Item',
        Name = 'Blightbringer\'s Tunic of the Grave',
        Options = { first = true }
    },
    --table.insert(items, common.getItem('Vicious Rabbit')) -- 5 minute CD
    --table.insert(items, common.getItem('Necromantic Fingerbone')) -- 3 minute CD
    --table.insert(items, common.getItem('Amulet of the Drowned Mariner')) -- 5 minute CD
    { -- buff, 24 minute CD
        Type = 'AA',
        Name = 'Mercurial Torment',
        Options = { first = true }
    },
    { -- buff, 15 minute CD
        Type = 'AA',
        Name = 'Heretic\'s Twincast',
        Options = { first = true }
    },
    { -- buff
        Type = 'AA',
        Name = 'Spire of Necromancy',
        Options = { first = true, emu = false }
    },
    { -- buff, 7:30 minute CD
        Type = 'AA',
        Name = 'Fundament: Third Spire of Necromancy',
        Options = { emu = true, first = true, emu = true }
    },
    {
        Type = 'AA',
        Name = 'Embalmer\'s Carapace',
        Options = { emu = true, first = true }
    },
    { -- song, 8:30 minute CD
        Type = 'AA',
        Name = 'Hand of Death',
        Options = { emu = false }
    },
    { -- song, Duskfall Empowerment, 10 minute CD
        Type = 'AA',
        Name = 'Gathering Dusk',
        Options = { alias = 'DUSK', first = true }
    },
    { -- 10 minute CD
        Type = 'AA',
        Name = 'Companion\'s Fury',
        Options = { first = true }
    },
    { -- 15 minute CD
        Type = 'AA',
        Name = 'Companion\'s Fortification',
        Options = { first = true }
    },
    { -- 10 minute CD
        Type = 'AA',
        Name = 'Rise of Bones',
        Options = { first = true, delay = 1500, opt = 'USESWARMPETS' }
    },
    { -- 9 minute CD
        Type = 'AA',
        Name = 'Swarm of Decay',
        Options = { first = true, delay = 1500, opt = 'USESWARMPETS' }
    },
    { -- 3 minute CD
        Type = 'AA',
        Name = 'Wake the Dead',
        Options = { key = 'wakethedead', opt = 'USESWARMPETS' }
    },
    { -- song, 20 minute CD
        Type = 'AA',
        Name = 'Funeral Pyre',
        Options = { key = 'funeralpyre' }
    },

    -- Buffs
    {
        Type = 'AA',
        Name = 'Mortifier\'s Unity',
        Options = { selfbuff = true, emu = false }
    },
    {
        Type = 'AA',
        Name = 'Gift of the Grave',
        Options = { selfbuff = true, RemoveBuff = 'Gift of the Grave Effect' }
    },
    {
        Type = 'AA',
        Name = 'Reluctant Benevolence',
        Options = { selfbuff = true }
    },
    {
        Type = 'AA',
        Name = 'Fortify Companion',
        Options = { petbuff = true }
    },
    {
        Type = 'AA',
        Name = 'Dead Man Floating',
        Options = { opt = 'USEDMF', skipifbuff = state.emu and 'Dead Men Floating' or 'Perfected Dead Men Floating', alias = 'DMF', selfbuff = true }
    },
    --for i,spell in ipairs(self.selfBuffs) do if spell.SpellGroup == 'dmf' then table.remove(self.selfBuffs, i) end end

    -- Debuffs
    {
        Type = 'AA',
        Name = 'Eradicate Magic',
        Options = { debuff = true, opt = 'USEDISPEL' }
    },
    {
        Type = 'AA',
        Name = 'Scent of Thule',
        Options = { debuff = true, opt = 'USEDEBUFF' }
    },
    {
        Type = 'AA',
        Name = 'Scent of Terris',
        Options = { debuff = true, opt = 'USEDEBUFF' }
    },

    -- Defensives
    {
        Type = 'AA',
        Name = 'Death\'s Effigy',
        Options = {
            key = 'deathseffigy',
            fade = true,
            opt = 'USEFD',
            postcast = function()
                mq.delay(500)
                mq.cmd('/stand')
                mq.cmd('/makemevis')
            end
        }
    },
    {
        Type = 'AA',
        Name = 'Death Peace',
        Options = {
            key = 'deathpeace',
            aggroreducer = true,
            opt = 'USEFD',
            postcast = function()
                mq.delay(1000)
                mq.cmd('/stand')
                mq.cmd('/makemevis')
            end
        }
    },

    -- Extras
    {
        Type = 'Item',
        Name = 'Bifold Focus of the Evil Eye',
        Options = { key = 'tcclick' }
    },
    {
        Type = 'AA',
        Name = 'Life Burn',
        Options = { key = 'lifeburn' }
    },
    {
        Type = 'AA',
        Name = 'Dying Grasp',
        Options = { key = 'dyinggrasp' }
    },
    {
        Type = 'AA',
        Name = 'Death Bloom',
        Options = { key = 'deathbloom', nodmz = true }
    },
    {
        Type = 'AA',
        Name = 'Blood Magic',
        Options = { key = 'bloodmagic', nodmz = true }
    },
    {
        Type = 'AA',
        Name = 'Convergence',
        Options = { rez = true, key = 'convergence' }
    },
    {
        Type = 'AA',
        Name = 'Summon Companion',
        Options = { key = 'summoncompanion' }
    }
}

function Necromancer:initBurns()
    self.pre_burn_items = {}
    table.insert(self.pre_burn_items, common.getItem('Blightbringer\'s Tunic of the Grave')) -- buff
    table.insert(self.pre_burn_items, common.getItem(mq.TLO.InvSlot('Chest').Item.Name()))   -- buff, Consuming Magic

    self.pre_burn_AAs = {}
    table.insert(self.pre_burn_AAs, self:addAA('Mercurial Torment'))                        -- buff
    table.insert(self.pre_burn_AAs, self:addAA('Heretic\'s Twincast'))                      -- buff
    if not state.emu then
        table.insert(self.pre_burn_AAs, self:addAA('Spire of Necromancy'))                  -- buff
    else
        table.insert(self.pre_burn_AAs, self:addAA('Fundament: Third Spire of Necromancy')) -- buff
    end
end

--[[
Count the number of necros in group or raid to determine whether alliance should be used.
This is currently only called once up front when the script starts.
]] --
local function countNecros()
    Necromancer.neccount = 1
    if mq.TLO.Raid.Members() > 0 then
        Necromancer.neccount = mq.TLO.SpawnCount('pc necromancer raid')()
    elseif mq.TLO.Group.Members() then
        Necromancer.neccount = mq.TLO.SpawnCount('pc necromancer group')()
    end
end

function Necromancer:resetClassTimers()
    Necromancer.debuffTimer:reset(0)
end

function Necromancer:swapSpells()
    -- Only swap spells in standard spell set
    if not self:isEnabled('SWAPSPELLS') or state.spellSetLoaded ~= 'standard' or mq.TLO.Me.Moving() then return end
    -- try to only swap after at least a few dots are on the mob
    if self.spells.haze and not mq.TLO.Target.MyBuff(self.spells.haze.Name)() then return end

    local woundsName = self.spells.wounds and self.spells.wounds.Name
    local pyrelongName = self.spells.pyrelong and self.spells.pyrelong.Name
    local fireshadowName = self.spells.fireshadow and self.spells.fireshadow.Name
    local woundsDuration = mq.TLO.Target.MyBuffDuration(woundsName)()
    local pyrelongDuration = mq.TLO.Target.MyBuffDuration(pyrelongName)()
    local fireshadowDuration = mq.TLO.Target.MyBuffDuration(fireshadowName)()
    local woundsGem = mq.TLO.Me.Gem(woundsName)()
    local pyrelongGem = mq.TLO.Me.Gem(pyrelongName)()
    local fireshadowGem = mq.TLO.Me.Gem(fireshadowName)()
    if woundsGem then
        if not self:isEnabled('USEWOUNDS') or (woundsDuration and woundsDuration > 20000) then
            if not pyrelongDuration or pyrelongDuration < 20000 then
                abilities.swapSpell(self.spells.pyrelong, woundsGem)
            elseif not fireshadowDuration or fireshadowDuration < 20000 then
                abilities.swapSpell(self.spells.fireshadow, woundsGem)
            end
        end
    elseif pyrelongGem then
        if pyrelongDuration and pyrelongDuration > 20000 then
            if self:isEnabled('USEWOUNDS') and (not woundsDuration or woundsDuration < 20000) then
                abilities.swapSpell(self.spells.wounds, pyrelongGem)
            elseif not fireshadowDuration or fireshadowDuration < 20000 then
                abilities.swapSpell(self.spells.fireshadow, pyrelongGem)
            end
        end
    elseif fireshadowGem then
        if fireshadowDuration and fireshadowDuration > 20000 then
            if self:isEnabled('USEWOUNDS') and (not woundsDuration or woundsDuration < 20000) then
                abilities.swapSpell(self.spells.wounds, fireshadowGem)
            elseif not pyrelongDuration or pyrelongDuration < 20000 then
                abilities.swapSpell(self.spells.pyrelong, fireshadowGem)
            end
        end
    elseif self.spells.wounds then
        -- maybe we got interrupted or something and none of these are mem'd anymore? just memorize wounds again
        abilities.swapSpell(self.spells.wounds, self.spells.wounds.Gem)
    end
end

-- Check whether a dot is applied to the target
local function targetHasProliferation()
    if not mq.TLO.Target.MyBuff(class.spells.proliferation and class.spells.proliferation.Name)() then return false else return true end
end

local function isNecBurnConditionMet()
    if class:isEnabled('BURNPROC') and targetHasProliferation() then
        logger.info('\arActivating Burns (proliferation proc)\ax')
        state.burnActiveTimer:reset()
        state.burnActive = true
        return true
    end
end

function Necromancer:alwaysCondition()
    if mq.TLO.Me.AltAbilityReady('Heretic\'s Twincast')() and not mq.TLO.Me.AltAbilityReady('Hand of Death')() then
        return false
    elseif not mq.TLO.Me.AltAbilityReady('Heretic\'s Twincast')() and mq.TLO.Me.AltAbilityReady('Hand of Death')() then
        return false
    else
        return true
    end
end

--[[
Base crit - 62%

Auspice - 33% crit
IOG - 13% crit
Bard Epic (12) + Fierce Eye (15) - 27% crit

Spire - 25% crit
OOW robe - 40% crit
Intensity - 50% crit
Glyph - 15% crit
]] --
function Necromancer:burnClass()
    -- Some items use Timer() and some use IsItemReady(), this seems to be mixed bag.
    -- Test them both for each item, and see which one(s) actually work.
    --if common.isBurnConditionMet(self.alwaysCondition) or isNecBurnConditionMet() then
    local base_crit = 62
    local auspice = mq.TLO.Me.Song('Auspice of the Hunter')()
    if auspice then base_crit = base_crit + 33 end
    local iog = mq.TLO.Me.Song('Illusions of Grandeur')()
    if iog then base_crit = base_crit + 13 end
    local brd_epic = mq.TLO.Me.Song('Spirit of Vesagran')()
    if brd_epic then base_crit = base_crit + 12 end
    local fierce_eye = mq.TLO.Me.Song('Fierce Eye')()
    if fierce_eye then base_crit = base_crit + 15 end

    if self:isEnabled('USESWARMPETS') and mq.TLO.SpawnCount('corpse radius 150')() > 0 and self.wakethedead then
        self.wakethedead:use()
        mq.delay(1500)
    end

    if config.get('USEGLYPH') and self.intensity and self.glyph then
        if not mq.TLO.Me.Song(self.intensity.Name)() and mq.TLO.Me.Buff('heretic\'s twincast')() then
            self.glyph:use()
        end
    end
    if config.get('USEINTENSITY') and self.glyph and self.intensity then
        if not mq.TLO.Me.Buff(self.glyph.Name)() and mq.TLO.Me.Buff('heretic\'s twincast')() then
            self.intensity:use()
        end
    end

    if self.lifeburn and mq.TLO.Me.PctHPs() > 90 and mq.TLO.Me.AltAbilityReady('Life Burn')() and (state.emu or (self.dyinggrasp and mq.TLO.Me.AltAbilityReady('Dying Grasp')())) then
        self.lifeburn:use()
        mq.delay(5)
        if self.dyinggrasp then self.dyinggrasp:use() end
    end
end

function Necromancer:preburn()
    logger.info('Pre-burn')

    for _, item in ipairs(self.pre_burn_items) do
        item:use()
    end

    for _, aa in ipairs(self.pre_burn_AAs) do
        aa:use()
    end

    if config.get('USEGLYPH') and self.intensity and self.glyph then
        if not mq.TLO.Me.Song(self.intensity.Name)() and mq.TLO.Me.Buff('heretic\'s twincast')() then
            self.glyph:use()
        end
    end
end

function Necromancer:recover()
    if self.spells.lich and mq.TLO.Me.PctHPs() < 40 and mq.TLO.Me.Buff(self.spells.lich.Name)() then
        logger.info('Removing lich to avoid dying!')
        mq.cmdf('/removebuff %s', self.spells.lich.Name)
    end
    -- modrods
    common.checkMana()
    if constants.DMZ[mq.TLO.Zone.ID()] then return end
    local pct_mana = mq.TLO.Me.PctMana()
    if self.deathbloom and pct_mana < 65 and mq.TLO.Me.CombatState() == 'COMBAT' then
        -- death bloom at some %
        self.deathbloom:use()
    end
    if self.bloodmagic and mq.TLO.Me.CombatState() == 'COMBAT' then
        if pct_mana < 40 then
            -- blood magic at some %
            self.bloodmagic:use()
        end
    end
end

local function safeToStand()
    if mq.TLO.Raid.Members() > 0 and mq.TLO.SpawnCount('pc raid tank radius 300')() > 2 then
        return true
    end
    if mq.TLO.Group.MainTank() then
        if not mq.TLO.Group.MainTank.Dead() then
            return true
        elseif mq.TLO.SpawnCount('npc radius 100')() == 0 then
            return true
        else
            return false
        end
    elseif mq.TLO.SpawnCount('npc radius 100')() == 0 then
        return true
    else
        return false
    end
end

local necCountTimer = timer:new(60000)

-- if Necromancer:isEnabled('USEALLIANCE') and necCountTimer:expired() then
--    countNecros()
--    necCountTimer:reset()
-- end

function Necromancer:drawBurnTab()
    self:set('BURNPROC', widgets.CheckBox('Burn On Proc', self:get('BURNPROC'), 'Burn when proliferation procs'))
end

return Necromancer
