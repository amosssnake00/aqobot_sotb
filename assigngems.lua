-- Smart Gem Assignment Utility for AQO
-- Automatically assigns gem slots to spells based on rotation priority and spell types
--
-- Classes can define essential spell groups by adding:
-- self.essentialSpellGroups = {
--     ['petheal'] = 'pet healing',
--     ['manaregen'] = 'mana recovery',
--     ['dispel'] = 'dispel magic'
-- }

local mq = require('mq')
local logger = require('utils.logger')
local constants = require('constants')

local assigngems = {}

-- Priority order for different spell types
local SPELL_TYPE_PRIORITY = {
    dps = 1,      -- Main DPS spells get highest priority
    debuff = 2,   -- Debuffs second
    buff = 3,     -- Buffs third
    heal = 4,     -- Heals fourth
    utility = 5   -- Utilities last
}

-- Gem slot preferences (lower gems for more important spells)
local PREFERRED_GEMS = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
}

---Analyze spell importance based on rotation position and type
---@param spell table
---@param rotationPosition number
---@return number priority score (lower = higher priority)
local function calculateSpellPriority(spell, rotationPosition)
    local priority = rotationPosition or 999
    
    -- Adjust priority based on spell type
    if spell.dps then
        priority = priority + (SPELL_TYPE_PRIORITY.dps * 100)
    elseif spell.debuff then
        priority = priority + (SPELL_TYPE_PRIORITY.debuff * 100)
    elseif spell.selfbuff or spell.singlebuff or spell.combatbuff then
        priority = priority + (SPELL_TYPE_PRIORITY.buff * 100)
    elseif spell.heal or spell.regular or spell.panic or spell.group then
        priority = priority + (SPELL_TYPE_PRIORITY.heal * 100)
    else
        priority = priority + (SPELL_TYPE_PRIORITY.utility * 100)
    end
    
    -- Higher priority for spells with no options (always used)
    if not spell.opt then
        priority = priority - 50
    end
    
    return priority
end

