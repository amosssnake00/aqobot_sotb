local mq = require('mq')
local class = require('classes.classbase')
local helpers = require('utils.helpers')
local logger = require('utils.logger')
local movement = require('utils.movement')
local timer = require('libaqo.timer')
local abilities = require('ability')
local castUtils = require('utils.cast')
local common = require('common')
local state = require('state')

local Magician = class:new()

--[[
    https://docs.google.com/document/d/1NHtWfaS6WJFurbzzWbzBOZdJ3cKn3F34m1TL5ZO3Vg0/edit#heading=h.5l4x9nc7jc3n
    http://forums.eqfreelance.net/index.php?topic=16654.0

    Sustained:
    1. self:addSpell('servant', {'Ravening Servant', 'Roiling Servant', 'Riotous Servant', 'Reckless Servant', 'Remorseless Servant'})
    2. self:addSpell('many', {'Fusillade of Many', 'Barrage of Many', 'Shockwave of Many', 'Volley of Many', 'Storm of Many'})
    3. self:addSpell('chaotic', {'Chaotic Magma', 'Chaotic Calamity', 'Chaotic Pyroclasm', 'Chaotic Inferno', 'Chaotic Fire'})
    4. self:addSpell('spear', {'Spear of Molten Dacite', 'Spear of Molten Luclinite', 'Spear of Molten Komatiite', 'Spear of Molten Arcronite', 'Spear of Molten Shieldstone'})

    Imp Twincast Burn:
    1. Riotous Servant
    2. Shockwave of Many
    3. Spear of Molten Komatiite
    4. Spear of Molten Arcronite
    (5. Chaotic Pyroclasm)

    Spell Twincast:
    1. Chaotic Pyroclasm
    2. Riotous Servant
    3. Shockwave of Many
    4. Spear of Molten Komatiite

    Sustained additional
    table.insert(self.DPSAbilities, self:addAA('Force of Elements'))
    table.insert(self.DPSAbilities, common.getItem('Molten Komatiite Orb'))
    self:addSpell('twincast', {'Twincast'})
    self:addSpell('alliance', {'Firebound Conjunction', 'Firebound Coalition', 'Firebound Covenant', 'Firebound Alliance'})
    self:addSpell('composite', {'Ecliptic Companion', 'Composite Companion', 'Dichotomic Companion'})

    self:addSpell('malo', {'Malosinera', 'Malosinetra', 'Malosinara', 'Malosinata', 'Malosinete'})

    Burns
    table.insert(self.burnAbilities, self:addAA('Heart of Skyfire')) --Glyph of Destruction
    table.insert(self.burnAbilities, self:addAA('Focus of Arcanum'))

    table.insert(self.burnAbilities, self:addAA('Host of the Elements'))
    table.insert(self.burnAbilities, self:addAA('Servant of Ro'))

    Host of the Elements, Servant of Ro -- cast after RS
    Imperative Minion, Imperative Servant -- clicky pets
    self:addSpell('servantclicky', {'Summon Valorous Servant', 'Summon Forbearing Servant', 'Summon Imperative Servant', 'Summon Insurgent Servant', 'Summon Mutinous Servant'})

    table.insert(self.burnAbilities, self:addAA('Spire of the Elements')) -- if no crit buff
    Thaumaturge\'s Focus -- if casting any magic spells'

    Burn AE
    Silent casting

    Firebound Coalition or Chaotic Pyroclasm -> RS -> Host of Elements -> Twincast -> Of Many
    Imp Twincast after spell Twincast
    Forceful Rejuv during ITC

    Pet
    table.insert(self.burnAbilities, self:addAA('Frenzied Burnout'))
    Zeal of the Elements
    Thaumaturgist\'s Infusion after burnout fades

    Buffs
    Elemental Form
    Burnout, Iceflame Rampart, Thaumaturge\'s Unity

    ModRods
    Radiant Modulation Shard, Wand of Freezing Modulation, Elemental Conversion
    Monster Summoning + Reclaim Energy

    Survival
    Shield of Destiny, Shield of Elements, Shared Health, Heart of Frostone

    Fade
    Drape of Shadows, Arcane Whisper

    Pets
    'air', {'Recruitment of Air', 'Conscription of Air', 'Manifestation of Air', 'Embodiment of Air', 'Convocation of Air'}
    'earth', {'Recruitment of Earth', 'Conscription of Earth', 'Manifestation of Earth', 'Embodiment of Earth', 'Convocation of Earth'}
    'fire', {'Recruitment of Fire', 'Conscription of Fire', 'Manifestation of Fire', 'Embodiment of Fire', 'Convocation of Fire'}
    'water', {'Recruitment of Water', 'Conscription of Water', 'Manifestation of Water', 'Embodiment of Water', 'Convocation of Water'}
    'monster', {'Monster Summoning XV', 'Monster Summoning XIV', 'Monster Summoning XIII', 'Monster Summoning XII', 'Monster Summoning XI'}
]]
function Magician:init()
    self.classOrder = { 'assist', 'mash', 'aggro', 'debuff', 'burn', 'cast', 'heal', 'recover', 'managepet', 'buff',
        'rest', 'rez' }
    self.spellRotations = { standard = {}, custom = {} }
    self:initBase('MAG')

    self:initClassOptions()
    self:loadSettings()
    self:initSpellLines()
    self:initSpellRotations()
    self:initAbilities()
    self:addCommonAbilities()
end

Magician.PetTypes = { water = 'waterpet', earth = 'earthpet', air = 'airpet', fire = 'firepet', monster = 'monsterpet' }
function Magician:initClassOptions()
    self:addOption('PETTYPE', 'Pet Type', 'water', self.PetTypes, 'The type of pet to be summoned', 'combobox', nil,
        'PetType', 'string')
    self:addOption('EARTHFORM', 'Elemental Form: Earth', false, nil, 'Toggle use of Elemental Form: Earth', 'checkbox',
        'FIREFORM', 'EarthForm', 'bool')
    self:addOption('FIREFORM', 'Elemental Form: Fire', true, nil, 'Toggle use of Elemental Form: Fire', 'checkbox',
        'EARTHFORM', 'FireForm', 'bool')
    self:addOption('USEFIRENUKES', 'Use Fire Nukes', true, nil, 'Toggle use of fire nuke line', 'checkbox', nil,
        'UseFireNukes', 'bool')
    self:addOption('USEMAGICNUKES', 'Use Magic Nukes', false, nil, 'Toggle use of magic nuke line', 'checkbox', nil,
        'UseMagicNukes', 'bool')
    self:addOption('USEDEBUFF', 'Use Malo', false, nil, 'Toggle use of Malo', 'checkbox', nil, 'UseDebuff', 'bool')
    self:addOption('SUMMONMODROD', 'Summon Mod Rods', false, nil, 'Toggle summoning of mod rods', 'checkbox', nil,
        'SummonModRod', 'bool')
    self:addOption('USEDS', 'Use Group DS', true, nil, 'Toggle casting of group damage shield', 'checkbox', nil, 'UseDS',
        'bool')
    self:addOption('USETEMPDS', 'Use Temp DS', true, nil, 'Toggle casting of temporary damage shield', 'checkbox', nil,
        'UseTempDS', 'bool')
    self:addOption('USESERVANT', 'Use Servant', true, nil, 'Toggle use of Servant line of spells', 'checkbox', nil,
        'UseServant', 'bool')
    if state.emu then
        self:addOption('USESKINDS', 'Use Skin DS', false, nil, 'Toggle use of skin DS line of spells', 'checkbox', nil,
            'UseSkinDS', 'bool')
        self:addOption('USEVEILDS', 'Use Veil DS', false, nil, 'Toggle use of veil DS line of spells', 'checkbox', nil,
            'UseVeilDS', 'bool')
        self:addOption('USEPARADOX', 'Use Paradox', true, nil,
            'Toggle summoning and use of Paradox item to use in combat', 'checkbox', nil, 'UseParadox', 'bool')
        self:addOption('USEMINION', 'Use Minion', false, nil, 'Toggle summoning and use of minion item to use in combat',
            'checkbox', nil, 'UseMinion', 'bool')
    end
    self:addOption('USEGATHER', 'Use Gather', false, nil, 'Toggle use of gather line of spells in combat', 'checkbox',
        nil, 'UseGather', 'bool')
    self:addOption('USEMODRODS', 'Use Mod Rods', false, nil, 'Toggle summoning of mod rods', 'checkbox', nil,
        'UseModRods', 'bool')
    self:addOption('USEDISPEL', 'Use Dispel', true, nil, 'Dispel mobs with Eradicate Magic AA', 'checkbox', nil,
        'UseDispel', 'bool')
end

