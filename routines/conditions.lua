local mq = require('mq')
local config = require('interface.configuration')
local constants = require('constants')
local state = require('state')
local logger = require('utils.logger')

local class
local conditions = {}

function conditions.init(_class)
    class = _class
end

function conditions.isEnabled(ability)
    return not ability.opt or class:isEnabled(ability.opt)
end

-- Heal Ability conditions

function conditions.spawnBelowHealPct(spawn)
    return (spawn.PctHPs() or 100) < config.get('HEALPCT')
end

function conditions.spawnBelowPanicHealPct(spawn)
    return (spawn.PctHPs() or 100) < config.get('PANICHEALPCT')
end

function conditions.spawnBelowGroupHealPct(spawn)
    return (spawn.PctHPs() or 100) < config.get('GROUPHEALPCT')
end

function conditions.spawnBelowHoTHealPct(spawn)
    return (spawn.PctHPs() or 100) < config.get('HOTHEALPCT')
end

-- Buff Ability conditions

function conditions.classesTarget(ability)
    return conditions.classes(ability, mq.TLO.Target)
end

function conditions.classes(ability, spawn)
    return not ability.classes or ability.classes[spawn.Class.ShortName()]
end

function conditions.missingPetCheckFor(ability)
    return not mq.TLO.Pet.Buff(ability.CheckFor)()
end

function conditions.missingPetBuff(ability)
    return not mq.TLO.Pet.Buff(ability.Name)()
end

function conditions.missingBuff(ability)
    return not conditions.hasBuff(ability)
end

function conditions.hasBuff(ability)
    return mq.TLO.Me.Buff(ability.Name)() or mq.TLO.Me.Song(ability.Name)()
end

function conditions.missingCheckFor(ability)
    return not conditions.checkFor(ability)
end

function conditions.checkFor(ability)
    return not ability.CheckFor or mq.TLO.Me.Buff(ability.CheckFor)() or mq.TLO.Me.Song(ability.CheckFor)()
end

function conditions.skipIfBuff(ability)
    return not ability.skipifbuff or not (mq.TLO.Me.Buff(ability.skipifbuff)() or mq.TLO.Me.Song(ability.skipifbuff)())
end

function conditions.dmz(ability)
    return not ability.dmz or constants.DMZ[mq.TLO.Zone.ID()]
end

function conditions.summonMinimum(ability)
    return not ability.summonMinimum or mq.TLO.FindItemCount(ability.SummonID)() < ability.summonMinimum
end

function conditions.stacksPet(ability)
    return not mq.TLO.Pet.Buff(ability.Name)() and mq.TLO.Spell(ability.Name).StacksPet()
end

function conditions.checkMana(ability)
    return mq.TLO.Me.CurrentMana() >= mq.TLO.Spell(ability.Name).Mana()
end

-- Recover Ability conditions

function conditions.aboveMinHP(ability)
    return not ability.minhp or mq.TLO.Me.PctHPs() > ability.minhp
end

-- TODO: define hpbelow
function conditions.belowDesiredHP(ability)
    return not ability.hpbelow or mq.TLO.Me.PctHPs() < ability.hpbelow
end

-- TODO: define manabelow
function conditions.belowDesiredMana(ability)
    return not ability.manabelow or mq.TLO.Me.PctMana() < ability.manabelow
end

-- TODO: define endbelow
function conditions.belowDesiredEndurance(ability)
    return not ability.endbelow or mq.TLO.Me.PctEndurance() < ability.endbelow
end

function conditions.inCombat(ability)
    return not ability.combat or mq.TLO.Me.CombatState() == 'COMBAT'
end

function conditions.OOC(ability)
    local combatState = mq.TLO.Me.CombatState()
    return not ability.ooc or combatState == 'ACTIVE' or combatState == 'RESTING'
end

-- DPS Ability conditions

function conditions.burnType(ability)
    return not state.burn_type or ability[state.burn_type]
end

function conditions.targetHPBelow(ability)
    local targetHP = mq.TLO.Target.PctHPs() or 100
    return not ability.usebelowpct or targetHP <= ability.usebelowpct
end

function conditions.withinMaxDistance(ability)
    local targetDistance = mq.TLO.Target.Distance3D() or 300
    return not ability.maxdistance or targetDistance <= ability.maxdistance
end

