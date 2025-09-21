local mq = require 'mq'
local config = require('interface.configuration')
local helpers = require('utils.helpers')
local logger = require('utils.logger')
local movement = require('utils.movement')
local timer = require('libaqo.timer')
local common = require('common')
local mode = require('mode')
local state = require('state')

local camp = {
    Active = false,
    X = 0,
    Y = 0,
    Z = 0,
    Heading = 0,
    ZoneID = 0,
    PullArcLeft = 0,
    PullArcRight = 0,
}

function camp.init() end

function camp.mobRadarB()
    local distanceFromCamp = false
    local x, y, z
    if camp.Active or mode.currentMode:getName() ~= 'huntertank' then
        distanceFromCamp = true
        x, y, z = camp.X, camp.Y, camp.Z
    end
    local xtarIDs = {}
    for i = 1, 20 do
        local xtarID = mq.TLO.Me.XTarget(i).ID()
        if xtarID then
            xtarIDs[xtarID] = true
        end
    end
    local function campPredicate(spawn)
        if spawn.Type() ~= 'NPC' then return false end
        if distanceFromCamp then
            local d = helpers.distance(x, y, spawn.X(), spawn.Y())
            if d > config.get('CAMPRADIUS') ^ 2 then return false end
        else
            if spawn.Distance3D() > config.get('CAMPRADIUS') then return false end
        end
        if not xtarIDs[spawn.ID()] then return false end
        return true
    end

    -- Preserve existing mob data (especially mez timers) when refreshing targets
    local oldTargets = state.targets or {}
    local newTargets = mq.getFilteredSpawns(campPredicate)
    
    -- Merge old data with new spawn data, preserving timers and other mob-specific data
    for id, spawn in pairs(newTargets) do
        if oldTargets[id] then
            -- Preserve existing mob data (timers, flags, etc.)
            newTargets[id] = oldTargets[id]
            -- Update name in case it changed (shouldn't happen but just in case)
            newTargets[id].Name = spawn.CleanName()
        else
            -- New mob, create basic entry
            newTargets[id] = { Name = spawn.CleanName() }
        end
    end
    
    state.targets = newTargets
    state.mobCount = #state.targets
    state.mobCountNoPets = #state.targets
end

local aggressive_count = 'npc radius %d zradius 50 loc %d %d %d'
local aggressive_spawn = '%d, npc radius %d zradius 50 loc %d %d %d'
local aggressive_nopet_count = 'npc radius %d zradius 50 nopet loc %d %d %d'
local xtar_count = 'xtarhater npc radius %d zradius 50 loc %d %d %d'
local xtar_spawn = '%d, xtarhater npc radius %d zradius 50 loc %d %d %d'
local xtar_nopet_count = 'xtarhater radius %d zradius 50 nopet loc %d %d %d'
---Determine the number of mobs within the camp radius.
---Uses optimized filtered spawn approach instead of individual spawn queries.
---Sets state.mobCount and adds valid mobs to state.targets table.
function camp.mobRadar()
    local x, y, z
    local distanceFromCamp = false
    
    if not camp.Active or mode.currentMode:getName() == 'huntertank' then
        x, y, z = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    else
        x, y, z = camp.X, camp.Y, camp.Z
        distanceFromCamp = true
    end
    
    -- Get xtarget IDs for filtering
    local xtarIDs = {}
    local me = mq.TLO.Me
    for i = 1, me.XTargetSlots() do
        local xtarID = me.XTarget(i).ID()
        if xtarID and xtarID > 0 then
            xtarIDs[xtarID] = true
        end
    end
    
    -- Optimized predicate function for spawn filtering
    local function campPredicate(spawn)
        if spawn.Type() ~= 'NPC' then return false end
        if not spawn.Aggressive() then return false end
        
        -- Distance check
        if distanceFromCamp then
            local d = helpers.distance(x, y, spawn.X(), spawn.Y())
            if d > (config.get('CAMPRADIUS') or 0) ^ 2 then return false end
        else
            if spawn.Distance3D() > (config.get('CAMPRADIUS') or 0) then return false end
        end
        
        -- Only include mobs on xtarget for aggressive filtering
        -- Exception: always include mobs that are being tanked or should be tanked
        local mobID = spawn.ID()
        if not xtarIDs[mobID] and mobID ~= state.tankMobID and mobID ~= state.pullMobID and mobID ~= state.assistMobID then
            return false
        end
        return true
    end
    
    -- Use efficient filtered spawn approach
    local validSpawns = mq.getFilteredSpawns(campPredicate)
    local mobCount = 0
    local mobCountNoPets = 0
    
    -- Preserve existing mob data (especially mez timers) when refreshing targets
    local oldTargets = {}
    for k, v in pairs(state.targets) do oldTargets[k] = v end
    
    -- Clear existing targets and rebuild with preserved data
    for k in pairs(state.targets) do state.targets[k] = nil end
    
    for _, spawn in ipairs(validSpawns) do
        local mob_id = spawn.ID()
        if mob_id and mob_id > 0 then
            mobCount = mobCount + 1
            if spawn.Type() ~= 'Pet' then
                mobCountNoPets = mobCountNoPets + 1
            end
            
            -- Preserve existing mob data if it exists, otherwise create new
            if oldTargets[mob_id] then
                state.targets[mob_id] = oldTargets[mob_id]
                -- Update name in case it changed
                state.targets[mob_id].Name = spawn.CleanName()
            else
                state.targets[mob_id] = { Name = spawn.CleanName() }
            end
        end
    end
    
    state.mobCount = mobCount
    state.mobCountNoPets = mobCountNoPets
end

---Checks for any mobs in common.TARGETS which are no longer valid and removes them from the table.
function camp.cleanTargets()
    for mobid, _ in pairs(state.targets) do
        local spawn = mq.TLO.Spawn(string.format('id %s', mobid))
        if not spawn() or spawn.Type() == 'Corpse' then
            state.targets[mobid] = nil
        end
    end
end

function camp.returnToCamp(force)
    local distToCamp = helpers.distance(mq.TLO.Me.X(), mq.TLO.Me.Y(), camp.X, camp.Y)
    if state.mobCount > 0 then
        -- allow some buffer to campradius when checking returntocamp with mobs in camp.. allow to keep fighting stuff near the edge.
        -- if toons are any further out maybe they were summoned out of camp or something.
        if force or distToCamp > (config.get('CAMPRADIUS') + 25) ^ 2 then
            movement.navToLoc(camp.X, camp.Y, camp.Z)
        end
    else
        -- otherwise if camp is empty, move back in if more than halfway out from camp center.
        if force or distToCamp > config.get('CAMPRETURN') then
            movement.navToLoc(camp.X, camp.Y, camp.Z)
        end
    end
end

---Return to camp if alive and in a camp mode and not currently fighting and more than 15ft from the camp center location.
local checkCampTimer = timer:new(2000)
function camp.checkCamp(force)
    if not mode.currentMode:isReturnToCampMode() or not camp.Active then return end
    if not force and not checkCampTimer:expired() then return end
    -- if mq.TLO.Me.CombatState() == 'COMBAT' or mq.TLO.Me.Combat() or mq.TLO.Me.AutoFire() then return end
    if not force then checkCampTimer:reset() end
    if (state.class ~= 'BRD' and mq.TLO.Me.Casting()) then return end -- or not common.clearToBuff() then return end
    if mq.TLO.Zone.ID() ~= camp.ZoneID then
        logger.info('Clearing camp due to zoning.')
        camp.Active = false
        return
    end
    camp.returnToCamp(force)
end

---Draw a maploc at the given heading on the pull radius circle.
---@param camp_x number @
---@param camp_y number @
---@param heading number @The MQ heading degrees pointing to where to draw the maploc.
---@param color string @The color input to the /maploc command.
local function drawMapLoc(camp_x, camp_y, camp_z, heading, color)
    if heading < 0 then
        heading = 360 - heading
    elseif heading > 360 then
        heading = heading - 360
    end
    local x_move = math.cos(math.rad(helpers.convertHeading(heading)))
    if x_move > 0 and heading > 0 and heading < 180 then
        x_move = x_move * -1
    elseif x_move < 0 and heading >= 180 then
        x_move = math.abs(x_move)
    end
    local y_move = math.sin(math.rad(helpers.convertHeading(heading)))
    if y_move > 0 and heading > 90 and heading < 270 then
        y_move = y_move * -1
    elseif y_move < 0 and (heading <= 90 or heading >= 270) then
        y_move = math.abs(y_move)
    end
    local x_off = camp_x + config.get('PULLRADIUS') * x_move
    local y_off = camp_y + config.get('PULLRADIUS') * y_move
    mq.cmdf('/squelch /maploc size 10 width 2 color %s radius 5 rcolor 0 0 0 %s %s %s', color, y_off, x_off, camp_z)
end

---Set the left and right pull arc values based on the configured PULLARC option.
local function setPullAngles()
    local pull_arc = config.get('PULLARC')
    if not pull_arc or pull_arc == 0 then return end
    if not camp.Heading then camp.Heading = 0 end
    if camp.Heading - (pull_arc * .5) < 0 then
        camp.PullArcLeft = 360 - ((pull_arc * .5) - camp.Heading)
    else
        camp.PullArcLeft = camp.Heading - (pull_arc * .5)
    end
    if camp.Heading + (pull_arc * .5) > 360 then
        camp.PullArcRight = (pull_arc * .5) + camp.Heading - 360
    else
        camp.PullArcRight = (pull_arc * .5) + camp.Heading
    end
    logger.debug(logger.flags.routines.camp, 'arcleft: %s, arcright: %s', camp.PullArcLeft, camp.PullArcRight)
end

---Set, update or clear the CAMP values depending on whether currently in a camp mode or not.
---@param reset boolean|nil @If true, then reset the camp to pickup the latest options.
function camp.setCamp(reset)
    local mode = mode.currentMode
    if mode:isCampMode() then
        mq.cmd('/squelch /maploc remove')
        if not camp.Active or reset then
            camp.Active = true
            camp.X = mq.TLO.Me.X()
            camp.Y = mq.TLO.Me.Y()
            camp.Z = mq.TLO.Me.Z()
            camp.Heading = mq.TLO.Me.Heading.Degrees()
            camp.ZoneID = mq.TLO.Zone.ID()
        end
        if mode:isPullMode() then
            -- Only draw pull arc/radius markers if polygon pull is not enabled
            if not config.get('POLYGONPULL_ENABLED') then
                if config.get('PULLARC') > 0 and config.get('PULLARC') < 360 then
                    setPullAngles()
                    drawMapLoc(camp.X, camp.Y, camp.Z, camp.PullArcLeft, '0 0 255')
                    drawMapLoc(camp.X, camp.Y, camp.Z, camp.PullArcRight, '0 0 255')
                    drawMapLoc(camp.X, camp.Y, camp.Z, camp.Heading, '255 0 0')
                else
                    camp.PullArcLeft = 0
                    camp.PullArcRight = 0
                end
                mq.cmdf('/squelch /maploc size 10 width 1 color 0 0 255 radius %s rcolor 0 0 255 %s %s %s',
                    config.get('PULLRADIUS'), camp.Y, camp.X, camp.Z)
            else
                camp.PullArcLeft = 0
                camp.PullArcRight = 0
            end
        else
            camp.PullArcLeft = 0
            camp.PullArcRight = 0
        end
        logger.info('Camp set to \ayX: %.02f Y: %.02f Z: %.02f R: %s H: %.02f\ax', camp.X, camp.Y, camp.Z,
            config.get('CAMPRADIUS'), camp.Heading)
        mq.cmdf('/squelch /maploc size 10 width 1 color 255 0 0 radius %s rcolor 255 0 0 %s %s %s',
            config.get('CAMPRADIUS'), camp.Y + 1, camp.X + 1, camp.Z)
        
        -- Redraw polygon markers if polygon pull is enabled
        if config.get('POLYGONPULL_ENABLED') then
            local pull = require('routines.pull')
            pull.drawAllPolygonMarkers()
        end
    elseif camp.Active then
        camp.Active = false
        mq.cmd('/squelch /mapf campradius 0')
        mq.cmd('/squelch /mapf pullradius 0')
        mq.cmd('/squelch /maploc remove')
    end
end

---Set, update or clear the CAMP values depending on whether currently in a camp mode or not.
function camp.setCampCustom(X, Y, Z, Heading, ZoneID)
    local mode = mode.currentMode
    if (not mode:isCampMode()) and (not mode:isPullMode()) then
        mode.currentMode = mode.modes.tank
    end
    mq.cmd('/squelch /maploc remove')
    camp.Active = true
    camp.X = tonumber(X)
    camp.Y = tonumber(Y)
    camp.Z = tonumber(Z)
    camp.Heading = tonumber(Heading)
    camp.ZoneID = tonumber(ZoneID)
    if mode:isPullMode() then
        -- Only draw pull arc/radius markers if polygon pull is not enabled
        if not config.get('POLYGONPULL_ENABLED') then
            if config.get('PULLARC') > 0 and config.get('PULLARC') < 360 then
                setPullAngles()
                drawMapLoc(camp.X, camp.Y, camp.Z, camp.PullArcLeft, '0 0 255')
                drawMapLoc(camp.X, camp.Y, camp.Z, camp.PullArcRight, '0 0 255')
                drawMapLoc(camp.X, camp.Y, camp.Z, camp.Heading, '255 0 0')
            else
                camp.PullArcLeft = 0
                camp.PullArcRight = 0
            end
            mq.cmdf('/squelch /maploc size 10 width 1 color 0 0 255 radius %s rcolor 0 0 255 %s %s %s',
                config.get('PULLRADIUS'), camp.Y, camp.X, camp.Z)
        else
            camp.PullArcLeft = 0
            camp.PullArcRight = 0
        end
    end

    logger.info('Camp set to \ayX: %.02f Y: %.02f Z: %.02f R: %s H: %.02f\ax', camp.X, camp.Y, camp.Z,
        config.get('CAMPRADIUS'), camp.Heading)
    mq.cmdf('/squelch /maploc size 10 width 1 color 255 0 0 radius %s rcolor 255 0 0 %s %s %s',
        config.get('CAMPRADIUS'), camp.Y + 1, camp.X + 1, camp.Z)
    
    -- Redraw polygon markers if polygon pull is enabled
    if config.get('POLYGONPULL_ENABLED') then
        local pull = require('routines.pull')
        pull.drawAllPolygonMarkers()
    end
end


return camp