--[[
-- Utility
self:addAA('Call of the Hero')
self:addAA('Perfected Invisibility')
self:addAA('Perfected Invisibility to Undead')
self:addAA('Perfected Levitation')
self:addAA('Group Perfected Invisibility')
self:addAA('Group Perfected Invisibility to Undead')
self:addAA('Mass Group Buff')
self:addAA('Tranquil Blessings')
self:addAA('Summon Companion')
self:addAA('Diminutive Companion')
self:addAA('Summon Modulation Shard') -- MGB mod rods

-- Burns
self:addAA('Heart of Skyfire') -- inc spell / crit dmg, reduce agro, 15 min cd, timer 9
self:addAA('Thaumaturge\'s Focus') -- inc dmg and crit dmg for magic spells, 15 min cd, timer 78
self:addAA('Host of the Elements') -- swarm pets, 10 min cd, timer 7
self:addAA('Servant of Ro') -- summons strong temp pet to nuke, 9 min cd, timer 6
self:addAA('Spire of Elements') -- inc crit chance + melee proc for group, 7:30 cd, timer 40
self:addAA('Silent Casting')
self:addAA('Improved Twincast') -- 15 min cd, timer 76
self:addAA('Focus of Arcanum')
self:addAA('Forceful Rejuvenation')

-- Defensives
self:addAA('Companion\'s Shielding') -- large pet heal + 72 seconds of 50% dmg absorb for self, 15 min cd, timer 8
self:addAA('Heart of Froststone') -- absorb 70% inc spell/melee, 15 min cd, timer 16
self:addAA('Shield of the Elements') -- 40k heal + hot, absorbs 100% of dmg up to 125k, 15 min cd, timer 11
self:addAA('Host in the Shell') -- pet rune, 25% dmg absorb, 4 min cd, timer 10
self:addAA('Dimensional Shield') -- absorb 50% melee dmg, 20 min, timer 17

-- Heals
self:addAA('Mend Companion')
self:addAA('Second Wind Ward') -- DI for pet, procs big heal below 20% hp, 20 min cd, timer 43

-- Pet Buffs
self:addAA('Velocity') -- pet sow

-- Buffs
self:addAA('Elemental Form') -- self buff, adds some procs, mana, hp
self:addAA('Thaumaturge\'s Unity') -- self buffs, chaotic largesse, ophiolite bodyguard, shield of shadow, relentless guardian

-- Leap
self:addAA('Summoner\'s Step')

-- Fades
self:addAA('Companion of Necessity') -- Fade pet, 10 min cd, timer 3
self:addAA('Drape of Shadows') -- fade
self:addAA('Arcane Whisper') -- large agro reducer, 10 min cd, timer 35

-- Rest
self:addAA('Elemental Conversion') -- 148k pet hp for 35k mana, 15 min cd, timer 42

-- Mash
self:addAA('Force of Elements') -- 40k nuke, 20 sec cd, timer 73
self:addAA('Turn Summoned') -- large summoned nuke, 5 min cd, timer 5

self:addAA('Companion\'s Aegis')
self:addAA('Companion\'s Discipline')
self:addAA('Companion\'s Fortification')
self:addAA('Companion\'s Fury')
self:addAA('Companion\'s Intervening Divine Aura')
self:addAA('Companion\'s Suspension')

-- Debuff spell replacers
self:addAA('Malaise') -- aa malo
self:addAA('Wind of Malaise') -- aa aoe malo
self:addAA('Eradicate Magic') -- dispel
]]
Magician.SpellLines = {
    { -- Main fire nuke. Slot 1/2
        Group = 'spear',
        NumToPick = 2,
        Spells = {
            'Spear of Molten Dacite',                       -- [[MAG/125 - Mana: 10825 - Cast: 3,5s - Recast 9s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 88548 ]]
            'Spear of Molten Luclinite',                    -- [[MAG/120 - Mana: 8962 - Cast: 3,5s - Recast 9s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 73014 ]]
            'Spear of Molten Komatiite',                    -- [[MAG/115 - Mana: 6738 - Cast: 3,5s - Recast 9s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 44150 ]]
            'Spear of Molten Arcronite',                    -- [[MAG/110 - Mana: 5390 - Cast: 3,5s - Recast 9s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 32704 ]]
            'Spear of Molten Shieldstone', --[[emu cutoff]] -- [[MAG/105 - Mana: 4487 - Cast: 3,5s - Recast 9s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 26967 ]]
            'Spear of Ro',                                  -- [[MAG/70 - Mana: 684 - Cast: 7s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 3119 ]]
            'Bolt of Jerikor',
            'Sun Vortex',                                   -- [[MAG/65 - Mana: 395 - Cast: 6,35s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 1600 ]]
            'Firebolt of Tallon',                           -- [[MAG/61 - Mana: 515 - Cast: 7s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 2100 ]]
            'Seeking Flame of Seukor',                      -- [[MAG/59 - Mana: 413 - Cast: 6,5s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 1607 ]]
            'Char',                                         -- [[MAG/52 - Mana: 291 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 974 ]]
            --[[   'Cinder Bolt', ]]                        -- [[MAG/33 - Mana: 165 - Cast: 4s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 510 ]]
            'Blaze',                                        -- [[MAG/31 - Mana: 136 - Cast: 4s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 418 ]]
            'Bolt of Flame',                                -- [[MAG/18 - Mana: 102 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 297 ]]
            'Shock of Flame',                               -- [[MAG/15 - Mana: 48 - Cast: 2,5s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 122 ]]
            'Flame Bolt',                                   -- [[MAG/5 - Mana: 25 - Cast: 2s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 55 ]]
            'Burn',                                         -- [[MAG/4 - Mana: 7 - Cast: 1,5s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 14 ]]
            'Burst of Flame',                               -- [[DRU/1 SHM/1 MAG/1 - Mana: 4 - Cast: 1,5s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 5 ]] ]]
        },
        Options = {
            opt = 'USEFIRENUKES',
            Gems = { 1, function(lvl) return not Magician:isEnabled('USEAOE') and 2 or nil end },
            precast = function()
                if mq.TLO.FindItem('Bifold Focus of the Evil Eye')() and mq.TLO.Me.ItemReady('Bifold Focus of the Evil Eye')() then
                    mq.cmd('/useitem "Bifold Focus of the Evil Eye"')
                end
            end
        }
    },
    { -- Main AE nuke. Slot 1
        Group = 'beam',
        Spells = {
            'Beam of Molten Dacite',                       -- [[MAG/122 - Mana: 2965 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Fire -10 - Target: Frontal AE (12) - Effects: 1: Decrease Current HP by 31120 ]]
            'Beam of Molten Olivine',                      -- [[MAG/117 - Mana: 2455 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Fire -10 - Target: Frontal AE (12) - Effects: 1: Decrease Current HP by 25661 ]]
            'Beam of Molten Komatiite',                    -- [[MAG/112 - Mana: 1846 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Fire -10 - Target: Frontal AE (12) - Effects: 1: Decrease Current HP by 15516 ]]
            'Beam of Molten Rhyolite',                     -- [[MAG/107 - Mana: 1538 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Fire -10 - Target: Frontal AE (12) - Effects: 1: Decrease Current HP by 12793 ]]
            'Beam of Molten Shieldstone', --[[emu cutoff]] -- [[MAG/102 - Mana: 1280 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Fire -10 - Target: Frontal AE (12) - Effects: 1: Decrease Current HP by 10549 ]]
            'Column of Fire',                              -- [[MAG/12 - Mana: 65 - Cast: 3,25s - Recast 6s  - Duration: 0s - Resist: Fire  - Target: Target AE (4) - Effects: 1: Decrease Current HP by 51 ]]
            'Fire Flux',                                   -- [[MAG/1 - Mana: 23 - Cast: 1,75s - Recast 6s  - Duration: 0s - Resist: Fire  - Target: Caster PB (30) - Effects: 1: Decrease Current HP by 12 ]]
        },
        Options = { opt = 'USEAOE', threshold = 2, Gem = function(lvl) return lvl >= 100 and 2 or nil end }
    },
    { -- Strong elemental temporary pet summon. Slot 3
        Group = 'servant',
        Spells = {
            'Ravening Servant',                     -- [[MAG/125 - Mana: 7856 - Cast: 1s - Recast 19s T5 - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: 1: Summon Pet: PCSwmMagS25L125Garg2Red x 1 for 18s 2: Decrease Current HP by 1 3: Stacking: Twincast Blocker ]]
            'Roiling Servant',                      -- [[MAG/120 - Mana: 6504 - Cast: 1s - Recast 19s T5 - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: 1: Summon Pet: PCSwmMagS24L120Garg2Red x 1 for 18s 2: Decrease Current HP by 1 3: Stacking: Twincast Blocker ]]
            'Riotous Servant',                      -- [[MAG/115 - Mana: 5541 - Cast: 1s - Recast 19s T5 - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: 1: Summon Pet: PCSwmMagS23L115Garg2Red x 1 for 18s 2: Decrease Current HP by 1 3: Stacking: Twincast Blocker ]]
            'Reckless Servant',                     -- [[MAG/110 - Mana: 4433 - Cast: 1s - Recast 19s T5 - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: 1: Summon Pet: PCSwmMagS22L110Garg2Red x 1 for 18s 2: Decrease Current HP by 1 3: Stacking: Twincast Blocker ]]
            'Remorseless Servant', --[[emu cutoff]] -- [[MAG/105 - Mana: 3690 - Cast: 1s - Recast 19s T5 - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: 1: Summon Pet: PCSwmMagS21L105Garg2Runic x 1 for 18s 2: Decrease Current HP by 1 3: Stacking: Twincast Blocker ]]
            'Raging Servant',                       -- [[MAG/70 - Mana: 1650 - Cast: 3s - Recast 18s T5 - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: 1: Summon Pet: PCSwmMagS14L070Garg2Red x 1 for 18s 2: Decrease Current HP by 1 3: Stacking: Twincast Blocker ]]
            'Rampaging Servant',                    -- [[MAG/75 - Mana: 1980 - Cast: 3s - Recast 18s T5 - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: 1: Summon Pet: PCSwmMagS15L075Garg2Red x 1 for 18s 2: Decrease Current HP by 1 3: Stacking: Twincast Blocker ]]
        },
        Options = { opt = 'USESERVANT', Gem = 3 }
    },
    { -- Large nuke, triggers beneficial buff chance. Slot 4
        Group = 'chaotic',
        Spells = {
            'Chaotic Magma',                 -- [[MAG/125 - Mana: 5563 - Cast: 1,5s - Recast 5,25s T4 - Duration: 0s - Resist: Fire -10 - Target: Single - Effects: 1: Decrease Current HP by 65353 2: Cast: Chaotic Magma Chance (v374) ]]
            'Chaotic Calamity',              -- [[MAG/120 - Mana: 4606 - Cast: 1,5s - Recast 5,25s T4 - Duration: 0s - Resist: Fire -10 - Target: Single - Effects: 1: Decrease Current HP by 53889 2: Cast: Chaotic Calamity Chance (v374) ]]
            'Chaotic Pyroclasm',             -- [[MAG/115 - Mana: 3463 - Cast: 1,5s - Recast 5,25s T4 - Duration: 0s - Resist: Fire -10 - Target: Single - Effects: 1: Decrease Current HP by 32586 2: Cast: Chaotic Pyroclasm Chance (v374) ]]
            'Chaotic Inferno',               -- [[MAG/110 - Mana: 2886 - Cast: 1,5s - Recast 5,25s T4 - Duration: 0s - Resist: Fire -10 - Target: Single - Effects: 1: Decrease Current HP by 23646 2: Cast: Chaotic Inferno Chance (v374) ]]
            'Chaotic Fire', --[[emu cutoff]] -- [[MAG/105 - Mana: 2426 - Cast: 1,5s - Recast 5,25s T4 - Duration: 0s - Resist: Fire -10 - Target: Single - Effects: 1: Decrease Current HP by 19497 2: Cast: Chaotic Fire Chance (v374) ]]
            'Burning Earth',                 -- [[MAG/69 - Mana: 337 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 1348 ]]
        },
        Options = { Gem = 4 }
    },
    { -- Large nuke based on # of summoned pets. Slot 5
        Group = 'ofmany',
        Spells = {
            'Fusillade of Many',              -- [[MAG/122 - Mana: 3944 - Cast: 0,75s - Recast 9s T6 - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 10973 (If Between 1 To 2 Pets On Hatelist) 2: Decrease Current HP by 46653 (If Between 3 To 6 Pets On Hatelist) 3: Decrease Current HP by 82334 (If More Than 6 Pets On Hatelist) ]]
            'Barrage of Many',                -- [[MAG/117 - Mana: 3265 - Cast: 0,75s - Recast 9s T6 - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 9048 (If Between 1 To 2 Pets On Hatelist) 2: Decrease Current HP by 38469 (If Between 3 To 6 Pets On Hatelist) 3: Decrease Current HP by 67890 (If More Than 6 Pets On Hatelist) ]]
            'Shockwave of Many',              -- [[MAG/112 - Mana: 2455 - Cast: 0,75s - Recast 9s T6 - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 7136 (If Between 1 To 2 Pets On Hatelist) 2: Decrease Current HP by 30341 (If Between 3 To 6 Pets On Hatelist) 3: Decrease Current HP by 53547 (If More Than 6 Pets On Hatelist) ]]
            'Volley of Many',                 -- [[MAG/107 - Mana: 2046 - Cast: 0,75s - Recast 9s T6 - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 5884 (If Between 1 To 2 Pets On Hatelist) 2: Decrease Current HP by 25019 (If Between 3 To 6 Pets On Hatelist) 3: Decrease Current HP by 44153 (If More Than 6 Pets On Hatelist) ]]
            'Storm of Many', --[[emu cutoff]] -- [[MAG/102 - Mana: 1703 - Cast: 0,75s - Recast 9s T6 - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 4851 (If Between 1 To 2 Pets On Hatelist) 2: Decrease Current HP by 20630 (If Between 3 To 6 Pets On Hatelist) 3: Decrease Current HP by 36408 (If More Than 6 Pets On Hatelist) ]]
        },
        Options = { Gem = 5, emu = false }
    },
    { -- Main magic nuke. Slot 6
        Group = 'shock',
        Spells = {
            'Shock of Memorial Steel',             -- [[MAG/122 - Mana: 2370 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 31921 ]]
            'Shock of Carbide Steel',              -- [[MAG/117 - Mana: 1962 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 26321 ]]
            'Shock of Burning Steel',              -- [[MAG/112 - Mana: 1475 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 15915 ]]
            'Shock of Arcronite Steel',            -- [[MAG/107 - Mana: 1229 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 13123 ]]
            'Shock of Darksteel', --[[emu cutoff]] -- [[MAG/102 - Mana: 1023 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 10821 ]]
            'Blade Strike',                        -- [[MAG/68 - Mana: 431 - Cast: 6,25s - Recast 1,5s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 2029 ]]
            'Rock of Taelosia',                    -- [[MAG/65 - Mana: 379 - Cast: 6,25s - Recast 1,5s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: 1: Decrease Current HP by 1623 ]]
            'Shock of Steel',                      -- [[MAG/57 - Mana: 293 - Cast: 6,25s - Recast 1,5s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 1193 ]]
            'Shock of Swords',                     -- [[MAG/41 - Mana: 162 - Cast: 5s - Recast 1,5s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 584 ]]
            'Shock of Spikes',                     -- [[MAG/23 - Mana: 75 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 227 ]]
            'Shock of Blades',                     -- [[MAG/7 - Mana: 18 - Cast: 2s - Recast 1,5s  - Duration: 0s - Resist: Magic  - Target: Single - Effects: Push: 0,5 1: Decrease Current HP by 42 ]]
        },
        Options = { opt = 'USEMAGICNUKES', Gem = 6 }
    },
    { -- Summons clicky nuke orb with 10 charges. Slot 7
        Group = 'orb',
        Spells = {
            'Summon Molten Komatiite Orb',           -- [[MAG/114 - Mana: 10099 - Cast: 7s - Recast 6s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 106091] x 1 ]]
            'Summon Firebound Orb', --[[emu cutoff]] -- [[MAG/102 - Mana: 8739 - Cast: 7s - Recast 6s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 150420] x 1 ]]
            'Summon: Molten Orb',                    -- [[MAG/69 - Mana: 1550 - Cast: 4,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 77678] x 1 ]]
            'Summon: Lava Orb',                      -- [[MAG/61 - Mana: 1275 - Cast: 4,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 77681] x 1 ]]
        },
        Options = {
            Gem = 7,
            summonMinimum = 1,
            nodmz = true,
            pause = true,
            alias = 'NUKEORB',
            selfbuff = true,
            condition = function()
                return not
                    mq.TLO.FindItem('Glyphwielder\'s Eternal Bracer')()
            end
        }
    },
    { -- Large DS 10 minutes. Slot 8
        Group = 'veilds',
        Spells = {
            'Igneous Veil',                  -- [[MAG/124 - Mana: 2409 - Cast: 1,5s - Recast 1,5s  - Duration: 6,5m+ - Resist: n/a - Target: Single - Effects: Max Hits: 48 Defensive Proc Casts 1: Add Defensive Proc: Igneous Lash with 400% Rate Mod ]]
            'Volcanic Veil',                 -- [[MAG/119 - Mana: 1994 - Cast: 1,5s - Recast 1,5s  - Duration: 6,5m+ - Resist: n/a - Target: Single - Effects: Max Hits: 48 Defensive Proc Casts 1: Add Defensive Proc: Volcanic Lash with 400% Rate Mod ]]
            'Exothermic Veil',               -- [[MAG/114 - Mana: 1698 - Cast: 1,5s - Recast 1,5s  - Duration: 6,5m+ - Resist: n/a - Target: Single - Effects: Max Hits: 48 Defensive Proc Casts 1: Add Defensive Proc: Exothermic Lash with 400% Rate Mod ]]
            'Skyfire Veil', --[[emu cutoff]] -- [[MAG/109 - Mana: 1415 - Cast: 1,5s - Recast 1,5s  - Duration: 6,5m+ - Resist: n/a - Target: Single - Effects: Max Hits: 48 Defensive Proc Casts 1: Add Defensive Proc: Skyfire Lash with 400% Rate Mod ]]
        },
        Options = { opt = 'USEVEILDS', Gem = function(lvl) return lvl >= 100 and 9 or nil end, emu = false }
    },
    { -- Regular group DS. Slot 9
        Group = 'groupds',
        Spells = {
            'Circle of Forgefire Coat',                -- [[MAG/124 - Mana: 5763 - Cast: 6s - Recast 1,5s  - Duration: 75m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 8955 2: Increase Fire Resist by 58 ]]
            'Circle of Emberweave Coat',               -- [[MAG/119 - Mana: 5011 - Cast: 6s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 6536 2: Increase Fire Resist by 50 ]]
            'Circle of Igneous Skin',                  -- [[MAG/114 - Mana: 4149 - Cast: 6s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 5187 2: Increase Fire Resist by 50 ]]
            'Circle of the Inferno',                   -- [[MAG/109 - Mana: 3319 - Cast: 6s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 672 2: Increase Fire Resist by 50 ]]
            'Circle of Flameweaving', --[[emu cutoff]] -- [[MAG/104 - Mana: 2763 - Cast: 6s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 407 2: Increase Fire Resist by 45 ]]
            'Circle of Brimstoneskin',                 -- [[MAG/84 - Mana: 954 - Cast: 9s - Recast 1,5s  - Duration: 15m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 108 2: Increase Fire Resist by 45 ]]
            'Circle of Fireskin',                      -- [[MAG/70 - Mana: 585 - Cast: 9s - Recast 1,5s  - Duration: 15m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 62 2: Increase Fire Resist by 45 ]]
            'Maelstrom of Ro',                         -- [[MAG/63 - Mana: 450 - Cast: 9s - Recast 1,5s  - Duration: 15m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 48 2: Increase Fire Resist by 45 ]]
            'Aegis of Ro',                             -- [[MAG/60 - Mana: 450 - Cast: 9s - Recast 1,5s  - Duration: 15m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 35 2: Increase Fire Resist by 33 ]]
            'Boon of Immolation',                      -- [[MAG/53 - Mana: 360 - Cast: 5s - Recast 1,5s  - Duration: 15m+ - Resist: n/a - Target: Target Group - Effects: 1: Increase Damage Shield by 25 2: Increase Fire Resist by 25 ]]
        },
        Options = { opt = 'USEDS', Gem = function() return not Magician:isEnabled('USESKINDS') and 8 or nil end, alias = 'DS' }
    },
    { -- 30 seconds, 4 charges large DS. Slot 9
        Group = 'skinds',
        Spells = {
            'Boiling Skin',                 -- [[MAG/123 - Mana: 1812 - Cast: 1s - Recast 14,5s T9 - Duration: 30s+ - Resist: n/a - Target: Single - Effects: Max Hits: 4 Incoming Hit Successes 12: Increase Damage Shield by 19681 ]]
            'Scorching Skin',               -- [[MAG/118 - Mana: 1501 - Cast: 1s - Recast 14,5s T9 - Duration: 30s+ - Resist: n/a - Target: Single - Effects: Max Hits: 4 Incoming Hit Successes 12: Increase Damage Shield by 14752 ]]
            'Burning Skin',                 -- [[MAG/113 - Mana: 1278 - Cast: 1s - Recast 14,5s T9 - Duration: 30s+ - Resist: n/a - Target: Single - Effects: Max Hits: 4 Incoming Hit Successes 12: Increase Damage Shield by 12164 ]]
            'Blistering Skin',              -- [[MAG/108 - Mana: 1065 - Cast: 1s - Recast 14,5s T9 - Duration: 30s+ - Resist: n/a - Target: Single - Effects: Max Hits: 4 Incoming Hit Successes 12: Increase Damage Shield by 4904 ]]
            'Corona Skin', --[[emu cutoff]] -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
        },
        Options = { opt = 'USESKINDS', Gem = 8, emu = false }
    },
    { -- Twincast next spell. Slot 10
        Group = 'twincast',
        Spells = {
            'Twincast', -- [[DRU/85 WIZ/85 MAG/85 - Mana: 1 - Cast: 0s - Recast 6m  - Duration: 18s - Resist: n/a - Target: Self - Effects: 1: Increase Chance to Twincast by 100% 2: Limit Effect: Current HP 3: Limit Effect: Exclude Twincast Blocker 4: Limit Min Mana Cost: 10 5: Limit Type: Exclude Combat Skills 6: Limit Type: Detrimental ]]
        },
        Options = { Gem = 10, first = true }
    },
    { -- Recover mana, long cast time. Slot 11
        Group = 'gather',
        Spells = {
            'Gather Zeal',       -- [[MAG/125 - Mana: 1 - Cast: 12s - Recast 7m T1 - Duration: 0s - Resist: n/a - Target: Self - Effects: Rest: 3s 1: Increase Current Mana by 29059 ]]
            'Gather Vigor',      -- [[MAG/120 - Mana: 1 - Cast: 12s - Recast 7m T1 - Duration: 0s - Resist: n/a - Target: Self - Effects: Rest: 3s 1: Increase Current Mana by 23961 ]]
            'Gather Potency',    -- [[MAG/115 - Mana: 1 - Cast: 12s - Recast 7m T1 - Duration: 0s - Resist: n/a - Target: Self - Effects: Rest: 3s 1: Increase Current Mana by 19758 ]]
            'Gather Capability', -- [[MAG/110 - Mana: 1 - Cast: 12s - Recast 7m T1 - Duration: 0s - Resist: n/a - Target: Self - Effects: Rest: 3s 1: Increase Current Mana by 14336 ]]
        },
        Options = { Gem = 11, recover = true, opt = 'USEGATHER' }
    },
    { -- Strong pet buff. Slot 12
        Group = 'composite',
        Spells = {
            'Ecliptic Companion',   -- [[MAG/116 - Mana: 13117 - Cast: 0,5s - Recast 60s T11 - Duration: 6s+ - Resist: n/a - Target: Pet - Effects: 1: Cast: Highest Rank of Group - Ecliptic Companion (v470) ]]
            'Composite Companion',  -- [[MAG/111 - Mana: 11406 - Cast: 0,5s - Recast 60s T11 - Duration: 6s+ - Resist: n/a - Target: Pet - Effects: 1: Cast: Highest Rank of Group - Composite Companion (v470) ]]
            'Dissident Companion',  -- [[MAG/106 - Mana: 9918 - Cast: 0,5s - Recast 60s T11 - Duration: 6s+ - Resist: n/a - Target: Pet - Effects: 1: Cast: Highest Rank of Group - Dissident Companion (v470) ]]
            'Dichotomic Companion', -- [[MAG/101 - Mana: 8624 - Cast: 0,5s - Recast 60s T11 - Duration: 6s+ - Resist: n/a - Target: Pet - Effects: 1: Cast: Highest Rank of Group - Dichotomic Companion (v470) ]]
        },
        Options = { Gem = 12, emu = false }
    },
    { -- Another clicky nuke. Slot 13
        Group = 'paradox',
        Spells = {
            'Grant Voidfrost Paradox',  -- [[MAG/119 - Mana: 2103 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 109875] x 1 ]]
            'Grant Frostbound Paradox', -- [[MAG/109 - Mana: 1741 - Cast: 4s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 41167] x 1 ]]
        },
        Options = { opt = 'USEPARADOX', Gem = function() return not Magician:isEnabled('USEALLIANCE') and 13 or nil end, summonMinimum = 1, nodmz = true, pause = true, emu = false }
    },
    { -- Slot 13
        Group = 'alliance',
        Spells = {
            'Firebound Conjunction', -- [[MAG/120 - Mana: 19600 - Cast: 3s - Recast 60s T13 - Duration: 18s+ - Resist: Fire -15 - Target: Single - Effects: Max Hits: 9 Matching Spells 1: Increase Spell Damage Taken by 56588 (v484, After Crit) 2: Limit Target: Single 3: Limit Target: Line of Sight 4: Limit Effect: Current HP 5: Limit Type: Detrimental 6: Limit Min Level: 111 7: Limit Max Level: 125 (lose 100% per level) 8: Limit Max Duration: 0s 9: Limit Min Mana Cost: 10 10: Limit Effect: Current HP less than -3700 11: Limit Caster Class: MAG 12: Limit Caster: Exclude Self 13: Cast: Firebound Resolution IV Azia if Max Hits Used ]]
            'Firebound Coalition',   -- [[MAG/115 - Mana: 16227 - Cast: 3s - Recast 60s T13 - Duration: 18s+ - Resist: Fire -10 - Target: Single - Effects: Stacking: Firebound Alliance 7 Max Hits: 8 Matching Spells 1: Increase Spell Damage Taken by 46661 (v484, After Crit) 2: Limit Target: Single 3: Limit Target: Line of Sight 4: Limit Effect: Current HP 5: Limit Type: Detrimental 6: Limit Min Level: 106 7: Limit Max Level: 120 (lose 100% per level) 8: Limit Max Duration: 0s 9: Limit Min Mana Cost: 10 10: Limit Effect: Current HP less than -3050 11: Limit Caster Class: MAG 12: Limit Caster: Exclude Self 13: Cast: Firebound Resolution III Azia if Max Hits Used ]]
            'Firebound Covenant',    -- [[MAG/110 - Mana: 13435 - Cast: 3s - Recast 60s T13 - Duration: 18s+ - Resist: Fire -10 - Target: Single - Effects: Stacking: Firebound Alliance 4 Max Hits: 8 Matching Spells 1: Increase Spell Damage Taken by 38475 (v484, After Crit) 2: Limit Target: Single 3: Limit Target: Line of Sight 4: Limit Effect: Current HP 5: Limit Type: Detrimental 6: Limit Min Level: 101 7: Limit Max Level: 115 (lose 100% per level) 8: Limit Max Duration: 0s 9: Limit Min Mana Cost: 10 10: Limit Effect: Current HP less than -2750 11: Limit Caster Class: MAG 12: Limit Caster: Exclude Self 13: Cast: Firebound Resolution if Max Hits Used ]]
            'Firebound Alliance',    -- [[MAG/101 - Mana: 11292 - Cast: 3s - Recast 60s T13 - Duration: 18s+ - Resist: Fire -10 - Target: Single - Effects: Stacking: Firebound Alliance 1 Max Hits: 8 Matching Spells 1: Increase Spell Damage Taken by 33236 (v484, After Crit) 2: Limit Target: Single 3: Limit Target: Line of Sight 4: Limit Effect: Current HP 5: Limit Type: Detrimental 6: Limit Min Level: 96 7: Limit Max Level: 110 (lose 100% per level) 8: Limit Max Duration: 0s 9: Limit Min Mana Cost: 10 10: Limit Effect: Current HP less than -2500 11: Limit Caster Class: MAG 12: Limit Caster: Exclude Self 13: Cast: Firebound Fulmination if Max Hits Used ]]
        },
        Options = { opt = 'USEALLIANCE', Gem = 13, emu = false }
    },
    --if state.emu and not mq.TLO.FindItem('Glyphwielder\'s Sleeves of the Summoner')() then
    {
        Group = 'shield',
        Spells = {
            'Shield of Inescapability',               -- [[NEC/122 WIZ/122 MAG/122 ENC/122 - Mana: 4258 - Cast: 4,5s - Recast 1,5s  - Duration: 75m+ - Resist: n/a - Target: Self - Effects: 1: Absorb Spell Damage: 60% over 32000, Total: 374000 2: Absorb Melee Damage: 75% over 51000, Total: 630000 ]]
            'Shield of Inevitability',                -- [[NEC/117 WIZ/117 MAG/117 ENC/117 - Mana: 3445 - Cast: 4,5s - Recast 1,5s  - Duration: 90m+ - Resist: n/a - Target: Self - Effects: 1: Absorb Spell Damage: 60% over 30000, Total: 271000 2: Absorb Melee Damage: 75% over 46000, Total: 511000 ]]
            'Shield of Destiny',                      -- [[NEC/112 WIZ/112 MAG/112 ENC/112 - Mana: 2935 - Cast: 4,5s - Recast 1,5s  - Duration: 90m+ - Resist: n/a - Target: Self - Effects: 1: Absorb Spell Damage: 60% over 30000, Total: 245261 2: Absorb Melee Damage: 75% over 35000, Total: 364667 ]]
            'Shield of Order',                        -- [[NEC/107 WIZ/107 MAG/107 ENC/107 - Mana: 1174 - Cast: 4,5s - Recast 1,5s  - Duration: 90m+ - Resist: n/a - Target: Self - Effects: 1: Absorb Spell Damage: 60% over 15000, Total: 211866 2: Absorb Melee Damage: 75% over 23000, Total: 191521 ]]
            'Shield of Consequence', --[[emu cutoff]] -- [[NEC/102 WIZ/102 MAG/102 ENC/102 - Mana: 977 - Cast: 4,5s - Recast 1,5s  - Duration: 90m+ - Resist: n/a - Target: Self - Effects: 1: Absorb Spell Damage: 60% over 12000, Total: 146668 2: Absorb Melee Damage: 75% over 12000, Total: 112304 ]]
            'Elemental Aura',                         -- [[MAG/66 - Mana: 455 - Cast: 12s - Recast 1,5s  - Duration: 90m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 390 2: Increase AC by 10 to 14, Based on Class 3: Stacking: Block new spell if slot 1 is 'HP Buff' and < 1390 6: Increase Magic Resist by 40 ]]
        },
        Options = {
            selfbuff = true,
            condition = function()
                return not mq.TLO.FindItem(
                    'Glyphwielder\'s Sleeves of the Summoner')()
            end
        }
    },
    {
        Group = 'minion',
        Spells = {
            'Summon Valorous Servant',   -- [[MAG/123 - Mana: 11783 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 159968] x 1 ]]
            'Summon Forbearing Servant', -- [[MAG/118 - Mana: 9756 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 124364] x 1 ]]
            'Summon Imperative Servant', -- [[MAG/113 - Mana: 8310 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 150405] x 1 ]]
            'Summon Insurgent Servant',  -- [[MAG/108 - Mana: 6648 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 64988] x 1 ]]
            'Summon Mutinous Servant',   -- [[MAG/103 - Mana: 5535 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 99810] x 1 ]]
        },
        Options = { opt = 'USEMINION', summonMinimum = 1, nodmz = true, pause = true, emu = false }
    },
    {
        Group = 'waterpet',
        Spells = {
            'Recruitment of Water',                  -- [[MAG/122 - Mana: 1000 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS25L122ElemWat ]]
            'Conscription of Water',                 -- [[MAG/117 - Mana: 1000 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS24L117ElemWat ]]
            'Manifestation of Water',                -- [[MAG/112 - Mana: 825 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS23L112ElemWat ]]
            'Embodiment of Water',                   -- [[MAG/107 - Mana: 550 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS22L107ElemWat ]]
            'Convocation of Water', --[[emu cutoff]] -- [[MAG/102 - Mana: 450 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS21L102ElemWat ]]
            'Child of Water',                        -- [[MAG/67 - Mana: 400 - Cast: 12s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS14L067ElemWat ]]
            'Servant of Marr',                       -- [[MAG/62 - Mana: 400 - Cast: 12s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon Pet: PCPetMagS13L062ElemWat ]]
            'Greater Vocaration: Water',             -- [[MAG/60 - Mana: 400 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS12L060ElemWat ]]
            'Vocarate: Water',                       -- [[MAG/54 - Mana: 300 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS11L054ElemWat ]]
            'Greater Conjuration: Water',            -- [[MAG/49 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS10L049ElemWat ]]
            'Conjuration: Water',                    -- [[MAG/41 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS09L041ElemWat ]]
            'Lesser Conjuration: Water',             -- [[MAG/36 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS08L036ElemWat ]]
            'Minor Conjuration: Water',              -- [[MAG/31 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS07L031ElemWat ]]
            'Greater Summoning: Water',              -- [[MAG/26 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS06L026ElemWat ]]
            'Summoning: Water',                      -- [[MAG/22 - Mana: 240 - Cast: 12s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS05L022ElemWat ]]
            'Lesser Summoning: Water',               -- [[MAG/18 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS04L018ElemWat ]]
            'Minor Summoning: Water',                -- [[MAG/14 - Mana: 160 - Cast: 9s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS03L014ElemWat ]]
            'Elemental: Water',                      -- [[MAG/10 - Mana: 120 - Cast: 8s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS02L010ElemWat ]]
            'Elementaling: Water',                   -- [[MAG/6 - Mana: 80 - Cast: 7s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS02L006ElemWat ]]
            'Elementalkin: Water',                   -- [[MAG/2 - Mana: 40 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS01L002ElemWat ]]
        },
        Options = {
            postcast = function()
                mq.delay(10000, function() return mq.TLO.Pet.ID() > 0 end)
                mq.delay(1500, function() return not mq.TLO.Me.SpellInCooldown() end)
                common.petClicky()
                mq.delay(1500, function() return not mq.TLO.Me.SpellInCooldown() end)
                if mq.TLO.FindItem('Glyphwielder\'s Ascendant Gloves of the Summoner')() then
                    mq.cmd('/useitem "Glyphwielder\'s Ascendant Gloves of the Summoner"')
                    mq.delay(3000, function() return not mq.TLO.Me.Casting() end)
                end
            end
        }
    },
    {
        Group = 'airpet',
        Spells = {
            'Recruitment of Air',                  -- [[MAG/121 - Mana: 1000 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS25L121ElemAir ]]
            'Conscription of Air',                 -- [[MAG/116 - Mana: 1000 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS24L116ElemAir ]]
            'Manifestation of Air',                -- [[MAG/111 - Mana: 863 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS23L111ElemAir ]]
            'Embodiment of Air',                   -- [[MAG/106 - Mana: 575 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS22L106ElemAir ]]
            'Convocation of Air', --[[emu cutoff]] -- [[MAG/101 - Mana: 488 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS21L101ElemAir ]]
            'Child of Wind',                       -- [[MAG/66 - Mana: 400 - Cast: 12s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS14L066ElemAir ]]
            'Ward of Xegony',                      -- [[MAG/61 - Mana: 400 - Cast: 12s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS13L061ElemAir ]]
            'Greater Vocaration: Air',             -- [[MAG/59 - Mana: 400 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS12L059ElemAir ]]
            'Vocarate: Air',                       -- [[MAG/53 - Mana: 300 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS11L053ElemAir ]]
            'Greater Conjuration: Air',            -- [[MAG/48 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS10L048ElemAir ]]
            'Conjuration: Air',                    -- [[MAG/43 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS09L043ElemAir ]]
            'Lesser Conjuration: Air',             -- [[MAG/38 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS08L038ElemAir ]]
            'Minor Conjuration: Air',              -- [[MAG/33 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS07L033ElemAir ]]
            'Greater Summoning: Air',              -- [[MAG/28 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS06L028ElemAir ]]
            'Summoning: Air',                      -- [[MAG/24 - Mana: 240 - Cast: 12s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS05L024ElemAir ]]
            'Lesser Summoning: Air',               -- [[MAG/20 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS04L020ElemAir ]]
            'Minor Summoning: Air',                -- [[MAG/16 - Mana: 160 - Cast: 9s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS04L016ElemAir ]]
            'Elemental: Air',                      -- [[MAG/12 - Mana: 120 - Cast: 8s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS03L012ElemAir ]]
            'Elementaling: Air',                   -- [[MAG/8 - Mana: 80 - Cast: 7s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS02L008ElemAir ]]
            'Elementalkin: Air',                   -- [[MAG/4 - Mana: 40 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS01L004ElemAir ]]
        },
        Options = {
            postcast = function()
                mq.delay(10000, function() return mq.TLO.Pet.ID() > 0 end)
                mq.delay(1500, function() return not mq.TLO.Me.SpellInCooldown() end)
                common.petClicky()
                mq.delay(1500, function() return not mq.TLO.Me.SpellInCooldown() end)
                if mq.TLO.FindItem('Glyphwielder\'s Ascendant Gloves of the Summoner')() then
                    mq.cmd('/useitem "Glyphwielder\'s Ascendant Gloves of the Summoner"')
                    mq.delay(3000, function() return not mq.TLO.Me.Casting() end)
                end
            end
        }
    },
    {
        Group = 'earthpet',
        Spells = {
            'Recruitment of Earth',                  -- [[MAG/124 - Mana: 1000 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS25L124ElemErf ]]
            'Conscription of Earth',                 -- [[MAG/119 - Mana: 1000 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS24L119ElemErf ]]
            'Manifestation of Earth',                -- [[MAG/114 - Mana: 825 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS23L114ElemErf ]]
            'Embodiment of Earth',                   -- [[MAG/109 - Mana: 550 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS22L109ElemErf ]]
            'Convocation of Earth', --[[emu cutoff]] -- [[MAG/104 - Mana: 450 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS21L104ElemErf ]]
            'Child of Earth',                        -- [[MAG/70 - Mana: 400 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS14L070ElemErf ]]
            'Rathe\'s Son',                          -- [[MAG/65 - Mana: 400 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon Pet: PCPetMagS13L065ElemErf ]]
            'Greater Vocaration: Earth',             -- [[MAG/57 - Mana: 400 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS12L057ElemErf ]]
            'Vocarate: Earth',                       -- [[MAG/51 - Mana: 300 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS11L051ElemErf ]]
            'Greater Conjuration: Earth',            -- [[MAG/46 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS10L046ElemErf ]]
            'Conjuration: Earth',                    -- [[MAG/44 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS09L044ElemErf ]]
            'Lesser Conjuration: Earth',             -- [[MAG/39 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS08L039ElemErf ]]
            'Minor Conjuration: Earth',              -- [[MAG/34 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS07L034ElemErf ]]
            'Greater Summoning: Earth',              -- [[MAG/29 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS06L029ElemErf ]]
            'Summoning: Earth',                      -- [[MAG/25 - Mana: 240 - Cast: 12s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS05L025ElemErf ]]
            'Lesser Summoning: Earth',               -- [[MAG/21 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS05L021ElemErf ]]
            'Minor Summoning: Earth',                -- [[MAG/17 - Mana: 160 - Cast: 9s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS04L017ElemErf ]]
            'Elemental: Earth',                      -- [[MAG/13 - Mana: 120 - Cast: 8s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS03L013ElemErf ]]
            'Elementaling: Earth',                   -- [[MAG/9 - Mana: 80 - Cast: 7s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS02L009ElemErf ]]
            'Elementalkin: Earth',                   -- [[MAG/5 - Mana: 40 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS01L005ElemErf ]]
        },
        Options = {
            postcast = function()
                mq.delay(10000, function() return mq.TLO.Pet.ID() > 0 end)
                mq.delay(1500, function() return not mq.TLO.Me.SpellInCooldown() end)
                common.petClicky()
                mq.delay(1500, function() return not mq.TLO.Me.SpellInCooldown() end)
                if mq.TLO.FindItem('Glyphwielder\'s Ascendant Gloves of the Summoner')() then
                    mq.cmd('/useitem "Glyphwielder\'s Ascendant Gloves of the Summoner"')
                    mq.delay(3000, function() return not mq.TLO.Me.Casting() end)
                end
            end
        }
    },
    {
        Group = 'firepet',
        Spells = {
            'Recruitment of Fire',                  -- [[MAG/123 - Mana: 1000 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS25L123ElemHeat ]]
            'Conscription of Fire',                 -- [[MAG/118 - Mana: 1000 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS24L118ElemHeat ]]
            'Manifestation of Fire',                -- [[MAG/113 - Mana: 825 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS23L113ElemHeat ]]
            'Embodiment of Fire',                   -- [[MAG/108 - Mana: 550 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS22L108ElemHeat ]]
            'Convocation of Fire', --[[emu cutoff]] -- [[MAG/103 - Mana: 450 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS21L103ElemHeat ]]
            'Child of Fire',                        -- [[MAG/68 - Mana: 400 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS14L068ElemHeat ]]
            'Child of Ro',                          -- [[MAG/63 - Mana: 400 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon Pet: PCPetMagS13L063ElemHeat ]]
            'Greater Vocaration: Fire',             -- [[MAG/58 - Mana: 400 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS12L058ElemHeat ]]
            'Vocarate: Fire',                       -- [[MAG/52 - Mana: 300 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS11L052ElemHeat ]]
            'Greater Conjuration: Fire',            -- [[MAG/47 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS10L047ElemHeat ]]
            'Conjuration: Fire',                    -- [[MAG/42 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS09L042ElemHeat ]]
            'Lesser Conjuration: Fire',             -- [[MAG/37 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS08L037ElemHeat ]]
            'Minor Conjuration: Fire',              -- [[MAG/32 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS07L032ElemHeat ]]
            'Greater Summoning: Fire',              -- [[MAG/27 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS06L027ElemHeat ]]
            'Summoning: Fire',                      -- [[MAG/23 - Mana: 240 - Cast: 12s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS05L023ElemHeat ]]
            'Lesser Summoning: Fire',               -- [[MAG/19 - Mana: 200 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS04L019ElemHeat ]]
            'Minor Summoning: Fire',                -- [[MAG/15 - Mana: 160 - Cast: 9s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS03L015ElemHeat ]]
            'Elemental: Fire',                      -- [[MAG/11 - Mana: 120 - Cast: 8s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS03L011ElemHeat ]]
            'Elementaling: Fire',                   -- [[MAG/7 - Mana: 80 - Cast: 7s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS02L007ElemHeat ]]
            'Elementalkin: Fire',                   -- [[MAG/3 - Mana: 40 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS01L003ElemHeat ]]
        },
        Options = {
            postcast = function()
                mq.delay(10000, function() return mq.TLO.Pet.ID() > 0 end)
                mq.delay(1500, function() return not mq.TLO.Me.SpellInCooldown() end)
                common.petClicky()
                mq.delay(1500, function() return not mq.TLO.Me.SpellInCooldown() end)
                if mq.TLO.FindItem('Glyphwielder\'s Ascendant Gloves of the Summoner')() then
                    mq.cmd('/useitem "Glyphwielder\'s Ascendant Gloves of the Summoner"')
                    mq.delay(3000, function() return not mq.TLO.Me.Casting() end)
                end
            end
        }
    },
    {
        Group = 'monsterpet',
        Spells = {
            'Monster Summoning XV',                  -- [[MAG/125 - Mana: 15000 - Cast: 8s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS25L125MonSum ]]
            'Monster Summoning XIV',                 -- [[MAG/120 - Mana: 15000 - Cast: 8s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS24L120MonSum ]]
            'Monster Summoning XIII',                -- [[MAG/115 - Mana: 13000 - Cast: 8s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS23L115MonSum ]]
            'Monster Summoning XII',                 -- [[MAG/110 - Mana: 11000 - Cast: 8s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS22L110MonSum ]]
            'Monster Summoning XI', --[[emu cutoff]] -- [[MAG/105 - Mana: 10000 - Cast: 8s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: Consumes: Malachite x 1 1: Summon Pet: PCPetMagS21L105MonSum ]]
        },
        Options = {}
    },
    {
        Group = 'petbuff',
        Spells = {
            'Burnout XVI',                  -- [[MAG/121 - Mana: 985 - Cast: 4,5s - Recast 1,5s  - Duration: 75m+ - Resist: n/a - Target: Pet - Effects: 2: Increase Hit Damage by 25% (v185) 3: Increase STR by 509 4: Increase Melee Haste by 85% 5: Increase ATK by 394 6: Increase AC by 45 to 59, Based on Class ]]
            'Burnout XV',                   -- [[MAG/116 - Mana: 796 - Cast: 4,5s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Pet - Effects: 2: Increase Hit Damage by 25% (v185) 3: Increase STR by 420 4: Increase Melee Haste by 85% 5: Increase ATK by 325 6: Increase AC by 37 to 49, Based on Class ]]
            'Burnout XIV',                  -- [[MAG/111 - Mana: 678 - Cast: 4,5s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Pet - Effects: 2: Increase Hit Damage by 25% (v185) 3: Increase STR by 364 4: Increase Melee Haste by 85% 5: Increase ATK by 281 6: Increase AC by 31 to 41, Based on Class ]]
            'Burnout XIII',                 -- [[MAG/106 - Mana: 565 - Cast: 4,5s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Pet - Effects: 2: Increase Hit Damage by 24% (v185) 3: Increase STR by 314 4: Increase Melee Haste by 85% 5: Increase ATK by 231 6: Increase AC by 25 to 34, Based on Class ]]
            'Burnout XII', --[[emu cutoff]] -- [[MAG/101 - Mana: 471 - Cast: 4,5s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Pet - Effects: 2: Increase Hit Damage by 22% (v185) 3: Increase STR by 258 4: Increase Melee Haste by 85% 5: Increase ATK by 182 6: Increase AC by 21 to 28, Based on Class ]]
            'Elemental Fury',               -- [[MAG/69 - Mana: 187 - Cast: 6,5s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Pet - Effects: 2: Increase Hit Damage by 5% (v185) 4: Increase Melee Haste by 85% 5: Increase ATK by 52 6: Increase AC by 6 to 8, Based on Class ]]
            'Burnout V',                    -- [[MAG/62 - Mana: 150 - Cast: 6,5s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Pet - Effects: 3: Increase STR by 80 4: Increase Melee Haste by 85% 5: Increase ATK by 40 6: Increase AC by 5 to 6, Based on Class ]]
            'Burnout IV',                   -- [[MAG/55 - Mana: 150 - Cast: 6,5s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Pet - Effects: 3: Increase STR by 60 4: Increase Melee Haste by 65% 6: Increase AC by 3 to 5, Based on Class ]]
            'Burnout III',                  -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Burnout II',                   -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Burnout',                      -- [[MAG/11 - Mana: 35 - Cast: 6,5s - Recast 1,5s  - Duration: 60m+ - Resist: n/a - Target: Pet - Effects: 3: Increase STR by 15 4: Increase Melee Haste by 15% 6: Increase AC by 2 to 2, Based on Class ]]
        },
        Options = {
            petbuff = true,
            condition = function()
                return not mq.TLO.FindItem(
                        'Glyphwielder\'s Leggings of the Summoner')() and
                    not mq.TLO.FindItem('Glyphwielder\'s Ascendant Leggings of the Summoner')()
            end
        }
    },
    -- having some issues?
    -- {
    --    Group='petds',
    --    Spells={'Iceflame Pallisade', 'Iceflame Barricade', 'Iceflame Rampart', 'Iceflame Keep', 'Iceflame Armaments', --[[emu cutoff]] 'Iceflame Guard'},
    --    Options={petbuff=true, Checkfor=''} -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
    -- },
    {
        Group = 'petheal',
        Spells = {
            'Renewal of Shoru',                  -- [[MAG/123 - Mana: 4582 - Cast: 3,75s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Increase Current HP by 71523 2: Decrease Disease Counter by 84 3: Decrease Poison Counter by 84 4: Decrease Curse Counter by 84 5: Decrease Corruption Counter by 65 ]]
            'Renewal of Iilivina',               -- [[MAG/118 - Mana: 3793 - Cast: 3,75s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Increase Current HP by 58976 2: Decrease Disease Counter by 83 3: Decrease Poison Counter by 83 4: Decrease Curse Counter by 83 5: Decrease Corruption Counter by 64 ]]
            'Renewal of Evreth',                 -- [[MAG/113 - Mana: 3230 - Cast: 3,75s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Increase Current HP by 42794 2: Decrease Disease Counter by 81 3: Decrease Poison Counter by 81 4: Decrease Curse Counter by 81 5: Decrease Corruption Counter by 61 ]]
            'Renewal of Ioulin',                 -- [[MAG/108 - Mana: 2692 - Cast: 3,75s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Increase Current HP by 32576 2: Decrease Disease Counter by 79 3: Decrease Poison Counter by 79 4: Decrease Curse Counter by 79 5: Decrease Corruption Counter by 55 ]]
            'Renewal of Calix', --[[emu cutoff]] -- [[MAG/103 - Mana: 2241 - Cast: 3,75s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Increase Current HP by 19033 2: Decrease Disease Counter by 74 3: Decrease Poison Counter by 74 4: Decrease Curse Counter by 74 5: Decrease Corruption Counter by 50 ]]
            'Planar Renewal',                    -- [[MAG/64 - Mana: 290 - Cast: 3,75s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Increase Current HP by 1200 2: Decrease Disease Counter by 24 3: Decrease Poison Counter by 24 4: Decrease Curse Counter by 24 ]]
            'Refresh Summoning',                 -- [[MAG/34 - Mana: 93 - Cast: 3,75s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Increase Current HP by 175 2: Decrease Disease Counter by 10 3: Decrease Poison Counter by 10 4: Decrease Curse Counter by 10 ]]
            'Renew Summoning',                   -- [[MAG/18 - Mana: 36 - Cast: 2,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Increase Current HP by 87 2: Decrease Disease Counter by 10 3: Decrease Poison Counter by 10 4: Decrease Curse Counter by 10 ]]
            'Renew Elements',                    -- [[MAG/7 - Mana: 15 - Cast: 2s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Increase Current HP by 32 2: Decrease Disease Counter by 10 3: Decrease Poison Counter by 10 4: Decrease Curse Counter by 10 ]]
        },
        Options = { opt = 'HEALPET', pet = 50, heal = true }
    },
    { -- aborb 9 smaller hits, spellslot 1
        Group = 'petshield',
        Spells = {
            'Aegis of Valorforged', -- [[NEC/124 MAG/124 BST/124 - Mana: 1638 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 72000 ]]
            'Aegis of Rumblecrush', -- [[NEC/119 MAG/119 BST/119 - Mana: 1357 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 59500 ]]
            'Aegis of Orfur',       -- [[NEC/114 MAG/114 BST/114 - Mana: 1157 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 49100 ]]
            'Aegis of Zeklor',      -- [[NEC/109 MAG/109 BST/109 - Mana: 964 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 35600 ]]
            'Aegis of Japac',       -- [[NEC/104 MAG/104 BST/104 - Mana: 802 - Cast: 6s - Recast 36s T10 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 1: Absorb 9 Hits or Spells, Max Per Hit: 24620 ]]
        },
        Options = {}
    },
    { --absorb 5 larger hits, spellslot 2
        Group = 'auspice',
        Spells = {
            'Auspice of Valia',      -- [[MAG/117 BST/117 - Mana: 1582 - Cast: 1s - Recast 48s T16 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 2: Absorb 5 Hits or Spells, Max Per Hit: 161500 ]]
            'Auspice of Kildrukaun', -- [[MAG/112 BST/112 - Mana: 1310 - Cast: 1s - Recast 48s T16 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 2: Absorb 5 Hits or Spells, Max Per Hit: 127538 ]]
            'Auspice of Esianti',    -- [[MAG/107 BST/107 - Mana: 1085 - Cast: 1s - Recast 48s T16 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 2: Absorb 5 Hits or Spells, Max Per Hit: 87836 ]]
            'Auspice of Eternity',   -- [[MAG/102 BST/102 - Mana: 921 - Cast: 1s - Recast 48s T16 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 2: Absorb 5 Hits or Spells, Max Per Hit: 58074 ]]
        },
        Options = {}
    },
    { -- large absorb but also large snare
        Group = 'petbigshield',
        Spells = {
            'Kanoite Stance',     -- [[MAG/118 - Mana: 1989 - Cast: 6s - Recast 2m T10 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 1: Absorb Melee Damage: 33%, Total: 187000 2: Decrease Movement Speed by 80% ]]
            'Pyroxene Stance',    -- [[MAG/113 - Mana: 1694 - Cast: 6s - Recast 2m T10 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 1: Absorb Melee Damage: 33%, Total: 135800 2: Decrease Movement Speed by 80% ]]
            'Rhyolite Stance',    -- [[MAG/108 - Mana: 1412 - Cast: 6s - Recast 2m T10 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 1: Absorb Melee Damage: 33%, Total: 98500 2: Decrease Movement Speed by 80% ]]
            'Shieldstone Stance', -- [[MAG/103 - Mana: 1176 - Cast: 6s - Recast 2m T10 - Duration: 36m+ - Resist: n/a - Target: Pet - Effects: 1: Absorb Melee Damage: 33%, Total: 68200 2: Decrease Movement Speed by 80% ]]
        },
        Options = {}
    },

    -- self hp buff, blocks shm
    {
        Group = 'hpbuff',
        Spells = {
            'Shield of Memories',                      -- [[NEC/121 WIZ/121 MAG/121 ENC/121 - Mana: 2582 - Cast: 9s - Recast 1,5s  - Duration: 2,5h+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 14224 2: Increase AC by 175 to 231, Based on Class 3: Stacking: Block new spell if slot 1 is 'HP Buff' and < 15224 6: Increase Magic Resist by 164 ]]
            'Shield of Shadow',                        -- [[NEC/116 WIZ/116 MAG/116 ENC/116 - Mana: 2138 - Cast: 9s - Recast 1,5s  - Duration: 90m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 11729 2: Increase AC by 144 to 191, Based on Class 3: Stacking: Block new spell if slot 1 is 'HP Buff' and < 12729 6: Increase Magic Resist by 162 ]]
            'Shield of Restless Ice',                  -- [[NEC/111 WIZ/111 MAG/111 ENC/111 - Mana: 1822 - Cast: 9s - Recast 1,5s  - Duration: 90m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 9671 2: Increase AC by 119 to 157, Based on Class 3: Stacking: Block new spell if slot 1 is 'HP Buff' and < 10671 6: Increase Magic Resist by 158 ]]
            'Shield of Scales',                        -- [[NEC/106 WIZ/106 MAG/106 ENC/106 - Mana: 1487 - Cast: 9s - Recast 1,5s  - Duration: 90m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 5316 2: Increase AC by 86 to 114, Based on Class 3: Stacking: Block new spell if slot 1 is 'HP Buff' and < 6316 6: Increase Magic Resist by 154 ]]
            'Shield of the Pellarus', --[[emu cutoff]] -- [[NEC/101 WIZ/101 MAG/101 ENC/101 - Mana: 1238 - Cast: 9s - Recast 1,5s  - Duration: 90m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 3857 2: Increase AC by 63 to 83, Based on Class 3: Stacking: Block new spell if slot 1 is 'HP Buff' and < 4857 6: Increase Magic Resist by 138 ]]
            'Greater Shielding',                       -- [[NEC/33 WIZ/33 MAG/32 ENC/31 - Mana: 120 - Cast: 6s - Recast 1,5s  - Duration: 54m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 100 2: Increase AC by 5 to 6, Based on Class 6: Increase Magic Resist by 16 ]]
            'Major Shielding',                         -- [[NEC/24 WIZ/23 MAG/24 ENC/23 - Mana: 80 - Cast: 5s - Recast 1,5s  - Duration: 45m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 75 2: Increase AC by 4 to 5, Based on Class 6: Increase Magic Resist by 14 ]]
            'Shielding',                               -- [[NEC/16 WIZ/15 MAG/16 ENC/16 - Mana: 50 - Cast: 5s - Recast 1,5s  - Duration: 36m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 50 2: Increase AC by 3 to 4, Based on Class 6: Increase Magic Resist by 12 ]]
            'Lesser Shielding',                        -- [[NEC/8 WIZ/6 MAG/5 ENC/6 - Mana: 25 - Cast: 4s - Recast 1,5s  - Duration: 27m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 30 2: Increase AC by 2 to 2, Based on Class 6: Increase Magic Resist by 10 ]]
            'Minor Shielding',                         -- [[NEC/1 WIZ/1 MAG/1 ENC/1 - Mana: 10 - Cast: 2,5s - Recast 1,5s  - Duration: 27m+ - Resist: n/a - Target: Self - Effects: 1: Increase Max HP by 10 2: Increase AC by 1 to 1, Based on Class ]]
        },
        Options = {}
    },
    {
        Group = 'acregen',
        Spells = {
            'Courageous Guardian',                  -- [[MAG/122 - Mana: 2546 - Cast: 5s - Recast 1,5s  - Duration: 2,5h+ - Resist: n/a - Target: Self - Effects: 2: Increase Current HP by 371 per tick 4: Increase Current Mana by 95 per tick 8: Increase AC by 132 to 174, Based on Class ]]
            'Relentless Guardian',                  -- [[MAG/117 - Mana: 2108 - Cast: 5s - Recast 1,5s  - Duration: 2,5h+ - Resist: n/a - Target: Self - Effects: 2: Increase Current HP by 306 per tick 4: Increase Current Mana by 78 per tick 8: Increase AC by 109 to 144, Based on Class ]]
            'Restless Guardian',                    -- [[MAG/112 - Mana: 1796 - Cast: 5s - Recast 1,5s  - Duration: 2,5h+ - Resist: n/a - Target: Self - Effects: 2: Increase Current HP by 252 per tick 4: Increase Current Mana by 67 per tick 8: Increase AC by 90 to 119, Based on Class ]]
            'Burning Guardian',                     -- [[MAG/107 - Mana: 1497 - Cast: 5s - Recast 1,5s  - Duration: 2,5h+ - Resist: n/a - Target: Self - Effects: 2: Increase Current HP by 66 per tick 4: Increase Current Mana by 58 per tick 8: Increase AC by 74 to 98, Based on Class ]]
            'Praetorian Guardian', --[[emu cutoff]] -- [[MAG/102 - Mana: 1246 - Cast: 5s - Recast 1,5s  - Duration: 2,5h+ - Resist: n/a - Target: Self - Effects: 2: Increase Current HP by 48 per tick 4: Increase Current Mana by 48 per tick 8: Increase AC by 54 to 71, Based on Class ]]
            'Phantom Shield',                       -- [[MAG/68 - Mana: 468 - Cast: 5s - Recast 1,5s  - Duration: 2,5h+ - Resist: n/a - Target: Self - Effects: 2: Increase Current HP by 9 per tick 4: Increase Current Mana by 9 per tick 8: Increase AC by 12 to 16, Based on Class ]]
            'Xegony\'s Phantasmal Guard',           -- [[MAG/62 - Mana: 375 - Cast: 5s - Recast 1,5s  - Duration: 2,5h+ - Resist: n/a - Target: Self - Effects: 2: Increase Current HP by 8 per tick 4: Increase Current Mana by 8 per tick 8: Increase AC by 9 to 12, Based on Class ]]
        },
        Options = { selfbuff = true }
    }, -- self regen/ac buff
    {
        Group = 'manaregen',
        Spells = {
            'Valiant Symbiosis',               -- [[MAG/122 - Mana: 0 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: Recourse: Valiant Symbiosis Recourse 1: Decrease Current HP by 13765 ]]
            'Relentless Symbiosis',            -- [[MAG/117 - Mana: 0 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: Recourse: Relentless Symbiosis Recourse 1: Decrease Current HP by 11350 ]]
            'Restless Symbiosis',              -- [[MAG/115 - Mana: 0 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: Recourse: Restless Symbiosis Recourse 1: Decrease Current HP by 9359 ]]
            'Burning Symbiosis',               -- [[MAG/110 - Mana: 0 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: Recourse: Burning Symbiosis Recourse 1: Decrease Current HP by 7717 ]]
            'Dark Symbiosis', --[[emu cutoff]] -- [[MAG/105 - Mana: 0 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: Recourse: Dark Symbiosis Recourse 1: Decrease Current HP by 6363 ]]
            'Elemental Simulacrum',            -- [[MAG/70 - Mana: 0 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: Recourse: Elemental Simulacrum Recourse 1: Decrease Current HP by 1600 ]]
            'Elemental Siphon',                -- [[MAG/65 - Mana: 0 - Cast: 1,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: Recourse: Elemental Siphon Recourse 1: Decrease Current HP by 1200 ]]
        },
        Options = {}
    }, -- self mana regen
    {
        Group = 'bodyguard',
        Spells = {
            'Valorforged Bodyguard', -- [[MAG/121 - Mana: 1680 - Cast: 3s - Recast 1,5s  - Duration: 36m+ - Resist: n/a - Target: Self - Effects: Max Hits: 48 Incoming Hit Successes 1: Add Defensive Proc: Labradorite Bodyguard with 400% Rate Mod ]]
            'Ophiolite Bodyguard',   -- [[MAG/116 - Mana: 1359 - Cast: 3s - Recast 1,5s  - Duration: 20m+ - Resist: n/a - Target: Self - Effects: Max Hits: 48 Incoming Hit Successes 1: Add Defensive Proc: Lunashade Bodyguard with 400% Rate Mod ]]
            'Pyroxenite Bodyguard',  -- [[MAG/115 - Mana: 1158 - Cast: 3s - Recast 1,5s  - Duration: 20m+ - Resist: n/a - Target: Self - Effects: Max Hits: 48 Incoming Hit Successes 1: Add Defensive Proc: Pyroxenite Bodyguard with 400% Rate Mod ]]
            'Rhylitic Bodyguard',    -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Shieldstone Bodyguard', -- [[MAG/105 - Mana: 803 - Cast: 3s - Recast 1,5s  - Duration: 20m+ - Resist: n/a - Target: Self - Effects: Max Hits: 48 Incoming Hit Successes 1: Add Defensive Proc: Shieldstone Bodyguard with 400% Rate Mod ]]
        },
        Options = {}
    }, -- proc pet when hit

    -- old emu stuff
    {
        Group = 'petstrbuff',
        Spells = {
            'Rathe\'s Strength', -- [[MAG/70 - Mana: 400 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Aura Effect: Rathe's Strength Effect (PCIObMagS14L070TrapPetAug) ]]
            'Earthen Strength',  -- [[MAG/55 - Mana: 250 - Cast: 6s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Pet - Effects: 1: Aura Effect: Earthen Strength Effect (PCIObMagS11L055TrapPetAug) ]]
        },
        Options = { skipifbuff = 'Champion', petbuff = true, Checkfor = 'Rathe\'s Strength Effect' }
    },
    {
        Group = 'bigds',
        Spells = {
            'Frantic Flames', -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Pyrilen Skin',   -- [[MAG/68 - Mana: 300 - Cast: 3s - Recast 13s T9 - Duration: 12s+ - Resist: n/a - Target: Single - Effects: Max Hits: 4 Incoming Hit Successes 12: Increase Damage Shield by 420 ]]
            'Burning Aura',   -- [[MAG/68 - Mana: 300 - Cast: 3s - Recast 1,5s  - Duration: 3m+ - Resist: n/a - Target: Single - Effects: Max Hits: 48 Defensive Proc Casts 1: Add Defensive Proc: Burning Vengeance with 400% Rate Mod ]]
        },
        Options = {
            opt = 'USETEMPDS',
            alias = 'TEMPDS',
            combatbuffothers = true,
            singlebuff = true,
            classes = { WAR = true, SHD = true, PAL = true },
            Gem = function(
                lvl)
                return lvl <= 70 and 9 or nil
            end
        }
    },
    -- Chance to increase spell power of next nuke
    {
        Group = 'prenuke',
        Spells = {
            'Fickle Conflagration', --[[emu cutoff]] -- [[MAG/105 - Mana: 1777 - Cast: 1,5s - Recast 5,25s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: Recourse: Fickle Conflagration Recourse 1: Decrease Current HP by 15378 ]]
            'Fickle Fire',                           -- [[MAG/69 - Mana: 519 - Cast: 6,35s - Recast 1,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: Recourse: Fickle Fire Recourse 1: Decrease Current HP by 2475 ]]
        },
        Options = { opt = 'USEFIRENUKES' }
    },

    {
        Group = 'modrod',
        Spells = {
            'Rod of Courageous Modulation', -- [[MAG/122 - Mana: 9532 - Cast: 4,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 159996] x 1 ]]
            'Sickle of Umbral Modulation',  -- [[MAG/117 - Mana: 8289 - Cast: 4,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 124392] x 1 ]]
            'Wand of Frozen Modulation',    -- [[MAG/112 - Mana: 6994 - Cast: 4,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 150436] x 1 ]]
            'Wand of Burning Modulation',   -- [[MAG/107 - Mana: 5828 - Cast: 4,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 99838] x 1 ]]
            'Wand of Dark Modulation',      -- [[MAG/102 - Mana: 4960 - Cast: 4,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 99782] x 1 ]]
        },
        Options = { opt = 'USEMODRODS', summonMinimum = 1, nodmz = true, pause = true }
    },
    {
        Group = 'massmodrod',
        Spells = {
            'Mass Dark Transvergence', -- [[MAG/105 - Mana: 5346 - Cast: 4,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Caster AE Players - Effects: 1: Summon: [Item 99783] x 1 ]]
        },
        Options = { opt = 'USEMODRODS', summonMinimum = 1, nodmz = true, pause = true }
    },
    {
        Group = 'armor',
        Spells = {
            'Grant Alloy\'s Plate',                   -- [[not found - Mana: not found - Cast: not found - Recast not found - Duration: not found - Resist: not found - Target: not found- Effects: not found ]]
            'Grant the Centien\'s Plate',             -- [[MAG/116 - Mana: 300 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 124370] x 1 ]]
            'Grant Ocoenydd\'s Plate',                -- [[MAG/111 - Mana: 250 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 150411] x 1 ]]
            'Grant Wirn\'s Plate',                    -- [[MAG/106 - Mana: 250 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 76549] x 1 ]]
            'Grant Thassis\' Plate', --[[emu cutoff]] -- [[MAG/101 - Mana: 200 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 99807] x 1 ]]
            'Grant Spectral Plate',                   -- [[MAG/86 - Mana: 200 - Cast: 5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 57293] x 1 ]]
            'Summon Phantom Plate',                   -- [[MAG/38 - Mana: 300 - Cast: 10s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 17310] x 1 2: Summon into Bag: [Item 3419] x 1 3: Summon into Bag: [Item 3420] x 1 4: Summon into Bag: [Item 3421] x 1 5: Summon into Bag: [Item 3422] x 1 6: Summon into Bag: [Item 3422] x 1 7: Summon into Bag: [Item 3423] x 1 8: Summon into Bag: [Item 3424] x 1 9: Summon into Bag: [Item 3425] x 1 ]]
        },
        Options = { alias = 'ARMOR' }
    }, -- targeted, Summon Folded Pack of Spectral Plate
    {
        Group = 'weapons',
        Spells = {
            'Grant Goliath\'s Armaments',                 -- [[MAG/123 - Mana: 633 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 159990] x 1 ]]
            'Grant Shak Dathor\'s Armaments',             -- [[MAG/118 - Mana: 550 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 124386] x 1 ]]
            'Grant Yalrek\'s Armaments',                  -- [[MAG/113 - Mana: 450 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 150430] x 1 ]]
            'Grant Wirn\'s Armaments',                    -- [[MAG/108 - Mana: 450 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 93699] x 1 ]]
            'Grant Thassis\' Armaments', --[[emu cutoff]] -- [[MAG/103 - Mana: 375 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 99809] x 1 ]]
            'Grant Spectral Armaments',                   -- [[MAG/88 - Mana: 375 - Cast: 5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 57295] x 1 ]]
            'Dagger of Symbols',                          -- [[MAG/35 - Mana: 100 - Cast: 6s - Recast 6s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 7310] x 1 ]]
        },
        Options = { alias = 'ARM' }
    }, -- targeted, Summons Folded Pack of Spectral Armaments
    {
        Group = 'jewelry',
        Spells = {
            'Grant Ankexfen\'s Heirlooms',               -- [[MAG/121 - Mana: 489 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 159983] x 1 ]]
            'Grant the Diabo\'s Heirlooms',              -- [[MAG/116 - Mana: 425 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 124379] x 1 ]]
            'Grant Crystasia\'s Heirlooms',              -- [[MAG/111 - Mana: 350 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 150423] x 1 ]]
            'Grant Ioulin\'s Heirlooms',                 -- [[MAG/106 - Mana: 350 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 93698] x 1 ]]
            'Grant Calix\'s Heirlooms', --[[emu cutoff]] -- [[MAG/101 - Mana: 300 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 99808] x 1 ]]
            'Grant Enibik\'s Heirlooms',                 -- [[MAG/86 - Mana: 300 - Cast: 5s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 57294] x 1 ]]
        },
        Options = { alias = 'JEWELRY' }
    }, -- targeted, Summons Folded Pack of Enibik's Heirlooms, includes muzzle
    {
        Group = 'belt',
        Spells = {
            'Summon Crystal Belt', -- [[MAG/67 - Mana: 125 - Cast: 4s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 77510] x 1 ]]
        },
        Options = {}
    }, -- Summoned: Crystal Belt
    {
        Group = 'mask',
        Spells = {
            'Grant Visor of Shoen', -- [[MAG/112 - Mana: 250 - Cast: 2s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Summon: [Item 106090] x 1 ]]
        },
        Options = {}
    },
    {
        Group = 'bundle',
        Spells = {
            'Grant Bristlebane\'s Festivity Bundle', -- [[MAG/111 - Mana: 50 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 106092] x 1 ]]
        },
        Options = {}
    },
    -- Cauldron of Endless Abundance

    -- Other BYOS spells
    {
        Group = 'ofsand',
        Spells = {
            'Ruination of Sand',   -- [[MAG/121 - Mana: 1926 - Cast: 1,25s - Recast 2,35s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 24771 ]]
            'Destruction of Sand', -- [[MAG/116 - Mana: 1595 - Cast: 1,25s - Recast 2,35s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 20426 ]]
            'Crash of Sand',       -- [[MAG/111 - Mana: 1100 - Cast: 1,25s - Recast 2,35s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 12351 ]]
            'Volley of Sand',      -- [[MAG/106 - Mana: 917 - Cast: 1,25s - Recast 2,35s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 10184 ]]
        },
        Options = { opt = 'USEFIRENUKES' }
    }, -- some one-off nuke??
    {
        Group = 'firebolt',
        Spells = {
            'Bolt of Molten Dacite',      -- [[MAG/121 - Mana: 3972 - Cast: 3s - Recast 6s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 46233 ]]
            'Bolt of Molten Olivine',     -- [[MAG/116 - Mana: 3289 - Cast: 3s - Recast 6s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 38123 ]]
            'Bolt of Molten Komatiite',   -- [[MAG/111 - Mana: 2473 - Cast: 3s - Recast 6s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 23052 ]]
            'Bolt of Skyfire',            -- [[MAG/106 - Mana: 2061 - Cast: 3s - Recast 6s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 19008 ]]
            'Bolt of Molten Shieldstone', -- [[MAG/101 - Mana: 1716 - Cast: 3s - Recast 6s  - Duration: 0s - Resist: Fire  - Target: Line of Sight - Effects: 1: Decrease Current HP by 15673 ]]
        },
        Options = { 'USEFIRENUKES' }
    },
    -- random fire nuke
    {
        Group = 'sands',
        Spells = {
            'Cremating Sands',    -- [[MAG/124 - Mana: 2682 - Cast: 0,75s - Recast 4,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 24666 ]]
            'Ravaging Sands',     -- [[MAG/118 - Mana: 2221 - Cast: 0,75s - Recast 4,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 20339 ]]
            'Incinerating Sands', -- [[MAG/113 - Mana: 1670 - Cast: 0,75s - Recast 4,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 12298 ]]
            'Blistering Sands',   -- [[MAG/108 - Mana: 1392 - Cast: 0,75s - Recast 4,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 10141 ]]
            'Searing Sands',      -- [[MAG/103 - Mana: 1159 - Cast: 0,75s - Recast 4,5s  - Duration: 0s - Resist: Fire  - Target: Single - Effects: 1: Decrease Current HP by 8362 ]]
        },
        Options = { opt = 'USEFIRENUKES' }
    },
    -- summoned mob nuke
    {
        Group = 'summonednuke',
        Spells = {
            'Dismantle the Unnatural',  -- [[DRU/122 MAG/124 - Mana: 3294 - Cast: 1,5s - Recast 5,75s  - Duration: 0s - Resist: Magic -100 - Target: Single - Effects: 1: Decrease Current HP by 44270 2: Cast: Annihilate Resistances (24% Chance) (v340) 3: Cast: Dismantle Destruction (10% Chance) (v340) ]]
            'Unmend the Unnatural',     -- [[DRU/118 MAG/118 - Mana: 2727 - Cast: 1,5s - Recast 5,75s  - Duration: 0s - Resist: Magic -100 - Target: Single - Effects: 1: Decrease Current HP by 36504 2: Cast: Annihilate Resistances (24% Chance) (v340) 3: Cast: Unmend Destruction (10% Chance) (v340) ]]
            'Obliterate the Unnatural', -- [[DRU/113 MAG/113 - Mana: 1877 - Cast: 1,5s - Recast 5,75s  - Duration: 0s - Resist: Magic -100 - Target: Single - Effects: 1: Decrease Current HP by 24168 2: Cast: Annihilate Resistances (24% Chance) (v340) 3: Cast: Obliterate Destruction (10% Chance) (v340) ]]
            'Repudiate the Unnatural',  -- [[DRU/108 MAG/108 - Mana: 1564 - Cast: 1,5s - Recast 5,75s  - Duration: 0s - Resist: Magic -100 - Target: Single - Effects: 1: Decrease Current HP by 17536 2: Cast: Annihilate Resistances (24% Chance) (v340) 3: Cast: Repudiate Destruction (10% Chance) (v340) ]]
            'Eradicate the Unnatural',  -- [[DRU/103 MAG/103 - Mana: 1302 - Cast: 1,5s - Recast 5,75s  - Duration: 0s - Resist: Magic -100 - Target: Single - Effects: 1: Decrease Current HP by 14460 2: Cast: Annihilate Resistances (24% Chance) (v340) 3: Cast: Eradicate Destruction (10% Chance) (v340) ]]
            'Expel Summoned',           -- [[CLR/47 DRU/33 MAG/28 - Mana: 108 - Cast: 3,5s - Recast 1,5s  - Duration: 0s - Resist: Magic -50 - Target: Summoned - Effects: 1: Decrease Current HP by 385 ]]
            'Dismiss Summoned',         -- [[CLR/37 RNG/33 DRU/23 MAG/25 - Mana: 73 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Magic -50 - Target: Summoned - Effects: 1: Decrease Current HP by 244 ]]
            'Expulse Summoned',         -- [[CLR/27 DRU/13 MAG/18 - Mana: 41 - Cast: 2,5s - Recast 1,5s  - Duration: 0s - Resist: Magic -50 - Target: Summoned - Effects: 1: Decrease Current HP by 122 ]]
            'Ward Summoned',            -- [[CLR/17 RNG/16 DRU/2 MAG/9 - Mana: 6 - Cast: 1,5s - Recast 1,5s  - Duration: 0s - Resist: Magic -50 - Target: Summoned - Effects: 1: Decrease Current HP by 14 ]]
        },
        Options = { opt = 'USEMAGICNUKES' }
    },
    -- bolt magic nuke
    {
        Group = 'magicbolt',
        Spells = {
            'Luclinite Bolt', -- [[MAG/118 - Mana: 2778 - Cast: 3s - Recast 6s  - Duration: 0s - Resist: Magic  - Target: Line of Sight - Effects: 1: Decrease Current HP by 45868 ]]
            'Komatiite Bolt', -- [[MAG/113 - Mana: 2150 - Cast: 3s - Recast 6s  - Duration: 0s - Resist: Magic  - Target: Line of Sight - Effects: 1: Decrease Current HP by 30368 ]]
            'Korascian Bolt', -- [[MAG/108 - Mana: 1780 - Cast: 3s - Recast 6s  - Duration: 0s - Resist: Magic  - Target: Line of Sight - Effects: 1: Decrease Current HP by 20404 ]]
            'Meteoric Bolt',  -- [[MAG/103 - Mana: 1510 - Cast: 3s - Recast 6s  - Duration: 0s - Resist: Magic  - Target: Line of Sight - Effects: 1: Decrease Current HP by 16825 ]]
        },
        Options = { opt = 'USEMAGICNUKES' }
    },
    -- magic nuke + malo
    {
        Group = 'magicmalonuke',
        Spells = {
            'Memorial Steel Malosinera', -- [[MAG/124 - Mana: 500 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: Hate: -1 1: Cast: Highest Rank of Group - Malosinera (v470) 2: Cast: Highest Rank of Group - Shock of Memorial Steel (v470) ]]
            'Carbide Malosinetra',       -- [[MAG/119 - Mana: 435 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: Hate: -1 1: Cast: Highest Rank of Group - Malosinetra (v470) 2: Cast: Highest Rank of Group - Shock of Carbide Steel (v470) ]]
            'Burning Malosinara',        -- [[MAG/114 - Mana: 360 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: Hate: -1 1: Cast: Highest Rank of Group - Malosinara (v470) 2: Cast: Highest Rank of Group - Shock of Burning Steel (v470) ]]
            'Arcronite Malosinata',      -- [[MAG/109 - Mana: 300 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: Hate: -1 1: Cast: Highest Rank of Group - Malosinata (v470) 2: Cast: Highest Rank of Group - Shock of Arcronite Steel (v470) ]]
            'Darksteel Malosenete',      -- [[MAG/104 - Mana: 1970 - Cast: 3,25s - Recast 5,25s  - Duration: 0s - Resist: Unresistable  - Target: Single - Effects: Hate: -1 1: Cast: Malosenete (v374) 2: Cast: Shock of Darksteel (v374) ]]
        },
        Options = { opt = 'USEMAGICNUKES' }
    },
    -- targeted AE fire rain
    {
        Group = 'firerain',
        Spells = {
            'Rain of Molten Dacite',         -- [[MAG/123 - Mana: 4185 - Cast: 4s - Recast 12s T3 - Duration: 0s - Resist: Fire  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 45812 ]]
            'Rain of Molten Olivine',        -- [[MAG/118 - Mana: 3465 - Cast: 4s - Recast 12s T3 - Duration: 0s - Resist: Fire  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 37775 ]]
            'Rain of Molten Komatiite',      -- [[MAG/113 - Mana: 2605 - Cast: 4s - Recast 12s T3 - Duration: 0s - Resist: Fire  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 22842 ]]
            'Rain of Molten Rhyolite',       -- [[MAG/108 - Mana: 2171 - Cast: 4s - Recast 12s T3 - Duration: 0s - Resist: Fire  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 18834 ]]
            'Coronal Rain', --[[emu cutoff]] -- [[MAG/103 - Mana: 1808 - Cast: 4s - Recast 12s T3 - Duration: 0s - Resist: Fire  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 15530 ]]
            'Rain of Jerikor',               -- [[MAG/67 - Mana: 549 - Cast: 4s - Recast 12s T3 - Duration: 0s - Resist: Fire  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 1099 ]]
            'Rain of Lava',                  -- [[MAG/35 - Mana: 250 - Cast: 5,5s - Recast 12s T3 - Duration: 0s - Resist: Fire  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 172 ]]
            'Rain of Fire',                  -- [[MAG/17 - Mana: 125 - Cast: 3,5s - Recast 12s T3 - Duration: 0s - Resist: Fire  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 75 ]]
        },
        Options = {
            opt = 'USEAOE',
            threshold = 2,
            Gem = function(lvl)
                return (lvl == 70 and 2) or (lvl <= 60 and 4) or
                    nil
            end
        }
    },
    -- targeted AE magic rain
    {
        Group = 'magicrain',
        Spells = {
            'Rain of Kukris',                     -- [[MAG/124 - Mana: 4027 - Cast: 4s - Recast 12s T7 - Duration: 0s - Resist: Magic  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 44702 ]]
            'Rain of Falchions',                  -- [[MAG/119 - Mana: 3334 - Cast: 4s - Recast 12s T7 - Duration: 0s - Resist: Magic  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 36860 ]]
            'Rain of Scimitars',                  -- [[MAG/114 - Mana: 2507 - Cast: 4s - Recast 12s T7 - Duration: 0s - Resist: Magic  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 22289 ]]
            'Rain of Knives',                     -- [[MAG/109 - Mana: 2089 - Cast: 4s - Recast 12s T7 - Duration: 0s - Resist: Magic  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 18379 ]]
            'Rain of Cutlasses', --[[emu cutoff]] -- [[MAG/104 - Mana: 1739 - Cast: 4s - Recast 12s T7 - Duration: 0s - Resist: Magic  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 15154 ]]
            'Star Scream',                        -- [[MAG/70 - Mana: 598 - Cast: 6s - Recast 12s T7 - Duration: 0s - Resist: Magic  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 1237 ]]
            'Rain of Spikes',                     -- [[MAG/26 - Mana: 162 - Cast: 4,5s - Recast 12s T7 - Duration: 0s - Resist: Magic  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 91 ]]
            'Rain of Blades',                     -- [[MAG/10 - Mana: 62 - Cast: 2,75s - Recast 12s T7 - Duration: 0s - Resist: Magic  - Target: Target AE (4) - Effects: AE Waves: 3 1: Decrease Current HP by 26 ]]
        },
        Options = {
            opt = 'USEAOE',
            threshold = 2,
            Gem = function(lvl)
                return (lvl == 70 and 10) or (lvl <= 60 and 5) or
                    nil
            end
        }
    },
    {
        Group = 'pbaefire',
        Spells = {
            'Fiery Blast',   -- [[MAG/119 - Mana: 4916 - Cast: 4s - Recast 12s T2 - Duration: 0s - Resist: Fire  - Target: Caster PB (30) - Effects: 1: Decrease Current HP by 27771 ]]
            'Flaming Blast', -- [[MAG/114 - Mana: 3696 - Cast: 4s - Recast 12s T2 - Duration: 0s - Resist: Fire  - Target: Caster PB (30) - Effects: 1: Decrease Current HP by 16792 ]]
            'Burning Blast', -- [[MAG/109 - Mana: 3148 - Cast: 4s - Recast 12s T2 - Duration: 0s - Resist: Fire  - Target: Caster PB (30) - Effects: 1: Decrease Current HP by 11716 ]]
            'Searing Blast', -- [[MAG/104 - Mana: 2621 - Cast: 4s - Recast 12s T2 - Duration: 0s - Resist: Fire  - Target: Caster PB (30) - Effects: 1: Decrease Current HP by 9661 ]]
            'Flame Flux',    -- [[MAG/22 - Mana: 123 - Cast: 3,5s - Recast 6s  - Duration: 0s - Resist: Fire  - Target: Caster PB (30) - Effects: 1: Decrease Current HP by 96 ]]
        },
        Options = { opt = 'USEAOE', threshold = 4 }
    },
    {
        Group = 'frontalmagic',
        Spells = {
            'Beam of Kukris',    -- [[MAG/123 - Mana: 2481 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Magic -10 - Target: Frontal AE (12) - Effects: 1: Decrease Current HP by 26078 ]]
            'Beam of Falchions', -- [[MAG/118 - Mana: 2054 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Magic -10 - Target: Frontal AE (12) - Effects: 1: Decrease Current HP by 21503 ]]
            'Beam of Scimitars', -- [[MAG/113 - Mana: 1544 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Magic -10 - Target: Frontal AE (12) - Effects: 1: Decrease Current HP by 13002 ]]
            'Beam of Knives',    -- [[MAG/108 - Mana: 1287 - Cast: 3s - Recast 1,5s  - Duration: 0s - Resist: Magic -10 - Target: Frontal AE (12) - Effects: 1: Decrease Current HP by 10721 ]]
        },
        Options = { opt = 'USEAOE', threshold = 4 }
    },
    -- pet promised heal
    {
        Group = 'pethealpromise',
        Spells = {
            'Promised Reconstitution', -- [[MAG/123 BST/123 - Mana: 1815 - Cast: 0,25s - Recast 15s T12 - Duration: 18s - Resist: n/a - Target: Pet - Effects: 1: Cast: Promised Reconstitution Trigger on Duration Fade 2: Stacking: Delayed Heal Marker (111375) 3: Stacking: Block new spell if slot 2 is 'Delayed Heal Marker' and < 111375 4: Stacking: Overwrite existing spell if slot 2 is 'Delayed Heal Marker' and < 111375 ]]
            'Promised Relief',         -- [[MAG/118 BST/118 - Mana: 1502 - Cast: 0,25s - Recast 15s T12 - Duration: 18s - Resist: n/a - Target: Pet - Effects: 1: Cast: Promised Relief Trigger on Duration Fade 2: Stacking: Delayed Heal Marker (91837) 3: Stacking: Block new spell if slot 2 is 'Delayed Heal Marker' and < 91837 4: Stacking: Overwrite existing spell if slot 2 is 'Delayed Heal Marker' and < 91837 ]]
            'Promised Healing',        -- [[MAG/113 BST/113 - Mana: 1279 - Cast: 0,25s - Recast 15s T12 - Duration: 18s - Resist: n/a - Target: Pet - Effects: 1: Cast: Promised Healing Trigger on Duration Fade 2: Stacking: Delayed Heal Marker (75726) 3: Stacking: Block new spell if slot 2 is 'Delayed Heal Marker' and < 75726 4: Stacking: Overwrite existing spell if slot 2 is 'Delayed Heal Marker' and < 75726 ]]
            'Promised Alleviation',    -- [[MAG/108 BST/108 - Mana: 1066 - Cast: 0,25s - Recast 15s T12 - Duration: 18s - Resist: n/a - Target: Pet - Effects: 1: Cast: Promised Alleviation Trigger on Duration Fade 2: Stacking: Delayed Heal Marker (59727) 3: Stacking: Block new spell if slot 2 is 'Delayed Heal Marker' and < 59727 4: Stacking: Overwrite existing spell if slot 2 is 'Delayed Heal Marker' and < 59727 ]]
            'Promised Invigoration',   -- [[MAG/103 BST/103 - Mana: 887 - Cast: 0,25s - Recast 15s T12 - Duration: 18s - Resist: n/a - Target: Pet - Effects: 1: Cast: Promised Invigoration Trigger on Duration Fade 2: Stacking: Delayed Heal Marker (36116) 3: Stacking: Block new spell if slot 2 is 'Delayed Heal Marker' and < 36116 4: Stacking: Overwrite existing spell if slot 2 is 'Delayed Heal Marker' and < 36116 ]]
        },
        Options = { opt = 'HEALPET' }
    },
    -- random chance to heal all pets in area
    {
        Group = 'chaoticheal',
        Spells = {
            'Chaotic Magnanimity', -- [[MAG/124 - Mana: 2032 - Cast: 3s - Recast 1,5s  - Duration: 6m+ - Resist: n/a - Target: Self - Effects: 1: Cast: Chaotic Magnanimity Effect on Spell Use (10% Chance) 2: Limit Type: Detrimental 3: Limit Type: Exclude Combat Skills 4: Limit Effect: Current HP 5: Limit Min Mana Cost: 10 6: Limit Max Level: 125 (lose 100% per level) ]]
            'Chaotic Largesse',    -- [[MAG/119 - Mana: 1682 - Cast: 3s - Recast 1,5s  - Duration: 6m+ - Resist: n/a - Target: Self - Effects: 1: Cast: Chaotic Largesse Effect on Spell Use (10% Chance) 2: Limit Type: Detrimental 3: Limit Type: Exclude Combat Skills 4: Limit Effect: Current HP 5: Limit Min Mana Cost: 10 6: Limit Max Level: 120 (lose 100% per level) ]]
            'Chaotic Bestowal',    -- [[MAG/114 - Mana: 1433 - Cast: 3s - Recast 1,5s  - Duration: 6m+ - Resist: n/a - Target: Self - Effects: 1: Cast: Chaotic Bestowal Effect on Spell Use (10% Chance) 2: Limit Type: Detrimental 3: Limit Type: Exclude Combat Skills 4: Limit Effect: Current HP 5: Limit Min Mana Cost: 10 6: Limit Max Level: 115 (lose 100% per level) ]]
            'Chaotic Munificence', -- [[MAG/109 - Mana: 1194 - Cast: 3s - Recast 1,5s  - Duration: 6m+ - Resist: n/a - Target: Self - Effects: 1: Cast: Chaotic Munificence Effect on Spell Use (10% Chance) 2: Limit Type: Detrimental 3: Limit Type: Exclude Combat Skills 4: Limit Effect: Current HP 5: Limit Min Mana Cost: 10 6: Limit Max Level: 110 (lose 100% per level) ]]
            'Chaotic Benefaction', -- [[MAG/104 - Mana: 993 - Cast: 3s - Recast 1,5s  - Duration: 6m+ - Resist: n/a - Target: Self - Effects: Stacking: Chaotic Boons 13 1: Cast: Chaotic Benefaction Effect on Spell Use (10% Chance) 2: Limit Type: Detrimental 3: Limit Type: Exclude Combat Skills 4: Limit Effect: Current HP 5: Limit Min Mana Cost: 10 6: Limit Max Level: 105 (lose 100% per level) ]]
        },
        Options = { opt = 'HEALPET' }
    },
    -- minion summon clicky 2
    {
        Group = 'minion2',
        Spells = {
            'Summon Valorous Minion',   -- [[MAG/125 - Mana: 12349 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 159971] x 1 ]]
            'Summon Forbearing Minion', -- [[MAG/120 - Mana: 10224 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 124367] x 1 ]]
            'Summon Imperative Minion', -- [[MAG/115 - Mana: 8709 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 150408] x 1 ]]
            'Summon Insurgent Minion',  -- [[MAG/110 - Mana: 6967 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 64991] x 1 ]]
            'Summon Mutinous Minion',   -- [[MAG/105 - Mana: 5800 - Cast: 4,5s - Recast 0s  - Duration: 0s - Resist: n/a - Target: Self - Effects: 1: Summon: [Item 99813] x 1 ]]
        },
        Options = { opt = 'USEMINION', emu = false }
    },
    {
        Group = 'dispel',
        Spells = {
            'Nullify Magic', -- [[CLR/38 PAL/58 RNG/58 SHD/58 DRU/43 SHM/44 NEC/37 WIZ/34 MAG/32 ENC/28 BST/58 - Mana: 50 - Cast: 4,5s - Recast 6s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Dispel (4) 2: Dispel (4) ]]
            'Cancel Magic',  -- [[CLR/13 PAL/32 RNG/30 SHD/36 DRU/18 SHM/19 NEC/15 WIZ/11 MAG/10 ENC/7 BST/35 - Mana: 30 - Cast: 3,5s - Recast 5s  - Duration: 0s - Resist: n/a - Target: Single - Effects: 1: Dispel (1) ]]
        },
        Options = { debuff = true, dispel = true, opt = 'USEDISPEL' }
    },
    {
        Group = 'mala',
        Spells = {
            'Malaise', -- [[SHM/18 MAG/22 - Mana: 60 - Cast: 3s - Recast 6s  - Duration: 14m+ - Resist: Magic  - Target: Single - Effects: 2: Decrease Cold Resist by 20 3: Decrease Magic Resist by 20 4: Decrease Poison Resist by 20 5: Decrease Fire Resist by 20 ]]
        },
        Options = { debuff = true, opt = 'USEDEBUFF', Gem = function(lvl) return lvl <= 60 and 6 or nil end }
    }
}