function conditions.withinMeleeDistance(ability)
    local targetDistance = mq.TLO.Target.Distance3D() or 300
    local targetMaxRange = mq.TLO.Target.MaxRangeTo() or 0
    return targetDistance <= targetMaxRange and mq.TLO.Target.LineOfSight() and
    mq.TLO.Me.Heading() == mq.TLO.Target.HeadingTo()
end

function conditions.aboveMobThreshold(ability)
    return ability.threshold == nil or ability.threshold <= state.mobCountNoPets
end

function conditions.useBash(ability)
    return (mq.TLO.Me.AltAbility('Improved Bash')() or mq.TLO.Me.Inventory('offhand').Type() == 'Shield')
        and (mq.TLO.Target.Distance3D() or 100) < (mq.TLO.Target.MaxMeleeTo() or 0) and
        mq.TLO.Me.Heading() == mq.TLO.Target.HeadingTo()
end

function conditions.aggroBelow(ability)
    local aggropct = mq.TLO.Target.PctAggro() or 100
    return ability.aggro == nil or aggropct < 100
end

function conditions.lowAggroInMelee(ability)
    local aggropct       = mq.TLO.Target.PctAggro() or 100
    local targetDistance = mq.TLO.Target.Distance3D() or 300
    local targetMaxRange = mq.TLO.Target.MaxRangeTo() or 0
    return (ability.aggro == nil or aggropct < 100) and targetDistance <= targetMaxRange
end

function conditions.mobsMissingAggro()
    if state.mobCount >= 2 then
        local xtar_aggro_count = 0
        for i = 1, 13 do
            local xtar = mq.TLO.Me.XTarget(i)
            if xtar.ID() ~= mq.TLO.Target.ID() and xtar.TargetType() == 'Auto Hater' and xtar.PctAggro() < 100 then
                xtar_aggro_count = xtar_aggro_count + 1
            end
        end
        return xtar_aggro_count > 0
    end
end

-- Cure Ability conditions

function conditions.radiantCureNeeded()
    logger.debug(logger.flags.routines.cure, 'ENTER radiantCureNeeded check')
    
    -- Check self first
    local selfDisease = (mq.TLO.Me.CountersDisease and mq.TLO.Me.CountersDisease()) or 0
    local selfPoison = (mq.TLO.Me.CountersPoison and mq.TLO.Me.CountersPoison()) or 0
    local selfCurse = (mq.TLO.Me.CountersCurse and mq.TLO.Me.CountersCurse()) or 0
    
    logger.debug(logger.flags.routines.cure, 'Self counters: Disease=%s Poison=%s Curse=%s', 
        selfDisease, selfPoison, selfCurse)
    
    if selfDisease > 0 or selfPoison > 0 or selfCurse > 0 then
        logger.debug(logger.flags.routines.cure, 'EXIT radiantCureNeeded: true (self needs cure)')
        return true
    end
    
    -- Check group members within 100 feet
    local groupSize = mq.TLO.Group.GroupSize() or 0
    logger.debug(logger.flags.routines.cure, 'Checking %s group members for cure needs', groupSize)
    
    for i = 1, groupSize - 1 do
        local member = mq.TLO.Group.Member(i)
        if member.Present() then
            local memberName = member.CleanName() or ('Member' .. i)
            local distance = member.Distance3D() or 300
            
            logger.debug(logger.flags.routines.cure, 'Checking %s: distance=%s', memberName, distance)
            
            if distance <= 100 then
                local memberDisease = (member.CountersDisease and member.CountersDisease()) or 0
                local memberPoison = (member.CountersPoison and member.CountersPoison()) or 0
                local memberCurse = (member.CountersCurse and member.CountersCurse()) or 0
                
                logger.debug(logger.flags.routines.cure, '%s counters: Disease=%s Poison=%s Curse=%s', 
                    memberName, memberDisease, memberPoison, memberCurse)
                
                -- Check for specific counters that Radiant Cure reduces by 9
                if memberDisease > 0 or memberPoison > 0 or memberCurse > 0 then
                    logger.debug(logger.flags.routines.cure, 'EXIT radiantCureNeeded: true (%s needs cure)', memberName)
                    return true
                end
            else
                logger.debug(logger.flags.routines.cure, '%s out of range (distance=%s > 100)', memberName, distance)
            end
        else
            logger.debug(logger.flags.routines.cure, 'Member %s not present in zone', i)
        end
    end
    
    logger.debug(logger.flags.routines.cure, 'EXIT radiantCureNeeded: false (no one needs cure)')
    return false
end

return conditions