---Get all spells that should be assigned to gems
---@param class table The class instance
---@param quiet boolean If true, reduce debug output
---@param assignedGems table Current gem assignments
---@param numGems number Number of available gem slots
---@return table spells to assign
local function getSpellsToAssign(class, quiet, assignedGems, numGems)
    local spellsToAssign = {}
    
    -- Get spells from current rotation - force getting the actual selected rotation
    local spellSet = class:get('SPELLSET') or 'standard'
    local rotation = nil
    
    -- Get the actual selected rotation, respecting custom
    if spellSet == 'custom' and class.customRotation and #class.customRotation > 0 then
        rotation = class.customRotation
    elseif class.spellRotations and class.spellRotations[spellSet] then
        rotation = class.spellRotations[spellSet]
    else
        rotation = class:getSpellRotation() -- fallback to existing logic
    end
    
    -- Build rotation spell names for replacement logic
    local rotationSpellNames = {}
    if rotation then
        for _, spell in ipairs(rotation) do
            if spell and spell.Name then
                -- Check if spell is enabled based on class options
                local spellEnabled = true
                
                if spell.opt and class.options[spell.opt] then
                    spellEnabled = class.options[spell.opt].value == true
                elseif spell.opt and not class.options[spell.opt] then
                    -- Option doesn't exist, assume enabled
                    spellEnabled = true
                end
                
                if spellEnabled then
                    rotationSpellNames[spell.Name] = true
                end
            end
        end
    end
    
    if not quiet then
        logger.info("=== Analyzing Current Spell Rotation ===")
        logger.info("Selected spell set: %s", spellSet)
        if rotation then
            logger.info("Active rotation has %d spells:", #rotation)
            for i, spell in ipairs(rotation) do
                if spell then
                    logger.info("  %d. %s (Group: %s, CastType: %s)", i, spell.Name, spell.Group or 'unknown', spell.CastType or 'unknown')
                end
            end
        else
            logger.info("No active rotation found")
        end
    end
    
    if rotation then
        for i, spell in ipairs(rotation) do
            if spell and spell.CastType == 1 then -- Only memorizable spells
                -- Check if spell is enabled based on class options FIRST
                local spellEnabled = true
                local disabledReason = ""
                
                -- Check if spell is enabled based on class options FIRST
                if spell.opt and class.options[spell.opt] then
                    spellEnabled = class.options[spell.opt].value == true
                    if not spellEnabled then
                        disabledReason = string.format("(%s=%s)", spell.opt, tostring(class.options[spell.opt].value))
                    end
                elseif spell.opt and not class.options[spell.opt] then
                    -- Option doesn't exist, assume disabled and warn
                    spellEnabled = false
                    disabledReason = string.format("(option %s not found)", spell.opt)
                    if not quiet then
                        logger.info("  Warning: Option %s not found for spell %s, treating as disabled", spell.opt, spell.Name)
                    end
                end
                
                -- Debug: show spell option info
                if not quiet then
                    if spell.opt then
                        local optionExists = class.options[spell.opt] ~= nil
                        local optionValue = optionExists and class.options[spell.opt].value or "not found"
                        logger.info("  Spell %s has option %s = %s -> enabled: %s", spell.Name, spell.opt, tostring(optionValue), tostring(spellEnabled))
                    else
                        logger.info("  Spell %s has no option -> enabled: %s", spell.Name, tostring(spellEnabled))
                    end
                end
                
                if not spellEnabled then
                    if not quiet then
                        logger.info("  → Skipped %s: disabled by option %s", spell.Name, disabledReason)
                    end
                elseif spell.Gem then
                    -- Check if this spell's gem assignment is valid (not disabled by function)
                    local gem = spell.Gem
                    if type(gem) == 'function' then
                        gem = gem(mq.TLO.Me.Level())
                    end
                    
                    if gem then
                        if not quiet then
                            logger.info("  → Skipped %s: already has gem assignment (gem %s)", spell.Name, tostring(gem))
                        end
                    else
                        -- Gem function returned nil, treat as if no gem assignment
                        local priority = calculateSpellPriority(spell, i)
                        table.insert(spellsToAssign, {
                            spell = spell,
                            priority = priority,
                            source = 'rotation',
                            rotationPos = i
                        })
                        if not quiet then
                            logger.info("  → Added to assignment list: %s (gem function returned nil, priority: %d)", spell.Name, priority)
                        end
                    end
                else
                    -- Spell is enabled and doesn't have gem assignment
                    local priority = calculateSpellPriority(spell, i)
                    table.insert(spellsToAssign, {
                        spell = spell,
                        priority = priority,
                        source = 'rotation',
                        rotationPos = i
                    })
                    if not quiet then
                        logger.info("  → Added to assignment list: %s (priority: %d)", spell.Name, priority)
                    end
                end
            elseif spell and not quiet then
                if spell.CastType ~= 1 then
                    logger.info("  → Skipped %s: not a memorizable spell (CastType: %s)", spell.Name, spell.CastType or 'nil')
                end
            end
        end
    end
    
    -- Add important spells not in rotation (only essential ones)
    if not quiet then
        logger.info("=== Checking Non-Rotation Essential Spells ===")
    end
    
    for groupName, spell in pairs(class.spells) do
        if spell and not spell.Gem and spell.CastType == 1 then
            local inRotation = false
            if rotation then
                for _, rotSpell in ipairs(rotation) do
                    if rotSpell and rotSpell.Name == spell.Name then
                        inRotation = true
                        break
                    end
                end
            end
            
            if not inRotation then
                -- Only include very important non-rotation spells
                local isEssential = false
                local reason = ""
                
                -- Self-protection buffs
                if spell.selfbuff and (groupName:find('rune') or groupName:find('shield') or groupName:find('skin')) then
                    isEssential = true
                    reason = "essential self-protection buff"
                -- Cure spells
                elseif spell.cure and groupName:find('cure') then
                    isEssential = true 
                    reason = "cure spell"
                -- Emergency heals
                elseif spell.heal and spell.panic then
                    isEssential = true
                    reason = "emergency heal"
                -- Pet heals for pet classes
                elseif spell.heal and spell.pet and constants.petClasses[class.class] then
                    isEssential = true
                    reason = "pet heal"
                -- Conditional DPS spells (like concussion with aggro conditions)
                elseif spell.dps and spell.condition then
                    isEssential = true
                    reason = "conditional DPS spell"
                -- Dispel abilities
                elseif spell.debuff and groupName:find('dispel') then
                    isEssential = true
                    reason = "dispel ability"
                -- Utility spells that are commonly used
                elseif groupName:find('harvest') and spell.recover then
                    isEssential = true
                    reason = "mana recovery spell"
                -- Check if spell group is marked as essential in class
                elseif spell.essential or (class.essentialSpellGroups and class.essentialSpellGroups[groupName]) then
                    isEssential = true
                    reason = class.essentialSpellGroups and class.essentialSpellGroups[groupName] or "marked as essential"
                end
                
                if isEssential then
                    local priority = calculateSpellPriority(spell, 999)
                    table.insert(spellsToAssign, {
                        spell = spell,
                        priority = priority,
                        source = 'essential',
                        rotationPos = nil
                    })
                    if not quiet then
                        logger.info("  → Added essential spell: %s (%s, priority: %d)", spell.Name, reason, priority)
                    end
                elseif not quiet then
                    logger.info("  → Skipped %s: not essential (%s)", spell.Name, groupName)
                end
            end
        end
    end
    
    -- DISABLED: Force replacement logic is causing too many issues
    -- Instead, just focus on assigning unassigned spells to empty gems
    if not quiet and #spellsToAssign == 0 then
        logger.info("=== No unassigned spells found ===")
        logger.info("All enabled rotation spells already have gem assignments.")
        logger.info("Use manual gem assignments in class files if you need to change layouts.")
    end
    
    -- Sort by priority (lowest number = highest priority)
    table.sort(spellsToAssign, function(a, b) return a.priority < b.priority end)
    
    if not quiet then
        logger.info("=== Final Priority Order ===")
        for i, entry in ipairs(spellsToAssign) do
            logger.info("  %d. %s (priority: %d, source: %s%s)", 
                i, 
                entry.spell.Name, 
                entry.priority, 
                entry.source,
                entry.rotationPos and (", rotation pos: " .. entry.rotationPos) or "")
        end
    end
    
    return spellsToAssign
end

---Assign gems to spells intelligently
---@param class table The class instance
---@param dryRun boolean If true, only print what would be assigned
---@param quiet boolean If true, reduce logging output for background operation
function assigngems.autoAssignGems(class, dryRun, quiet)
    if not class or not class.spells then
        logger.info("No valid class provided to assigngems")
        return
    end
    
    local numGems = mq.TLO.Me.NumGems() or 8
    local assignedGems = {}
    local assignments = {}
    
    -- Build assignedGems first, then call getSpellsToAssign
    -- Check for existing gem assignments and identify unused slots
    local assignedSpells = {} -- Track which spells have already been assigned
    local existingAssignments = {}
    local rotationSpellNames = {}
    local unusedGems = {}
    
    -- Get the rotation to build rotation spell names
    local spellSet = class:get('SPELLSET') or 'standard'
    local rotation = nil
    
    if spellSet == 'custom' and class.customRotation and #class.customRotation > 0 then
        rotation = class.customRotation
    elseif class.spellRotations and class.spellRotations[spellSet] then
        rotation = class.spellRotations[spellSet]
    else
        rotation = class:getSpellRotation()
    end
    
    -- Build list of spell names in current rotation (only enabled spells)
    if rotation then
        for _, spell in ipairs(rotation) do
            if spell and spell.Name then
                -- Check if spell is enabled based on class options
                local spellEnabled = true
                
                if spell.opt and class.options[spell.opt] then
                    spellEnabled = class.options[spell.opt].value == true
                elseif spell.opt and not class.options[spell.opt] then
                    -- Option doesn't exist, assume enabled
                    spellEnabled = true
                end
                
                if spellEnabled then
                    rotationSpellNames[spell.Name] = true
                end
            end
        end
    end
    
    for _, spell in pairs(class.spells) do
        if spell.Gem then
            -- Check if this spell should have its gem assignment based on options
            local shouldAssignGem = true
            if spell.opt and class.options[spell.opt] then
                shouldAssignGem = class.options[spell.opt].value == true
            elseif spell.opt and not class.options[spell.opt] then
                -- Option doesn't exist, assume disabled
                shouldAssignGem = false
            end
            
            if shouldAssignGem then
                local gem = spell.Gem
                if type(gem) == 'function' then
                    gem = gem(mq.TLO.Me.Level())
                end
                -- Skip if gem function returned nil (spell shouldn't be assigned)
                if gem and gem <= numGems then
                -- Check for duplicate gem assignments
                if assignedGems[gem] then
                    if not quiet then
                        logger.info("WARNING: Duplicate assignment to gem %d - %s and %s", gem, assignedGems[gem].Name, spell.Name)
                    end
                    -- Find next available gem for the duplicate
                    for nextGem = 1, numGems do
                        if not assignedGems[nextGem] then
                            gem = nextGem
                            if not quiet then
                                logger.info("  → Moving %s to gem %d", spell.Name, gem)
                            end
                            break
                        end
                    end
                end
                
                assignedGems[gem] = spell
                assignedSpells[spell.Name] = gem
                
                local inCurrentRotation = rotationSpellNames[spell.Name] == true
                table.insert(existingAssignments, {
                    gem = gem, 
                    spell = spell.Name, 
                    inRotation = inCurrentRotation
                })
                
                -- Mark gems with non-rotation spells as candidates for replacement
                -- Only mark non-essential spells for replacement
                local isEssential = spell.selfbuff or spell.cure or spell.recover or 
                                  (spell.debuff and (spell.Group and spell.Group:find('dispel'))) or
                                  (spell.heal and spell.panic)
                if not inCurrentRotation and not isEssential then
                    table.insert(unusedGems, gem)
                end
                end
            else
                if not quiet then
                    logger.info("Skipping gem assignment for %s: option %s = %s", spell.Name, spell.opt or "none", 
                               spell.opt and class.options[spell.opt] and tostring(class.options[spell.opt].value) or "disabled")
                end
            end
        end
    end
    
    local spellsToAssign = getSpellsToAssign(class, quiet, assignedGems, numGems)
    
    if not quiet then
        logger.info("Smart Gem Assignment for %s", class.class)
        logger.info("Available gem slots: %d", numGems)
        logger.info("Spells to assign: %d", #spellsToAssign)
        
        if dryRun then
            logger.info("=== DRY RUN - No changes will be made ===")
        end
    end
    
    -- Sort and display existing assignments
    if not quiet and #existingAssignments > 0 then
        table.sort(existingAssignments, function(a, b) return a.gem < b.gem end)
        logger.info("=== Existing Gem Assignments ===")
        for _, assignment in ipairs(existingAssignments) do
            local status = assignment.inRotation and "(in rotation)" or "(not in rotation)"
            logger.info("Existing assignment: Gem %d = %s %s", assignment.gem, assignment.spell, status)
        end
        
        if #unusedGems > 0 then
            table.sort(unusedGems)
            logger.info("Gems available for replacement: %s", table.concat(unusedGems, ", "))
        end
    end
    
    -- Assign gems to spells
    local assignmentCount = 0
    
    for _, entry in ipairs(spellsToAssign) do
        if assignmentCount >= numGems then break end
        
        local spell = entry.spell
        local spellName = spell.Name
        local assigned = false
        
        -- Skip if this spell is already assigned to a gem
        if assignedSpells[spellName] then
            if not quiet then
                logger.info("Skipping duplicate spell: %s (already assigned to gem %d)", spellName, assignedSpells[spellName])
            end
            goto continue
        end
        
        -- Try to assign to preferred gem slots (empty slots only for now)
        local slotsToTry = {}
        
        -- First, add truly empty slots
        for _, gemSlot in ipairs(PREFERRED_GEMS) do
            if gemSlot <= numGems and not assignedGems[gemSlot] then
                table.insert(slotsToTry, gemSlot)
            end
        end
        
        for _, gemSlot in ipairs(slotsToTry) do
            if gemSlot <= numGems then
                -- Check if we're replacing an existing spell
                local replacingSpell = assignedGems[gemSlot]
                if replacingSpell and not quiet then
                    logger.info("  → Replacing %s in gem %d with %s", replacingSpell.Name, gemSlot, spellName)
                end
                
                assignedGems[gemSlot] = spell
                assignedSpells[spellName] = gemSlot -- Track this assignment
                
                if not dryRun then
                    -- If we're force replacing, clear the old assignment first
                    if entry.forceReplace and assignedSpells[spellName] then
                        local oldGem = assignedSpells[spellName]
                        for _, otherSpell in pairs(class.spells) do
                            if otherSpell.Name == spellName and otherSpell.Gem == oldGem then
                                otherSpell.Gem = nil
                                if not quiet then
                                    logger.info("  → Cleared old assignment: %s from gem %d", spellName, oldGem)
                                end
                            end
                        end
                    end
                    
                    -- Clear any existing Gem assignments for this spell name from other spell objects
                    for _, otherSpell in pairs(class.spells) do
                        if otherSpell.Name == spellName and otherSpell ~= spell then
                            if not quiet then
                                logger.info("  → Clearing duplicate gem assignment: %s.Gem = %s", otherSpell.Name, tostring(otherSpell.Gem))
                            end
                            otherSpell.Gem = nil
                        end
                    end
                    -- Assign to this spell object
                    spell.Gem = gemSlot
                    if not quiet then
                        logger.info("  → Assigned: %s.Gem = %d", spellName, gemSlot)
                    end
                end
                
                table.insert(assignments, {
                    gem = gemSlot,
                    spell = spellName,
                    group = spell.Group or 'unknown',
                    priority = entry.priority,
                    source = entry.source
                })
                
                assignmentCount = assignmentCount + 1
                assigned = true
                break
            end
        end
        
        if not assigned and not quiet then
            logger.info("Could not assign gem for spell: %s (no free slots)", spellName)
        end
        
        ::continue::
    end
    
    -- Print assignments
    if not quiet then
        logger.info("=== Gem Assignments ===")
        table.sort(assignments, function(a, b) return a.gem < b.gem end)
        
        for _, assignment in ipairs(assignments) do
            local status = assignedGems[assignment.gem] and assignedGems[assignment.gem].Name == assignment.spell and "ASSIGNED" or "FAILED"
            logger.info("Gem %2d: %-25s (Group: %-12s, Source: %s) - %s", 
                assignment.gem, 
                assignment.spell, 
                assignment.group,
                assignment.source,
                status)
        end
    end
    
    if not dryRun and not quiet then
        -- Save the updated gem assignments to settings
        class:saveSettings()
        logger.info("Gem assignments updated and saved!")
        if class:get('BYOS') then
            logger.info("BYOS mode is enabled - you'll need to manually memorize spells or disable BYOS.")
            logger.info("To disable BYOS: /aqo BYOS false")
            logger.info("Then use: /aqo loadspells")
        else
            logger.info("Use '/aqo loadspells' to memorize the assigned spells.")
        end
    elseif dryRun and not quiet then
        logger.info("Run '/aqo assigngems apply' to make these changes permanent.")
    end
    
    return assignments
end

return assigngems