Magician.compositeNames = {
    ['Ecliptic Companion'] = true,
    ['Composite Companion'] = true,
    ['Dissident Companion'] = true,
    ['Dichotomic Companion'] = true
}
Magician.allDPSSpellGroups = { 'servant', 'ofmany', 'chaotic', 'shock', 'spear1', 'spear2', 'prenuke', 'ofsand',
    'firebolt', 'sands', 'summonednuke', 'magicbolt', 'magicmalonuke', 'beam', 'firerain', 'magicrain', 'pbaefire',
    'frontalmagic' }

Magician.Abilities = {
    {
        Type = 'AA',
        Name = 'Summon Companion',
        Options = { key = 'summoncompanion' }
    },

    {
        Type = 'AA',
        Name = 'Force of Elements',
        Options = { dps = true }
    },
    {
        Type = 'Item',
        Name = 'Glyphwielder\'s Eternal Bracer',
        Options = { alias = 'NUKEORB2', summonMinimum = 1, nodmz = true, pause = true, selfbuff = true, combatbuff = true, combatbuffothers = true, emu = true }
    },

    -- Burns
    {
        Type = 'AA',
        Name = 'Fundament: First Spire of the Elements',
        Options = { first = true, emu = true }
    },
    {
        Type = 'AA',
        Name = 'Host of the Elements',
        Options = { first = true, delay = 1500, opt = 'USESWARMPETS' }
    },
    {
        Type = 'AA',
        Name = 'Servant of Ro',
        Options = { first = true, delay = 500, opt = 'USESWARMPETS' }
    },
    {
        Type = 'AA',
        Name = 'Frenzied Burnout',
        Options = { first = true }
    },
    {
        Type = 'AA',
        Name = 'Improved Twincast',
        Options = { first = true }
    },

    -- Buffs
    {
        Type = 'AA',
        Name = 'Elemental Form: Earth',
        Options = { selfbuff = true, opt = 'EARTHFORM' }
    },
    {
        Type = 'AA',
        Name = 'Elemental Form: Fire',
        Options = { opt = 'FIREFORM', selfbuff = true }
    },
    {
        Type = 'AA',
        Name = 'Large Modulation Shard',
        Options = { selfbuff = true, opt = 'SUMMONMODROD', summonMinimum = 1, nodmz = true, }
    },
    {
        Type = 'AA',
        Name = 'Fire Core',
        Options = { combatbuff = true }
    },
    {
        Type = 'Item',
        Name = 'Focus of Ancient Elements',
        Options = { first = true, epicburn = true, CheckFor = 'Elemental Conjunction' }
    },
    {
        Type = 'Item',
        Name = 'Focus of Primal Elements',
        Options = { first = true, epicburn = true, CheckFor = 'Elemental Conjunction' }
    },
    {
        Type = 'Item',
        Name = 'Staff of Elemental Essence',
        Options = { first = true, epicburn = true, CheckFor = 'Elemental Conjunction' }
    },
    {
        Type = 'AA',
        Name = 'Aegis of Kildrukaun',
        Options = { petbuff = true }
    },
    {
        Type = 'AA',
        Name = 'Fortify Companion',
        Options = { petbuff = true }
    },

    -- Debuffs
    {
        Type = 'AA',
        Name = 'Malosinete',
        Options = { debuff = true, opt = 'USEDEBUFF' }
    },

    -- Defensives
    {
        Type = 'AA',
        Name = 'Companion of Necessity',
        Options = { fade = true }
    }
}

function Magician:initSpellRotations()
    self:initBYOSCustom()
    self.spellRotations.standard = {}
    table.insert(self.spellRotations.standard, self.spells.servant)
    table.insert(self.spellRotations.standard, self.spells.ofmany)
    table.insert(self.spellRotations.standard, self.spells.chaotic)
    table.insert(self.spellRotations.standard, self.spells.shock)
    table.insert(self.spellRotations.standard, self.spells.magicrain)
    table.insert(self.spellRotations.standard, self.spells.firerain)
    table.insert(self.spellRotations.standard, self.spells.spear1)
    table.insert(self.spellRotations.standard, self.spells.spear2)
    table.insert(self.spellRotations.standard, self.spells.beam)
end

function Magician:getPetSpell()
    return self.spells[self.PetTypes[self:get('PETTYPE')]]
end

function Magician:pullCustom()
    if (mq.TLO.Target.Distance3D() or 300) > 175 then return end
    movement.stop()
    mq.cmd('/pet attack')
    mq.cmd('/pet swarm')
    mq.delay(1000)
end

-- Below pet arming code shamelessly stolen from Rekka and E3Next
local petToys = {
    weapons = {
        ['Grant Goliath\'s Armaments'] = {
            foldedBag = 'Folded Pack of Goliath\'s Armaments',
            fire = '',
            water = '',
            magic = '',
            aggro = '',
            deaggro = '',
        },
        ['Grant Shak Dathor\'s Armaments'] = {
            foldedBag = 'Folded Pack of Shak Dathor\'s Armaments',
            fire = 'Summoned: Shadewrought Fireblade',
            water = 'Summoned: Shadewrought Ice Spear',
            magic = 'Summoned: Shadewrought Staff',
            aggro = 'Summoned: Shadewrought Rageaxe',
            deaggro = 'Summoned: Shadewrought Mindmace',
        },
        ['Grant Yalrek\'s Armaments'] = {
            foldedBag = 'Folded Pack of Yalrek\'s Armaments',
            fire = 'Summoned: Silver Fireblade',
            water = 'Summoned: Silver Iceblade',
            magic = 'Summoned: Silver Shortsword',
            aggro = 'Summoned: Silver Ragesword',
            deaggro = 'Summoned: Silver Mindblade',
        },
        ['Grant Wirn\'s Armaments'] = {
            foldedBag = 'Folded Pack of Wirn\'s Armaments',
            fire = 'Summoned: Gorstruck Fireblade',
            water = 'Summoned: Gorstruck Iceblade',
            magic = 'Summoned: Gorstruck Shortsword',
            aggro = 'Summoned: Gorstruck Ragesword',
            deaggro = 'Summoned: Gorstruck Mindblade',
        },
        ['Grant Thassis\'s Armaments'] = {
            foldedBag = 'Folded Pack of Thalassic Armaments',
            fire = 'Summoned: Thalassic Fireblade',
            water = 'Summoned: Thalassic Iceblade',
            magic = 'Summoned: Thalassic Shortsword',
            aggro = 'Summoned: Thalassic Ragesword',
            deaggro = 'Summoned: Thalassic Mindblade',
        },
        ['Grant Spectral Armaments'] = {
            foldedBag = 'Folded Pack of Spectral Armaments',
            fire = 'Summoned: Fist of Flame',
            water = 'Summoned: Orb of Chilling Water',
            shield = 'Summoned: Buckler of Draining Defense',
            aggro = 'Summoned: Short Sword of Warding',
            slow = 'Summoned: Mace of Temporal Distortion',
            malo = 'Summoned: Spear of Maliciousness',
            dispel = 'Summoned: Wand of Dismissal',
            snare = 'Summoned: Tendon Carve,'
        },
        ['Summon Dagger of the Deep'] = {
            magic = 'Summoned: Dagger of the Deep',
        }
    },
    armor = {
        ['Grant Alloy\'s Plate'] = {
            foldedBag = 'Folded Pack of Alloy\'s Plate'
        },
        ['Grant the Centien\'s Plate'] = {
            foldedBag = 'Folded Pack of the Centien\'s Plate'
        },
        ['Grant Ocoenydd\'s Plate'] = {
            foldedBag = 'Folded Pack of Ocoenydd\'s Plate'
        },
        ['Grant Wirn\'s Plate'] = {
            foldedBag = 'Folded Pack of Wirn\'s Plate'
        },
        ['Grant Thassis\' Plate'] = {
            foldedBag = 'Folded Pack of Thalassic Plate'
        },
        ['Grant Spectral Plate'] = {
            foldedBag = 'Folded Pack of Spectral Plate'
        },
        ['Summon Phantom Plate'] = {
            foldedBag = 'Phantom Satchel'
        }
    },
    jewelry = {
        ['Grant Ankexfen\'s Heirlooms'] = {
            foldedBag = 'Folded Pack of Ankexfen\'s Heirlooms'
        },
        ['Grant the Diabo\'s Heirlooms'] = {
            foldedBag = 'Folded Pack of Diabo\'s Heirlooms'
        },
        ['Grant Crystasia\'s Heirlooms'] = {
            foldedBag = 'Folded Pack of Crystasia\'s Heirlooms'
        },
        ['Grant Ioulin\'s Heirlooms'] = {
            foldedBag = 'Folded Pack of Ioulin\'s Heirlooms'
        },
        ['Grant Calix\'s Heirlooms'] = {
            foldedBag = 'Folded Pack of Calix\'s Heirlooms'
        },
        ['Grant Enibik\'s Heirlooms'] = {
            foldedBag = 'Folded Pack of Enibik\'s Heirlooms'
        }
    },
    belts = {

    },
    masks = {

    }
}
local weaponBag = 'Pouch of Quellious'
local disenchantedBag = 'Huge Disenchanted Backpack'
--[[ local summonedItemMap = {
    ['Grant Shak Dathor\'s Armaments'] = 'Folded Pack of Shak Dathor\'s Armaments',
    ['Grant Spectral Armaments'] = 'Folded Pack of Spectral Armaments',
    ['Grant Spectral Plate'] = 'Folded Pack of Spectral Plate',
    ['Grant Enibik\'s Heirlooms'] = 'Folded Pack of Enibik\'s Heirlooms',
} ]]
local EnchanterPetPrimaryWeaponId = 10702

-- Checks pets for items and re-equips if necessary.
local armPetTimer = timer:new(60000)
function Magician:autoArmPets()
    if common.hostileXTargets() then return end
    if not self:isEnabled('ARMPETS') or not self.spells.weapons then return end
    if not armPetTimer:expired() then return end
    armPetTimer:reset()

    self:armPets()
end

function Magician:clearCursor()
    while mq.TLO.Cursor() do
        mq.cmd('/autoinv')
        mq.delay(100)
    end
end

local codex = 'Codex of Minion\'s Materiel'
local dsk = 'Glyphwielder\'s Ascendant Gloves of the Summoner'
function Magician:armPets()
    -- if mq.TLO.FindItem(codex)() then
    --     self:armPetsCodex()
    --     return
    -- end

    if mq.TLO.Cursor() then self:clearCursor() end
    if mq.TLO.Cursor() then
        logger.info('Unable to clear cursor, not summoning pet toys.')
        return
    end
    if not self.petWeapons then return end
    logger.info('Begin arming pets')
    state.paused = true
    local restoreGem1 = { Name = mq.TLO.Me.Gem(12)() }
    local restoreGem2 = { Name = mq.TLO.Me.Gem(11)() }
    local restoreGem3 = { Name = mq.TLO.Me.Gem(10)() }
    local restoreGem4 = { Name = mq.TLO.Me.Gem(9)() }

    local havedsk = mq.TLO.FindItem(dsk)()

    local petPrimary = mq.TLO.Pet.Primary()
    local petID = mq.TLO.Pet.ID()
    if petID > 0 and petPrimary == 0 then
        state.armPet = petID
        state.armPetOwner = mq.TLO.Me.CleanName()
        local weapons = self.petWeapons.Self
        if havedsk then weapons = 'corrupted|corrupted' end
        if weapons then
            if mq.TLO.FindItem(codex)() then
                mq.cmdf('/useitem "%s"', codex)
                mq.delay(5000)
            end
            self:armPet(petID, weapons, 'Me')
        end
    end

    for owner, weapons in pairs(self.petWeapons) do
        if owner ~= mq.TLO.Me.CleanName() then
            local ownerSpawn = mq.TLO.Spawn('pc =' .. owner)
            if ownerSpawn() then
                local ownerPetID = ownerSpawn.Pet.ID()
                local ownerPetDistance = ownerSpawn.Pet.Distance3D() or 300
                local ownerPetLevel = ownerSpawn.Pet.Level() or 0
                local ownerPetPrimary = ownerSpawn.Pet.Primary() or -1
                if ownerPetID > 0 and ownerPetDistance < 50 and ownerPetLevel > 0 and (havedsk or ownerPetPrimary == 0 or ownerPetPrimary == EnchanterPetPrimaryWeaponId) then
                    if havedsk then
                        weapons = 'corrupted|corrupted'
                    end
                    state.armPet = ownerPetID
                    state.armPetOwner = owner
                    mq.delay(2000, function() return self.spells.weapons:isReady() == abilities.IsReady.SHOULD_CAST end)
                    self:armPet(ownerPetID, weapons, owner)
                end
            end
        end
    end
    if mq.TLO.Me.Gem(12)() ~= restoreGem1.Name then abilities.swapSpell(restoreGem1, 12) end
    if mq.TLO.Me.Gem(11)() ~= restoreGem2.Name then abilities.swapSpell(restoreGem2, 11) end
    if mq.TLO.Me.Gem(10)() ~= restoreGem3.Name then abilities.swapSpell(restoreGem3, 10) end
    if mq.TLO.Me.Gem(9)() ~= restoreGem4.Name then abilities.swapSpell(restoreGem4, 9) end
    state.paused = false
end

function Magician:armPetRequest(requester)
    local weapons = nil
    local havedsk = mq.TLO.FindItem(dsk)()
    if havedsk then
        weapons = 'corrupted|corrupted'
    else
        if not self.petWeapons then return end
        weapons = self.petWeapons[requester]
        if not weapons then return end
    end
    local ownerSpawn = mq.TLO.Spawn('pc =' .. requester)
    if ownerSpawn() then
        local ownerPetID = ownerSpawn.Pet.ID()
        local ownerPetDistance = ownerSpawn.Pet.Distance3D() or 300
        local ownerPetLevel = ownerSpawn.Pet.Level() or 0
        local ownerPetPrimary = ownerSpawn.Pet.Primary() or -1
        if ownerPetID > 0 and ownerPetDistance < 50 and ownerPetLevel > 0 and (havedsk or ownerPetPrimary == 0 or ownerPetPrimary == EnchanterPetPrimaryWeaponId) then
            state.paused = true
            local restoreGem1 = { Name = mq.TLO.Me.Gem(12)() }
            local restoreGem2 = { Name = mq.TLO.Me.Gem(11)() }
            local restoreGem3 = { Name = mq.TLO.Me.Gem(10)() }
            local restoreGem4 = { Name = mq.TLO.Me.Gem(9)() }
            state.armPet = ownerPetID
            state.armPetOwner = requester
            mq.delay(2000, function() return self.spells.weapons:isReady() == abilities.IsReady.SHOULD_CAST end)
            self:armPet(ownerPetID, weapons, requester)
            if mq.TLO.Me.Gem(12)() ~= restoreGem1.Name then abilities.swapSpell(restoreGem1, 12) end
            if mq.TLO.Me.Gem(11)() ~= restoreGem2.Name then abilities.swapSpell(restoreGem2, 12) end
            if mq.TLO.Me.Gem(10)() ~= restoreGem3.Name then abilities.swapSpell(restoreGem3, 12) end
            if mq.TLO.Me.Gem(9)() ~= restoreGem4.Name then abilities.swapSpell(restoreGem4, 12) end
            state.paused = false
        end
    end
end

function Magician:armPet(petID, weapons, owner)
    logger.info('Attempting to arm pet %s for %s', mq.TLO.Spawn('id ' .. petID).CleanName(), owner)

    local myX, myY, myZ = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    if not self:giveWeapons(petID, weapons or 'water|fire') then
        movement.navToLoc(myX, myY, myZ, nil, 2000)
        if state.isExternalRequest then
            logger.info('tell %s There was an error arming your pet', state.requester)
        else
            logger.info('there was an issue with arming a pet')
        end
        return
    end
    if state.emu then
        if self.spells.armor then
            mq.delay(3000, function() return self.spells.armor:isReady() == abilities.IsReady.SHOULD_CAST end)
            if not self:giveOther(petID, self.spells.armor, 'armor') then return end
        end
        if self.spells.jewelry then
            mq.delay(3000, function() return self.spells.jewelry:isReady() == abilities.IsReady.SHOULD_CAST end)
            if not self:giveOther(petID, self.spells.jewelry, 'jewelry') then return end
        end
        if mq.TLO.FindItemCount('=Gold')() >= 1 then
            logger.info('have gold to give!')
            mq.cmdf('/mqt id %s', petID)
            self:pickupWeapon('Gold')
            if mq.TLO.Cursor() == 'Gold' then
                self:giveCursorItemToTarget()
            else
                self:clearCursor()
            end
        end
    end

    local petSpawn = mq.TLO.Spawn('id ' .. petID)
    if petSpawn() then
        logger.info('Finished arming %s', petSpawn.CleanName())
    end

    movement.navToLoc(myX, myY, myZ, nil, 2000)
end

function Magician:armPetsCodex()
    local numPets = mq.TLO.SpawnCount('pcpet radius 100')()
    for i = 1, numPets do
        local nearestpet = mq.TLO.NearestSpawn(i .. ',pcpet radius 100')
        mq.cmdf('/mqt id %s', nearestpet.ID())
        logger.info('Arming %s with codex', nearestpet.Name())
        -- while not mq.TLO.Me.Casting() do
        --     if mq.TLO.Me.ItemReady(codex)() then
        -- logger.info('Casting codex on %s', nearestpet.Name())
        mq.cmdf('/useitem "%s"', codex)
        --     end
        --     mq.delay(250)
        -- end
        mq.delay(3000)
        -- while mq.TLO.Me.Casting() do
        --     mq.delay(100)
        -- end
        -- mq.cmdf('/useitem "%s"', codex)
        -- mq.delay(250)
        -- if not mq.TLO.Me.ItemReady(codex)() then
        logger.info('Done arming %s with codex', nearestpet.Name())
        mq.delay(30000)
        -- end
    end
end

function Magician:giveWeapons(petID, weaponString)
    local weapons = helpers.split(weaponString, '|')
    local primary = ''
    local secondary = ''
    if weapons[1] == 'corrupted' then
        primary = 'Summoned: Companion\'s Corrupted Dirk'
        secondary = 'Summoned: Companion\'s Corrupted Dirk'
    else
        primary = petToys.weapons[self.spells.weapons.BaseName][weapons[1]]
        secondary = petToys.weapons[self.spells.weapons.BaseName][weapons[2]]
    end
    logger.info('weapons: %s %s', primary, secondary)
    if weapons[1] == 'corrupted' then
        mq.cmdf('/mqt id %s', petID)
        mq.cmdf('/useitem "%s"', dsk)
        mq.delay(500)
        mq.delay(10000, function() return mq.TLO.Me.ItemReady(dsk)() end)
        return true
    end

    mq.cmdf('/mqt 0')
    if not self:checkForWeapons(primary, secondary) then
        return false
    end

    mq.cmdf('/mqt id %s', petID)
    if mq.TLO.Target.ID() == petID then
        logger.info('Give primary weapon %s to pet %s', primary, petID)
        self:pickupWeapon(primary)
        if mq.TLO.Cursor() == primary then
            self:giveCursorItemToTarget()
        else
            self:clearCursor()
        end
        if not self:checkForWeapons(primary, secondary) then
            return false
        end
        logger.info('Give secondary weapon %s to pet %s', secondary, petID)
        self:pickupWeapon(secondary)
        mq.cmdf('/mqt id %s', petID)
        if mq.TLO.Cursor() == secondary then
            self:giveCursorItemToTarget()
        else
            self:clearCursor()
        end
        self:giveCursorItemToTarget()
    else
        return false
    end
    return true
end

-- If specifying 2 different weapons where only 1 of each is in the bag, this
-- will end up summoning two bags
function Magician:checkForWeapons(primary, secondary)
    local foundPrimary = mq.TLO.FindItem('=' .. primary)
    local foundSecondary = mq.TLO.FindItem('=' .. secondary)
    logger.info('Check inventory for weapons %s %s', primary, secondary)
    if not foundPrimary() or not foundSecondary() then
        local foundWeaponBag = mq.TLO.FindItem('=' .. weaponBag)
        if foundWeaponBag() then
            if not self:safeToDestroy(foundWeaponBag) then return false end
            mq.cmdf('/nomodkey /itemnotify "%s" leftmouseup', weaponBag)
            mq.delay(1000, function() return mq.TLO.Cursor() end)
            if mq.TLO.Cursor.ID() == foundWeaponBag.ID() then
                mq.cmd('/destroy')
            else
                logger.info('Unexpected item on cursor when trying to destroy %s', weaponBag)
                return false
            end
        else
            if not self:checkInventory() then
                if state.isExternalRequest then
                    logger.info('tell %s i was unable to free up inventory space', state.requester)
                else
                    logger.info('Unable to free up inventory space')
                end
                return false
            end
        end
        local summonResult = self:summonItem(self.spells.weapons, mq.TLO.Me.ID(),
            petToys.weapons[self.spells.weapons.BaseName].foldedBag, true)
        if not summonResult then
            logger.info('Error occurred summoning items')
            return false
        end
    end
    return true
end

function Magician:pickupWeapon(weaponName)
    local item = mq.TLO.FindItem('=' .. weaponName)
    local itemSlot = item.ItemSlot()
    local itemSlot2 = item.ItemSlot2()
    local packSlot = itemSlot - 22
    local inPackSlot = itemSlot2 + 1
    mq.cmdf('/nomodkey /ctrlkey /itemnotify in pack%s %s leftmouseup', packSlot, inPackSlot)
    mq.delay(100, function() return mq.TLO.Cursor.ID() == item.ID() end)
end

function Magician:giveOther(petID, spell, toyType)
    -- local itemName = petToys[toyType][spell.BaseName].foldedBag
    -- local item = mq.TLO.FindItem('='..itemName)
    --if not item() then
    mq.cmdf('/mqt id %s', petID)
    local summonResult = self:summonItem(spell, petID, false, false)
    if not summonResult then
        logger.info('Error occurred summoning items')
        return false
    end
    --else
    --    mq.cmdf('/nomodkey /itemnotify "%s" rightmouseup')
    --    mq.delay(3000, function() return mq.TLO.Cursor() end)
    --end

    --mq.cmdf('/mqt id %s', petID)
    --self.giveCursorItemToTarget()
    return true
end

function Magician:summonItem(spell, targetID, summonsItem, inventoryItem)
    logger.info('going to summon item %s', spell.Name)
    --mq.cmd('/mqt 0')
    if not mq.TLO.Me.Gem(spell.Name)() then
        abilities.swapSpell(spell, 12, true)
    end
    mq.delay(10000, function() return mq.TLO.Me.SpellReady(spell.Name)() end)
    if spell:isReady() ~= abilities.IsReady.SHOULD_CAST then
        logger.info('Spell %s was not ready', spell.Name)
        return false
    end
    castUtils.cast(spell, targetID)

    mq.delay(1000, function() return mq.TLO.Cursor() end)
    if summonsItem then
        if not mq.TLO.Cursor.ID() then
            logger.info('Cursor was empty after casting %s', spell.Name)
            return false
        end

        self:clearCursor()
        mq.cmdf('/nomodkey /itemnotify "%s" rightmouseup', summonsItem)
        mq.delay(3000, function() return mq.TLO.Cursor() end)
        mq.delay(1)
        if inventoryItem then self:clearCursor() end
    end
    return true
end

function Magician:giveCursorItemToTarget(moveback, clearTarget)
    local meX, meY, meZ = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    movement.navToTarget('dist=10', 2000)
    mq.cmd('/click left target')
    local targetType = mq.TLO.Target.Type()
    local windowType = 'TradeWnd'
    local buttonType = 'TRDW_Trade_Button'
    if targetType ~= 'PC' then
        windowType = 'GiveWnd'
        buttonType = 'GVW_Give_Button'
    end
    mq.delay(3000, function() return mq.TLO.Window(windowType).Open() end)
    if not mq.TLO.Window(windowType).Open() then
        mq.cmd('/autoinv')
        return
    end
    mq.cmdf('/squelch /nomodkey /notify %s %s leftmouseup', windowType, buttonType)
    mq.delay(3000, function() return not mq.TLO.Window(windowType).Open() end)
    if mq.TLO.Window(windowType).Open() then
        -- wait a bit?
        mq.delay(10000)
    end
    if clearTarget then
        mq.cmd('/squelch /nomodkey /keypress esc')
    end
    -- move back
    if moveback then
        movement.navToLoc(meX, meY, meZ, nil, 2000)
    end
end

function Magician:safeToDestroy(bag)
    for i = 1, bag.Container() do
        local bagSlot = bag.Item(i)
        if bagSlot() and not bagSlot.NoRent() then
            logger.info('DO NOT DESTROY: Found non-NoRent item: %s in summoned bag', bagSlot.Name())
            return false
        end
    end
    return true
end

function Magician:checkInventory()
    local pouch = 'Pouch of Quellious'
    local bag = mq.TLO.FindItem('=' .. pouch)
    local pouchID = bag.ID()
    local summonedItemCount = mq.TLO.FindItemCount('=' .. pouch)()
    logger.info('cleanup Pouch of Quellious')
    for i = 1, summonedItemCount do
        if not self:safeToDestroy(bag) then return false end
        mq.cmdf('/nomodkey /itemnotify "%s" leftmouseup', pouch)
        mq.delay(1000, function() return mq.TLO.Cursor.ID() == pouchID end)
        if mq.TLO.Cursor.ID() ~= pouchID then
            return false
        end
        mq.cmd('/destroy')
    end

    logger.info('cleanup Disenchanted Bags')
    bag = mq.TLO.FindItem('=' .. disenchantedBag)
    local bagID = bag.ID()
    summonedItemCount = mq.TLO.FindItemCount('=' .. disenchantedBag)()
    for i = 1, summonedItemCount do
        if not self:safeToDestroy(bag) then return false end
        mq.cmdf('/nomodkey /itemnotify "%s" leftmouseup', disenchantedBag)
        mq.delay(1000, function() return mq.TLO.Cursor.ID() == bagID end)
        if mq.TLO.Cursor.ID() ~= bagID then
            return false
        end
        mq.cmd('/destroy')
    end

    local containerWithOpenSpace = -1
    local slotToMoveFrom = -1
    local hasOpenInventorySlot = false

    -- if the first inventory slot is empty or an empty bag, this fails because it never sets containerWithOpenSpace
    logger.info('find bag slot')
    for i = 1, 10 do
        local currentSlot = i
        local containerSlots = mq.TLO.Me.Inventory('pack' .. i).Container()
        -- slots empty
        if not containerSlots then
            logger.info('empty slot! %s', currentSlot)
            slotToMoveFrom = -1
            return true
        end
    end
    for i = 1, 10 do
        local currentSlot = i
        local containerSlots = mq.TLO.Me.Inventory('pack' .. i).Container()
        local containerItemCount = mq.TLO.InvSlot('pack' .. i).Item.Items() or 0

        -- slots empty
        if not containerSlots then
            logger.info('empty slot! %s', currentSlot)
            slotToMoveFrom = -1
            hasOpenInventorySlot = true
            break
        end

        -- empty bag
        if containerItemCount == 0 then
            logger.info('found empty bag %s', currentSlot)
            slotToMoveFrom = i
            break
        end

        if (containerSlots or 0) - containerItemCount > 0 then
            logger.info('found bag with room')
            containerWithOpenSpace = i
        end

        -- its not a container or its empty, may move it
        if containerSlots == 0 or (containerSlots > 0 and containerItemCount == 0) then
            logger.info('found a item or empty bag we can move')
            slotToMoveFrom = currentSlot
        end
    end

    local freeInventory = mq.TLO.Me.FreeInventory()
    if freeInventory > 0 and containerWithOpenSpace > 0 and slotToMoveFrom > 0 then
        mq.cmdf('/nomodkey /itemnotify pack%s leftmouseup', slotToMoveFrom)
        mq.delay(250)

        if mq.TLO.Window('QuantityWnd').Open() then
            mq.cmd('/nomodkey /notify QuantityWnd QTYW_Accept_Button leftmouseup')
        end
        mq.delay(1000, function() return mq.TLO.Cursor() end)
        mq.delay(1)
    end

    freeInventory = mq.TLO.Me.FreeInventory()
    if freeInventory > 0 then
        hasOpenInventorySlot = true
    end

    if mq.TLO.Cursor.ID() and containerWithOpenSpace > 0 then
        local invslot = mq.TLO.Me.Inventory('pack' .. containerWithOpenSpace)
        local slots = invslot.Container()
        for i = 1, slots do
            local item = invslot.Item(i)
            if not item() then
                logger.info('/nomodkey /itemnotify in pack%s %s leftmouseup', containerWithOpenSpace, i)
                mq.cmdf('/nomodkey /itemnotify in pack%s %s leftmouseup', containerWithOpenSpace, i)
                mq.delay(1000, function() return not mq.TLO.Cursor() end)
                mq.delay(1)
                hasOpenInventorySlot = true
                break
            end
        end

        if mq.TLO.Cursor() then self:clearCursor() end
    end
    return hasOpenInventorySlot
end

return Magician
