local mq = require 'mq'
local config = require('interface.configuration')
local camp = require('routines.camp')
local helpers = require('utils.helpers')
local logger = require('utils.logger')
local movement = require('utils.movement')
local timer = require('libaqo.timer')
local abilities = require('ability')
local constants = require('constants')
local common = require('common')
local mode = require('mode')
local state = require('state')

local class
local pull = {}

function pull.init(_class)
    class = _class
    
    -- Load polygon points from class settings
    if class.polygonPoints and #class.polygonPoints > 0 then
        -- Create a deep copy to avoid reference issues
        polygonPoints = {}
        for i, point in ipairs(class.polygonPoints) do
            polygonPoints[i] = {point[1], point[2]}
        end
        local centerAndRadius = calculatePolygonCenterAndRadius(polygonPoints)
        if centerAndRadius then
            polygonCenter = centerAndRadius
            polygonRadius = centerAndRadius.radius
        end
        -- Draw markers for loaded polygon points
        pull.drawAllPolygonMarkers()
    else
        -- No polygon points defined, clear any existing markers
        mq.cmd('/squelch /maploc remove')
    end
end

-- Pull Functions

local PULL_TARGET_SKIP = {}

local pull_range = nil

-- Polygon pull points - stored as {{x1,y1}, {x2,y2}, ...}
local polygonPoints = {}
local polygonCenter = nil
local polygonRadius = nil

-- No longer need local polygon sets - using config system

---
-- Calculates the compass angle in degrees of a target point relative to a center point.
-- Assumes EverQuest's coordinate system: 0/360=North, 90=East, 180=South, 270=West.
-- @param center_x The x-coordinate of the center point.
-- @param center_y The y-coordinate of the center point.
-- @param target_x The x-coordinate of the target point.
-- @param target_y The y-coordinate of the target point.
-- @return number The angle in degrees, normalized to [0, 360).
local function getCompassAngle(center_x, center_y, target_x, target_y)
    -- This is the only line that changed.
    -- By subtracting target from center for X, we invert the axis to match the server's coordinate system.
    local dx = center_x - target_x 
    local dy = target_y - center_y
    
    -- atan2 returns angle in radians from positive x-axis (East), counter-clockwise.
    local angle_rad = math.atan2(dy, dx)
    local angle_deg = math.deg(angle_rad)
    
    -- Convert the mathematical angle to a compass heading.
    local compass_heading = (450 - angle_deg) % 360
    
    return compass_heading
end

---
-- Checks if a target point is located within a given angular sector (defined by two angles).
-- Handles cases where the angular range crosses the 360-degree mark.
-- @param center table: A table with x and y keys for the origin point (e.g., {x=0, y=0}).
-- @param target table: A table with x and y keys for the point to check.
-- @param start_angle number: The starting angle of the sector in degrees (0-360).
-- @param end_angle number: The ending angle of the sector in degrees (0-360).
-- @return boolean: True if the point is within the sector, false otherwise.
local function isPointInSector(center, target, start_angle, end_angle)
    -- Calculate the actual angle of the target relative to the center
    local target_angle = getCompassAngle(center.x, center.y, target.x, target.y)

    -- Normalize boundary angles to ensure they are within the [0, 360) range
    local s = (start_angle % 360 + 360) % 360
    local e = (end_angle % 360 + 360) % 360

    -- Check for the wrap-around case (e.g., a range from 315 to 45 degrees)
    if s > e then
        -- If the range crosses 0/360, the target angle must be either
        -- greater than the start OR smaller than the end.
        if target_angle >= s or target_angle <= e then
            return true
        end
    else
        -- This is the normal case where the range does not cross 0/360.
        if target_angle >= s and target_angle <= e then
            return true
        end
    end
    
    return false
end


-- false invalid, true valid
---Determine whether the pull spawn is within the configured pull arc, if there is one.
---@param pull_spawn MQSpawn @The MQ Spawn to check.
---@return boolean @Returns true if the spawn is within the pull arc, otherwise false.
local function checkMobAngle(pull_spawn)
    local pull_arc = config.get('PULLARC')
    if pull_arc == 360 or pull_arc == 0 then return true end
    -- TODO: pull arcs without camp set???
    if not camp.Active then return true end
    --local direction_to_mob = getCompassAngle(camp.X, camp.Y, pull_spawn.X(), pull_spawn.Y())
    local direction_to_mob = pull_spawn.HeadingTo(camp.Y, camp.X).Degrees()
    if not direction_to_mob then return false end
    -- switching from non-puller mode to puller mode, the camp may not be updated yet
    if not (camp.PullArcLeft and camp.PullArcRight) then return false end
    logger.debug(logger.flags.routines.pull, 'mob id: %s, arcleft: %s, arcright: %s, dirtomob: %s',pull_spawn.ID(), camp.PullArcLeft,
        camp.PullArcRight, direction_to_mob)
    if camp.PullArcLeft >= camp.PullArcRight then
        if direction_to_mob < camp.PullArcLeft and direction_to_mob > camp.PullArcRight then return false end
    else
        if direction_to_mob < camp.PullArcLeft or direction_to_mob > camp.PullArcRight then return false end
    end
    return true
end

-- z check done separately so that high and low values can be different
---Determine whether the pull spawn is within the configured Z high and Z low values.
---@param pull_spawn MQSpawn @The MQ Spawn to check.
---@return boolean @Returns true if the spawn is within the Z high and Z low, otherwise false.
local function checkZRadius(pull_spawn)
    local mob_z = pull_spawn.Z()
    if not mob_z then return false end
    if camp.Active then
        if mob_z > camp.Z + config.get('PULLHIGH') or mob_z < camp.Z - config.get('PULLLOW') then return false end
    else
        if mob_z > mq.TLO.Me.Z() + config.get('PULLHIGH') or mob_z < mq.TLO.Me.Z() - config.get('PULLLOW') then return false end
    end
    return true
end

---Determine whether the pull spawn is within the configured pull level range.
---@param pull_spawn MQSpawn @The MQ Spawn to check.
---@return boolean @Returns true if the spawn is within the configured level range, otherwise false.
local function checkMobLevel(pull_spawn)
    if config.get('PULLMINLEVEL') == 0 and config.get('PULLMAXLEVEL') == 0 then return true end
    local mob_level = pull_spawn.Level()
    if not mob_level then return false end
    return mob_level >= config.get('PULLMINLEVEL') and mob_level <= config.get('PULLMAXLEVEL')
end

local function checkPathLength(pull_spawn)
    local path_len = mq.TLO.Navigation.PathLength(string.format('id %s', pull_spawn.ID()))()
    if path_len < 0 or path_len > config.get('PULLPATH') then
        logger.debug(logger.flags.routines.pull, 'Navigation PathLength %s exceeds PullPath %s', path_len,
            config.get('PULLPATH'))
        return -1
    end
    return path_len
end

---Checks if a point is inside a polygon using the Ray Casting algorithm.
---@param point_x number @The x-coordinate of the point to check.
---@param point_y number @The y-coordinate of the point to check.
---@param polygon table @A table of ordered vertices, where each vertex is a table {x_coord, y_coord}, e.g., {{x1,y1}, {x2,y2}, ...}.
---@return boolean @True if the point is inside the polygon, false otherwise.
local function isPointInPolygon(point_x, point_y, polygon)
    -- Validate the input point's coordinates first
    if not point_x or not point_y then
        -- Consider adding a logger.debug here if this case should be exceptional
        -- logger.debug(logger.flags.routines.pull, "isPointInPolygon: Received nil for point_x or point_y.")
        return false
    end

    local numVertices = #polygon
    if numVertices < 3 then
        -- logger.debug(logger.flags.routines.pull, "isPointInPolygon: Polygon has less than 3 vertices.")
        return false -- Not a polygon
    end

    local inside = false

    -- p1 is the last vertex in the polygon, forming the first edge with polygon[1]
    local p1x = polygon[numVertices][1]
    local p1y = polygon[numVertices][2]

    -- Robustness: Check if the initial polygon vertex is valid
    if not p1x or not p1y then
        logger.debug(logger.flags.routines.pull, "isPointInPolygon: Invalid coordinates for vertex %d in polygon.",
            numVertices)
        return false
    end

    for i = 1, numVertices do
        -- p2 is the current vertex in the loop
        local p2x = polygon[i][1]
        local p2y = polygon[i][2]

        -- Robustness: Check if the current polygon vertex is valid
        if not p2x or not p2y then
            logger.debug(logger.flags.routines.pull, "isPointInPolygon: Invalid coordinates for vertex %d in polygon.", i)
            return false -- Invalid polygon structure
        end

        -- Check if the horizontal ray crosses the edge (p1x,p1y) to (p2x,p2y)
        -- (point_y < p2y) ~= (point_y < p1y) checks if the edge straddles the horizontal line at point_y
        if (point_y < p2y) ~= (point_y < p1y) then
            -- Calculate the x-intersection of the ray and the edge's extended line.
            -- This check is only performed if the edge is not horizontal (p1y ~= p2y),
            -- because if p1y == p2y, the first condition ((point_y < p2y) ~= (point_y < p1y)) will be false.
            if point_x < (p1x - p2x) * (point_y - p2y) / (p1y - p2y) + p2x then
                inside = not inside -- Toggle the inside state for each crossing
            end
        end

        -- Move to the next edge: current p2 becomes the new p1
        p1x = p2x
        p1y = p2y
    end

    return inside
end

--- Calculates the centroid (center) of a polygon and the radius to encompass all points.
--- The center is the average of all vertices.
--- The radius is the distance from center to the furthest vertex.
--- @param polygon_points table @A table of ordered vertices, e.g., {{x1,y1}, {x2,y2}, ...}.
--- @return table|nil @A table {x, y, radius} or nil if not enough points.
local function calculatePolygonCenterAndRadius(polygon_points)
    if not polygon_points or #polygon_points < 2 then
        logger.debug(logger.flags.routines.pull, 'Polygon has less than 2 points for center calculation.')
        return nil
    end

    -- Calculate centroid (average of all vertices)
    local sum_x, sum_y = 0, 0
    for i = 1, #polygon_points do
        local point = polygon_points[i]
        if not point or not point[1] or not point[2] then
            logger.debug(logger.flags.routines.pull, 'Invalid point format in polygon at index %d.', i)
            return nil
        end
        sum_x = sum_x + point[1]
        sum_y = sum_y + point[2]
    end
    
    local center_x = sum_x / #polygon_points
    local center_y = sum_y / #polygon_points
    
    -- Find the maximum distance from center to any vertex (this becomes our radius)
    local max_distance_sq = 0
    for i = 1, #polygon_points do
        local point = polygon_points[i]
        local dist_sq = (point[1] - center_x) ^ 2 + (point[2] - center_y) ^ 2
        if dist_sq > max_distance_sq then
            max_distance_sq = dist_sq
        end
    end
    
    local radius = math.sqrt(max_distance_sq)
    logger.debug(logger.flags.routines.pull, 'polygon center %d, %d + radius %d.', center_x, center_y, radius)
    return { x = center_x, y = center_y, radius = radius }
end

---Add a point to the polygon using current target position, or specified coordinates
---@param x number|nil @The x coordinate of the point (optional, uses current target if nil, or current pos if no target)
---@param y number|nil @The y coordinate of the point (optional, uses current target if nil, or current pos if no target)
function pull.addPolygonPoint(x, y)
    -- If no coordinates provided, use current target position
    if not x or not y then
        local target = mq.TLO.Target
        if not target() then
            logger.info('No target selected for polygon point, using current position')
            x, y = mq.TLO.Me.X(), mq.TLO.Me.Y()
        else
            x, y = target.X(), target.Y()
        end
    end
    
    if not x or not y then return false end
    table.insert(polygonPoints, {x, y})
    
    -- Recalculate center and radius
    local centerAndRadius = calculatePolygonCenterAndRadius(polygonPoints)
    if centerAndRadius then
        polygonCenter = centerAndRadius
        polygonRadius = centerAndRadius.radius
    end
    
    -- Remove all markers and re-add them (to ensure clean state)
    mq.cmd('/squelch /maploc remove')
    pull.drawAllPolygonMarkers()
    pull.redrawCampMarkers()
    
    -- Save to class settings
    if class then
        -- Create a deep copy to ensure proper persistence
        class.polygonPoints = {}
        for i, point in ipairs(polygonPoints) do
            class.polygonPoints[i] = {point[1], point[2]}
        end
        class:saveSettings()
    end
    
    return true
end

---Remove a point from the polygon by index
---@param index number @The index of the point to remove
function pull.removePolygonPoint(index)
    if not index or index < 1 or index > #polygonPoints then return end
    table.remove(polygonPoints, index)
    
    -- Recalculate center and radius
    local centerAndRadius = calculatePolygonCenterAndRadius(polygonPoints)
    if centerAndRadius then
        polygonCenter = centerAndRadius
        polygonRadius = centerAndRadius.radius
    else
        polygonCenter = nil
        polygonRadius = nil
    end
    
    -- Remove all markers and re-add remaining ones
    mq.cmd('/squelch /maploc remove')
    pull.drawAllPolygonMarkers()
    pull.redrawCampMarkers()
    
    -- Save to class settings
    if class then
        -- Create a deep copy to ensure proper persistence
        class.polygonPoints = {}
        for i, point in ipairs(polygonPoints) do
            class.polygonPoints[i] = {point[1], point[2]}
        end
        class:saveSettings()
    end
end

---Clear all polygon points
function pull.clearPolygon()
    polygonPoints = {}
    polygonCenter = nil
    polygonRadius = nil
    
    -- Remove all map markers
    mq.cmd('/squelch /maploc remove')
    pull.redrawCampMarkers()
    
    -- Save to class settings
    if class then
        -- Create a deep copy to ensure proper persistence
        class.polygonPoints = {}
        for i, point in ipairs(polygonPoints) do
            class.polygonPoints[i] = {point[1], point[2]}
        end
        class:saveSettings()
    end
end

---List all polygon points
function pull.listPolygonPoints()
    if #polygonPoints == 0 then
        logger.info('No polygon points defined')
        return
    end
    
    logger.info('Polygon points:')
    for i, point in ipairs(polygonPoints) do
        logger.info('  %d: %.2f, %.2f', i, point[1], point[2])
    end
    
    if polygonCenter then
        logger.info('Center: %.2f, %.2f (radius: %.2f)', polygonCenter.x, polygonCenter.y, polygonRadius)
    end
end

---Get polygon points for UI display
---@return table @Array of polygon points
function pull.getPolygonPoints()
    return polygonPoints
end

---Debug function to check polygon points
function pull.debugPolygonPoints()
    logger.info('=== POLYGON POINTS DEBUG ===')
    logger.info('Local polygonPoints table has %d entries', #polygonPoints)
    for i, point in ipairs(polygonPoints) do
        logger.info('  Point %d: %.2f, %.2f', i, point[1], point[2])
    end
    if class and class.polygonPoints then
        logger.info('Class polygonPoints table has %d entries', #class.polygonPoints)
        for i, point in ipairs(class.polygonPoints) do
            logger.info('  Class Point %d: %.2f, %.2f', i, point[1], point[2])
        end
    else
        logger.info('Class polygonPoints is nil or empty')
    end
    logger.info('=== END DEBUG ===')
end

---Save current polygon points as a named set
---@param setName string @Name for the polygon set
---@param note string @Optional description/note
function pull.savePolygonSet(setName, note)
    if #polygonPoints == 0 then
        logger.info('No polygon points to save')
        return false
    end
    
    if not setName or setName == '' then
        logger.info('Set name cannot be empty')
        return false
    end
    
    local zone = mq.TLO.Zone.ShortName()
    local pointsCopy = {}
    for i, point in ipairs(polygonPoints) do
        pointsCopy[i] = {point[1], point[2]}
    end
    
    config.addPolygonSet(setName, zone, note, pointsCopy)
    logger.info('Saved polygon set "%s" with %d points for zone %s', setName, #pointsCopy, zone)
    return true
end

---Load a polygon set by name
---@param setName string @Name of the polygon set to load
function pull.loadPolygonSet(setName)
    local set = config.getPolygonSet(setName)
    if not set then
        logger.info('Polygon set "%s" not found', setName)
        return false
    end
    
    -- Clear current points
    polygonPoints = {}
    
    -- Load points from set
    for i, point in ipairs(set.points) do
        polygonPoints[i] = {point[1], point[2]}
    end
    
    -- Recalculate center and radius
    local centerAndRadius = calculatePolygonCenterAndRadius(polygonPoints)
    if centerAndRadius then
        polygonCenter = centerAndRadius
        polygonRadius = centerAndRadius.radius
    else
        polygonCenter = nil
        polygonRadius = nil
    end
    
    -- Update current polygon points in class
    if class then
        class.polygonPoints = {}
        for i, point in ipairs(polygonPoints) do
            class.polygonPoints[i] = {point[1], point[2]}
        end
        class:saveSettings()
    end
    
    -- Redraw markers
    mq.cmd('/squelch /maploc remove')
    pull.drawAllPolygonMarkers()
    pull.redrawCampMarkers()
    
    logger.info('Loaded polygon set "%s" with %d points', setName, #polygonPoints)
    return true
end

---Get polygon sets for current zone
---@return table @Array of polygon sets for current zone
function pull.getPolygonSetsForZone()
    local zone = mq.TLO.Zone.ShortName()
    local zoneSets = {}
    local allSets = config.getPolygonSets()
    
    for setName, set in pairs(allSets) do
        if set.zone == zone then
            table.insert(zoneSets, {
                name = setName,
                note = set.note,
                count = set.count,
                timestamp = set.timestamp,
                zone = set.zone
            })
        end
    end
    
    -- Sort by timestamp (newest first)
    table.sort(zoneSets, function(a, b) return a.timestamp > b.timestamp end)
    
    return zoneSets
end

---Get all polygon sets
---@return table @All polygon sets
function pull.getAllPolygonSets()
    local sets = {}
    local allSets = config.getPolygonSets()
    
    for setName, set in pairs(allSets) do
        table.insert(sets, {
            name = setName,
            note = set.note,
            count = set.count,
            timestamp = set.timestamp,
            zone = set.zone
        })
    end
    
    -- Sort by zone, then timestamp
    table.sort(sets, function(a, b) 
        if a.zone == b.zone then
            return a.timestamp > b.timestamp
        end
        return a.zone < b.zone
    end)
    
    return sets
end

---Delete a polygon set
---@param setName string @Name of the polygon set to delete
function pull.deletePolygonSet(setName)
    if config.removePolygonSet(setName) then
        logger.info('Deleted polygon set "%s"', setName)
        return true
    else
        logger.info('Polygon set "%s" not found', setName)
        return false
    end
end

---Draw map markers for all polygon points
function pull.drawAllPolygonMarkers()
    if #polygonPoints == 0 then return end
    
    local z = mq.TLO.Me.Z()
    for i, point in ipairs(polygonPoints) do
        local label = 'polygon_' .. i
        mq.cmdf('/squelch /maploc size 10 width 2 radius 5 color 255 128 0 rcolor 255 51 255 %s %s %s label %s', 
            point[2], point[1], z, label)
    end
end

---Redraw camp markers if camp is active
function pull.redrawCampMarkers()
    if not camp.Active then return end
    
    -- Redraw camp radius marker
    mq.cmdf('/squelch /maploc size 10 width 1 color 255 0 0 radius %s rcolor 255 0 0 %s %s %s',
        config.get('CAMPRADIUS'), camp.Y + 1, camp.X + 1, camp.Z)
end

---Validate that the spawn is good for pulling
---@param pull_spawn MQSpawn @The MQ Spawn to validate.
---@param path_len number @The navigation path length to the spawn.
---@param zone_sn string @The current zone short name.
---@return boolean @Returns true if the spawn meets all the criteria for pulling, otherwise false.
local function validatePull(pull_spawn, path_len, zone_sn)
    local mob_id = pull_spawn.ID()
    if path_len < 0 then return false end
    if not mob_id or mob_id == 0 or PULL_TARGET_SKIP[mob_id] or pull_spawn.Type() == 'Corpse' or pull_spawn.Surname() ~= '' then
        logger.debug(logger.flags.routines.pull, 'Invalid mob ID %s (type=%s, skip=%s)', mob_id, pull_spawn.Type(),
            PULL_TARGET_SKIP[mob_id])
        return false
    end
    if config.get('POLYGONPULL_ENABLED') then
        -- If no polygon points defined, fall back to regular radius + arc pulling
        local usePolygon = #polygonPoints >= 3
        if usePolygon then
            return checkZRadius(pull_spawn) and checkMobLevel(pull_spawn) and
                not config.ignoresContains(zone_sn, pull_spawn.CleanName()) and
                isPointInPolygon(mq.TLO.Spawn(mob_id).X(), mq.TLO.Spawn(mob_id).Y(), polygonPoints)
        else
            logger.debug(logger.flags.routines.pull, 'not enough polygon points to determine area')
            return false
        end
    else
        return checkMobAngle(pull_spawn) and checkZRadius(pull_spawn) and checkMobLevel(pull_spawn) and
            not config.ignoresContains(zone_sn, pull_spawn.CleanName())
    end
end

-- Helper Function: Extract the owner's name from the corpse
local function getCorpseOwner(corpse)
    local owner = corpse.Owner() or ""
    if owner == "" then
        local name = corpse.Name() or ""
        owner = name:match("^(.-)'s corpse")
    end
    return owner or "Unknown"
end




--local medding = false
local healers = { CLR = true, DRU = true, SHM = true }
local holdPullTimer = timer:new(5000)
local holdPulls = false
function pull.checkPullConditions()
    if config.get('WAITFORCORPSES') and mq.TLO.SpawnCount('pccorpse radius ' .. config.get('CAMPRADIUS') .. ' zradius 40')() > 0 then
        logger.debug(logger.flags.routines.pull, ('checking corpses!'))
        local pcCorpses = mq.getFilteredSpawns(function(spawn)
            if spawn.Type() == "Corpse" and spawn.Distance() <= config.get('CAMPRADIUS') then
                local owner = getCorpseOwner(spawn)
                if owner ~= "Unknown" and (mq.TLO.Group.Member(owner)() or mq.TLO.Raid.Member(owner)()) or mq.TLO.DanNet(owner)() then
                    logger.debug(logger.flags.routines.pull, ('Associated PC Corpse found: '):format(owner))
                    return true
                end
            end
            return false
        end)
        if pcCorpses and #pcCorpses > 0 then
            if not holdPulls then
                holdPullTimer:reset()
                holdPulls = true
            end
            return false
        end
    end

    if config.get('GROUPSTAYCLOSE') and mq.TLO.Group.Members() then
        for i = 1, mq.TLO.Group.Members() do
            local member = mq.TLO.Group.Member(i)
            if member() then
                if (member.Distance3D() or 300) > 150 then
                    -- group member not nearby, hold pulls until they catch up
                    if not holdPulls then
                        holdPullTimer:reset()
                        holdPulls = true
                    end
                    return false
                end
            end
        end
    end
    if config.get('GROUPWATCHWHO') == 'none' then return true end
    -- groupwatch self when self or healer is selected
    if config.get('GROUPWATCHWHO') ~= 'none' then
        if mq.TLO.Me.PctHPs() < config.get('MEDHPSTART') or mq.TLO.Me.PctEndurance() < config.get('MEDENDSTART') or (mq.TLO.Me.MaxMana() > 0 and mq.TLO.Me.PctMana() < config.get('MEDMANASTART')) and not state.medding then
            state.medding = true
            if not mq.TLO.Me.Sitting() and state.sitTimer:expired() then
                mq.cmd('/sit')
                state.sitTimer:reset()
            end
            return false
        end
        if (mq.TLO.Me.PctHPs() < config.get('MEDHPSTOP') or mq.TLO.Me.PctEndurance() < config.get('MEDENDSTOP') or (mq.TLO.Me.MaxMana() > 0 and mq.TLO.Me.PctMana() < config.get('MEDMANASTOP'))) and state.medding then
            if not mq.TLO.Me.Sitting() and state.sitTimer:expired() then
                mq.cmd('/sit')
                state.sitTimer:reset()
            end
            return false
        end
    end
    if mq.TLO.Group.Members() then
        for i = 1, mq.TLO.Group.Members() do
            local member = mq.TLO.Group.Member(i)
            if member() then
                if config.get('GROUPSTAYCLOSE') and (member.Distance3D() or 300) > 150 then
                    -- group member not nearby, hold pulls until they catch up
                    if not holdPulls then
                        holdPullTimer:reset()
                        holdPulls = true
                    end
                    return false
                end
                local pcthp = member.PctHPs()
                local pctmana = member.PctMana()
                if member.Dead() then
                    return false
                elseif healers[member.Class.ShortName()] and config.get('GROUPWATCHWHO') == 'healer' and pctmana then
                    if pcthp < config.get('MEDHPSTOP') and state.groupWatchWaiting then
                        if mq.TLO.Target.ID ~= member.ID() then
                            member.DoTarget() -- yay for reliable hp/mana updates on emu :-/
                        end
                        return false
                    end
                    if pctmana < config.get('MEDMANASTOP') and state.groupWatchWaiting then
                        if mq.TLO.Target.ID ~= member.ID() then
                            member.DoTarget()
                        end
                        return false
                    end
                    if pctmana < config.get('MEDMANASTART') then
                        if mq.TLO.Target.ID ~= member.ID() then
                            member.DoTarget()
                        end
                        state.groupWatchWaiting = true
                        return false
                    elseif pcthp < config.get('MEDHPSTART') then
                        if mq.TLO.Target.ID ~= member.ID() then
                            member.DoTarget()
                        end
                        state.groupWatchWaiting = true
                        return false
                    end
                end
            end
        end
    end
    state.groupWatchWaiting = false
    return true
end

local pullRadarTimer = timer:new(1000)
--[[ function pull.pullRadarB()
    if not pullRadarTimer:expired() then return 0 end
    pullRadarTimer:reset()
    local pull_radius = config.get('PULLRADIUS')
    if not pull_radius then return 0 end
    local shortest_path = pull_radius
    local pull_id = 0

    local function pullPredicate(spawn)
        if spawn.Type() ~= 'NPC' then return false end
        if spawn.Distance3D() > pull_radius then return false end
        local path_len = mq.TLO.Navigation.PathLength(string.format('id %s', spawn.ID()))()
        if not validatePull(spawn, path_len, mq.TLO.Zone.ShortName()) then return false end
        if path_len < shortest_path then
            shortest_path = path_len
            pull_id = spawn.ID()
        end
        return true
    end

    mq.getFilteredSpawns(pullPredicate)
    state.pullMobID = pull_id
    return pull_id
end ]]


local function getPullRange()
    local melee_range = 100
    local pullWith = config.get('PULLWITH')
    local pull_item = nil
    if pullWith == 'spell' then
        if not class.pullSpell then
            return melee_range
        else
            return class.pullSpell.MyRange()
        end
    elseif pullWith == 'item' then
        if #class.pullClickies == 0 then return melee_range end
        for _, clicky in ipairs(class.pullClickies) do
            local reagentCount = mq.TLO.FindItem(clicky.CastName).Clicky.Spell.ReagentCount(1)()
            local reagentID = mq.TLO.FindItem(clicky.CastName).Clicky.Spell.ReagentID(1)()
            if clicky.enabled and mq.TLO.Me.ItemReady(clicky.CastName)() and
                (reagentCount == -1 or mq.TLO.FindItemCount(reagentID)() > 0) then
                pull_item = true
                return mq.TLO.FindItem(clicky.CastName).Clicky.Spell.Range()
            end
            break
        end
        if not pull_item then return melee_range end
    elseif pullWith == 'ranged' then
        local ranged_item = mq.TLO.InvSlot('ranged').Item
        local ammo_item = mq.TLO.InvSlot('ammo').Item
        if not ranged_item() or (ranged_item.Damage() or 0) == 0 or not ammo_item() or (ammo_item.Damage() or 0) == 0 then
            return melee_range
        else
            return ranged_item.Range() + ammo_item.Range()
        end
    elseif pullWith == 'custom' then
        if not class.pullCustom then
            return melee_range
        else
            return class.pullCustom.Range()
        end
    end
    return melee_range
end


--loc ${s_WorkSpawn.X} ${s_WorkSpawn.Y}
local pull_count = 'npc targetable nopet radius %d'                    -- zradius 50'
local pull_spawn = '%d, npc targetable nopet radius %d'                -- zradius 50'
local pull_count_camp = 'npc targetable nopet loc %d %d radius %d'     -- zradius 50'
local pull_spawn_camp = '%d, npc targetable nopet loc %d %d radius %d' -- zradius 50'
local pc_near = 'pc radius 30 loc %d %d'
---Search for pullable mobs within the configured pull radius.
---Sets common.pullMobID to the mob ID of the first matching spawn.

function pull.pullRadar()
    if not pullRadarTimer:expired() then
        logger.debug(logger.flags.routines.pull,
            ('pullRadarTimer not expired! Remaining: %s'):format(pullRadarTimer:remaining()))
        return 0
    end
    pullRadarTimer:reset()
    state.pullMobID = nil
    local pull_radius_count
    local pull_radius = config.get('PULLRADIUS')
    local pull_level_priority = config.get('PULLLEVELPRIORITY')
    -- local max_radius = math.max(pull_radius, math.max(config.get('PULLHIGH'), config.get('PULLLOW')))
    local search_x, search_y
    
    if not pull_radius then return 0 end
    
    -- Use polygon center and radius if polygon mode is enabled and polygon is defined
    if config.get('POLYGONPULL_ENABLED') and polygonCenter and polygonRadius then
        search_x = polygonCenter.x
        search_y = polygonCenter.y
        pull_radius_count = mq.TLO.SpawnCount(pull_count_camp:format(search_x, search_y, polygonRadius))()
        logger.debug(logger.flags.routines.pull,
            ('%s: %s (polygon mode)'):format(pull_radius_count or 0, pull_count_camp:format(search_x, search_y, polygonRadius)))
    elseif camp.Active then --puller tank
        search_x = camp.X
        search_y = camp.Y
        pull_radius_count = mq.TLO.SpawnCount(pull_count_camp:format(search_x, search_y, pull_radius))()
        logger.debug(logger.flags.routines.pull,
            ('%s: %s'):format(pull_radius_count or 0, pull_count_camp:format(search_x, search_y, pull_radius)))
    else -- hnunter tank
        pull_radius_count = mq.TLO.SpawnCount(pull_count:format(pull_radius))()
        -- error here
        logger.debug(logger.flags.routines.pull, ('%s: %s'):format(pull_radius_count or 0, pull_count:format(pull_radius)))
    end
    local shortest_path = config.get('PULLPATH')
    local pull_id = 0
    local pull_level_priority_max = 0
    if pull_radius_count > 0 then
        local pullRange = getPullRange()
        local zone_sn = mq.TLO.Zone.ShortName()
        for i = 1, pull_radius_count do
            -- try not to iterate through the whole world if there's a pretty large pull radius
            if i > config.get('MOBSEVAL') then
                logger.debug(logger.flags.routines.pull, ('too many mobs %s > MobsEval!'):format(pull_radius_count))
                break
            end
            local mob
            if config.get('POLYGONPULL_ENABLED') and polygonCenter and polygonRadius then
                -- Use polygon center for search
                mob = mq.TLO.NearestSpawn(pull_spawn_camp:format(i, search_x, search_y, polygonRadius))
            elseif camp.Active then
                mob = mq.TLO.NearestSpawn(pull_spawn_camp:format(i, search_x, search_y, pull_radius))
            else
                mob = mq.TLO.NearestSpawn(pull_spawn:format(i, pull_radius))
            end
            if validatePull(mob, 0, zone_sn) then
                local path_len = checkPathLength(mob)
                local dist3d = mob.Distance3D()
                if (mob.LineOfSight() and dist3d < (pullRange - 30)) or (dist3d and path_len < dist3d + 50 and path_len > -1) then
                    -- don't bother to check path length if mob already in los and pullrange, never mind of a path exists.
                    -- if path length is within 50 of distance3d then its probably safe to pull also
                    state.pullMobID = mob.ID()
                    logger.debug(logger.flags.routines.pull, ('fetching nearby mob: %s'):format(mob.ID()))
                    return mob.ID()
                elseif path_len > -1 then
                    logger.debug(logger.flags.routines.pull, ('fetching mob in pullpath range: %s %s'):format(mob.ID(), path_len))
                    -- local path_len = mq.TLO.Navigation.PathLength(string.format('id %s', mob.ID()))()
                    -- if  then
                    -- TODO: check for people nearby, check level, check z radius if high/low differ
                    --local pc_near_count = mq.TLO.SpawnCount(pc_near:format(mob.X(), mob.Y()))
                    --if pc_near_count == 0 then

                    if not pull_level_priority and path_len < shortest_path then
                        logger.debug(logger.flags.routines.pull,
                            ("Found closer pull, %s < %s"):format(path_len, shortest_path))
                        shortest_path = path_len
                        pull_id = mob.ID()
                    elseif pull_level_priority and mob.Level() > pull_level_priority_max then
                        logger.debug(logger.flags.routines.pull,
                            ("Found higher level pull, %s < %s"):format(pull_level_priority_max, mob.Level()))
                        pull_level_priority_max = mob.Level()
                        shortest_path = path_len
                        pull_id = mob.ID()
                    elseif pull_level_priority and mob.Level() == pull_level_priority_max and path_len < shortest_path then
                        logger.debug(logger.flags.routines.pull,
                            ("Found closer pull (L %s), %s < %s"):format(pull_level_priority_max, path_len, shortest_path))
                        shortest_path = path_len
                        pull_level_priority_max = mob.Level()
                        pull_id = mob.ID()
                    end
                end
            end
        end
    end
    if pull_id ~= 0 then
        state.pullMobID = pull_id
    end
    return pull_id
end




---Reset common mob ID variables to 0 to reset pull status.
function pull.clearPullVars(caller)
    logger.debug(logger.flags.routines.pull, 'Resetting pull status. beforeState=%s, caller=%s', state.pullStatus, caller)
    state.pullMobID = 0
    state.pullStatus = nil
end

---Navigate to the pull spawn. Stop when it is within bow distance and line of sight, or when within melee distance.
---@param pull_spawn MQSpawn @The MQ Spawn to navigate to.
---@return boolean @Returns false if the pull spawn became invalid during navigation, otherwise true.
local function pullNavToMob(pull_spawn, announce_pull)
    local mob_x = pull_spawn.X()
    local mob_y = pull_spawn.Y()
    local pullRange = getPullRange()

    if not (mob_x and mob_y) then
        pull.clearPullVars('navToMob')
        return false
    end
    if announce_pull then
        logger.info('Pulling \at%s\ax (\at%s\ax)', pull_spawn.CleanName(), pull_spawn.ID())
    end
    -- TODO: find proper pullability range and check for that - safety margin
    if ((helpers.distance(mq.TLO.Me.X(), mq.TLO.Me.Y(), mob_x, mob_y) > 100) and config.get('PULLWITH') == 'melee') or (config.get('PULLWITH') ~= 'melee' and (not pull_spawn.LineOfSight() or pull_spawn.Distance3D() > (pullRange - 30))) then
        logger.debug(logger.flags.routines.pull, 'Moving to pull target (\at%s\ax)', state.pullMobID)
        -- TODO: set timeout as parameter - handling for some areas where xtarget aggro detection seemed not to work
        --movement.navToSpawn('id ' .. state.pullMobID, 'dist=5', 1000)
        movement.navToSpawn('id ' .. state.pullMobID, 'dist=5')
    end
    return true
end

local function pullApproaching(pull_spawn)
    local pullRange = getPullRange()
    if not pull_spawn or not mq.TLO.Navigation.Active() then
        return true
    end
    local dist3d = pull_spawn.Distance3D()
    -- return right away if we can't read distance, as pull spawn is probably no longer valid
    if not dist3d then return true end
    -- return true once target is in range and in LOS, or if something appears on xtarget
    -- TODO: set distance as parameter

    return (config.get('PULLWITH') ~= 'melee' and pull_spawn.LineOfSight() and dist3d < (pullRange - 30)) or dist3d < 5 or
        common.hostileXTargets()
end

---Aggro the specified target to be pulled. Attempts to use bow and moves closer to melee pull if necessary.
---@param pull_spawn MQSpawn @The MQ Spawn to be pulled.
local function pullEngage(pull_spawn)
    -- pull  mob
    local pullRange = getPullRange()
    local pullMobID = state.pullMobID
    local dist3d = pull_spawn.Distance3D()

    if not dist3d then
        logger.info('\arPull target no longer valid \ax(\at%s\ax)', pullMobID)
        pull.clearPullVars('pullEngage-distanceCheck')
        return false
    end
    if not pull_spawn.LineOfSight() or dist3d > (pullRange - 30) then
        state.pullStatus = constants.pullStates.APPROACHING
        --logger.info('\arPull state \ax(\at%s\ax)', state.pullStatus)
        pullNavToMob(pull_spawn, false)
        return false
    end
    pull_spawn.DoTarget()
    if not mq.TLO.Target() then
        logger.info('\arPull target no longer valid \ax(\at%s\ax)', pullMobID)
        pull.clearPullVars('pullEngage-targetCheck')
        return false
    end
    local tot_id = mq.TLO.Me.TargetOfTarget.ID()
    local targethp = mq.TLO.Target.PctHPs()
    --if (tot_id > 0 and tot_id ~= mq.TLO.Me.ID()) or (targethp and targethp < 100) then --or mq.TLO.Target.PctHPs() < 100 then
    if tot_id > 0 and tot_id ~= mq.TLO.Me.ID() and tot_id ~= mq.TLO.Pet.ID() then
        if targethp and targethp < 99 then
            logger.info('\arPull target already engaged, skipping \ax(\at%s\ax) %s %s %s', pullMobID, tot_id,
                mq.TLO.Me.ID(), targethp)
            -- TODO: clear skip targets
            PULL_TARGET_SKIP[pullMobID] = 1
            pull.clearPullVars('pullEngage-hpCheck')
            return false
        end
    end
    if mq.TLO.Target.Distance3D() < 35 then
        --movement.stop()
        if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop') end
        mq.cmd('/squelch /face fast')
        mq.cmd('/squelch /stand')
        mq.cmd('/squelch /stick front loose moveback 10')
        common.dismountForCombat()
        mq.cmd('/attack on')
        state.pullStatus = constants.pullStates.WAIT_FOR_AGGRO
    else
        if mq.TLO.Me.Combat() then
            mq.cmd('/attack off')
            -- mq.delay(100)
        end
        local pullWith = config.get('PULLWITH')
        local pull_item = nil
        if pullWith == 'spell' and not class.pullSpell then
            pullWith = 'melee'
        elseif pullWith == 'item' then
            if #class.pullClickies == 0 then pullWith = 'melee' end
            for _, clicky in ipairs(class.pullClickies) do
                local reagentCount = mq.TLO.FindItem(clicky.CastName).Clicky.Spell.ReagentCount(1)()
                local reagentID = mq.TLO.FindItem(clicky.CastName).Clicky.Spell.ReagentID(1)()
                if clicky.enabled and mq.TLO.Me.ItemReady(clicky.CastName)() and
                    (reagentCount == -1 or mq.TLO.FindItemCount(reagentID)() > 0) then
                    pull_item = clicky
                    pull_range = mq.TLO.FindItem(clicky.CastName).Clicky.Spell.Range()
                    break
                end
            end
            if not pull_item then pullWith = 'melee' end
        elseif pullWith == 'ranged' then
            local ranged_item = mq.TLO.InvSlot('ranged').Item
            local ammo_item = mq.TLO.InvSlot('ammo').Item
            if not ranged_item() or (ranged_item.Damage() or 0) == 0 or not ammo_item() or (ammo_item.Damage() or 0) == 0 then
                pullWith = 'melee'
            end
        elseif pullWith == 'custom' and not class.pullCustom then
            pullWith = 'melee'
        end
        if pullWith == 'item' and pull_item then
            movement.stop()
            -- mq.delay(50)
            abilities.use(pull_item, class)
            state.pullStatus = constants.pullStates.WAIT_FOR_AGGRO
        elseif pullWith == 'ranged' then
            mq.cmd('/squelch /face fast')
            mq.cmd('/squelch /stand')
            mq.cmd('/autofire on')
            -- mq.delay(1000)
            if not mq.TLO.Me.AutoFire() then
                mq.cmd('/autofire on')
            end
            if mode.currentMode:isReturnToCampMode() then
                movement.stop()
                mq.delay(1000,
                    function()
                        return mq.TLO.Me.TargetOfTarget.ID() == mq.TLO.Me.ID() or
                            mq.TLO.Me.CombatState() == 'COMBAT'
                    end)
            end
            state.pullStatus = constants.pullStates.WAIT_FOR_AGGRO
        elseif pullWith == 'spell' then
            if mq.TLO.Me.SpellReady(class.pullSpell.CastName)() then
                movement.stop()
                -- mq.delay(50)
                -- abilities.use(class.pullSpell, class)
                class.pullSpell:execute()
                state.pullStatus = constants.pullStates.WAIT_FOR_AGGRO
            end
        elseif pullWith == 'custom' and class.pullCustom then
            class:pullCustom()
        elseif pullWith == 'melee' then
            state.pullStatus = constants.pullStates.APPROACHING
            pullNavToMob(pull_spawn, false)
            return false
        end
    end
    return true
end

local pullReturnTimer = timer:new(120000)
---Return to camp and wait for the pull target to arrive in camp. Stops early if adds appear on xtarget.
local function pullReturn(noMobs)
    --logger.info('Bringing pull target back to camp (%s)', common.pullMobID)
    if noMobs and not pullReturnTimer:expired() then return end
    if helpers.distance(mq.TLO.Me.X(), mq.TLO.Me.Y(), camp.X, camp.Y) < 225 then return end
    movement.navToLoc(camp.X, camp.Y, camp.Z)
    if noMobs then pullReturnTimer:reset() end
end

local function pullMobOnXTarget()
    for i = 1, 20 do
        if mq.TLO.Me.XTarget(i).ID() == state.pullMobID then return true end
    end
    return false
end

local function anyoneDead()
    local groupSize = mq.TLO.Group.GroupSize()
    if not groupSize then return false end
    for i = 1, groupSize - 1 do
        if mq.TLO.Group.Member(i).Dead() then return true end
    end
    return false
end

local pullEngageTimer = timer:new(3000)
local old_pull_state = nil
---Attempt to pull the mob whose ID is stored in common.pullMobID.
---Sets common.tankMobID to the mob being pulled.
function pull.pullMob()
    local pull_state = state.pullStatus
    if pull_state ~= old_pull_state then
        logger.debug(logger.flags.routines.pull, '\arPull state \ax(\at%s\ax) was: %s', pull_state, old_pull_state)
        old_pull_state = pull_state
    end

    -- or (mq.TLO.Group.Injured(config.get('MEDHPSTART'))() or 0) > 0
    if anyoneDead() or mq.TLO.Me.PctHPs() < config.get('MEDHPSTART') or constants.DMZ[mq.TLO.Zone.ID()] then -- or (state.holdForBuffs and not state.holdForBuffs:expired()) then
        if pull_state == constants.pullStates.APPROACHING or pull_state == constants.pullStates.ENGAGING then
            pull.clearPullVars('pullMob-deadOrInjured')
            movement.stop()
            return
        elseif not pull_state then
            -- let this fall through to pull validation which already checks groupwatch stuff
            --return
        end
    end
    -- if currently assisting or tanking something, or stuff is on xtarget, then don't start new pulling things
    if not pull_state and (state.assistMobID ~= 0 or state.tankMobID ~= 0 or common.hostileXTargets()) then
        --logger.debug(logger.flags.routines.pull, 'returning at weird state')
        return
    end

    -- account for any odd pull state discrepancies?
    if (pull_state and state.pullMobID == 0) or (state.pullMobID ~= 0 and not pull_state) then
        pull.clearPullVars('pullMob-consistencyCheck')
        pullReturn()
        return
    end

    -- try to break if something agro'd that isn't the pull mob? thought this was already happening somewhere...
    if pull_state and common.hostileXTargets() and not pullMobOnXTarget() then
        pull.clearPullVars('pullMob-onXTargetCheck')
        if mode.currentMode:isReturnToCampMode() and camp.Active then
            logger.debug(logger.flags.routines.pull, 'Xtar aggro? - returning to camp')
            state.pullStatus = constants.pullStates.RETURNING
            movement.stop()
            pullReturn(false)
        else
            pullReturnTimer:reset()
            state.pullStatus = constants.pullStates.PULLED
        end
        return
    end
    if not pull_state then
        logger.debug(logger.flags.routines.pull, 'a pull search can start')
        -- don't start a new pull if tanking or assisting or hostiles on xtarget or conditions aren't met
        if state.assistMobID ~= 0 or state.tankMobID ~= 0 or common.hostileXTargets() then return end
        if not pull.checkPullConditions() then
            if holdPulls and holdPullTimer:expired() then
                local furthest = 0
                local furthestID = 0
                for i = 1, mq.TLO.Group.Members() do
                    local member = mq.TLO.Group.Member(i)
                    if member() and (member.Distance3D() or 0) > furthest then
                        furthest = member.Distance3D()
                        furthestID = member.ID()
                    end
                end
                if furthestID > 0 then movement.navToID(furthestID, 'dist=10') end
            end
            return
        elseif holdPulls then
            holdPulls = false
        end
        -- find a mob to pull
        logger.debug(logger.flags.routines.pull, 'searching for pulls')
        local pullMobID = pull.pullRadar()
        local pull_spawn = mq.TLO.Spawn(pullMobID)
        logger.debug(logger.flags.routines.pull, ('pull radar returned id %s'):format(pullMobID))
        if pull_spawn.ID() == 0 then
            -- didn't seem to find the mob returned by pullRadar
            pull.clearPullVars('pullMob-mobMissingCheck')
            pullReturn(true)
            return
        end
        if pull_spawn.Type() ~= 'NPC' then
            pull.clearPullVars('pullMob-nonNPC')
            return
        end
        -- valid pull spawn acquired, begin approach
        state.pullStatus = constants.pullStates.APPROACHING
        pullNavToMob(pull_spawn, true)
    elseif pull_state == constants.pullStates.APPROACHING then
        local pull_spawn = mq.TLO.Spawn(state.pullMobID)
        if pull_spawn.Type() ~= 'NPC' then
            pull.clearPullVars('pullMob-nonNPC')
            return
        end
        if pullApproaching(pull_spawn) then
            -- movement stopped, either spawn became invalid, we're in range, or other stuff agro'd
            state.pullStatus = constants.pullStates.ENGAGING
            movement.stop()
            return --ams test
        end
    elseif pull_state == constants.pullStates.ENGAGING then
        local pull_spawn = mq.TLO.Spawn(state.pullMobID)
        if pull_spawn.Type() ~= 'NPC' then
            pull.clearPullVars('pullMob-nonNPC')
            return
        end
        pullEngage(pull_spawn)
        pullEngageTimer:reset()
    elseif pull_state == constants.pullStates.WAIT_FOR_AGGRO then
        if (mq.TLO.Me.TargetOfTarget.ID() == mq.TLO.Me.ID() and common.hostileXTargets()) or not mq.TLO.Target() then
            if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
            if mq.TLO.Me.AutoFire() then mq.cmd('/autofire off') end
            if mq.TLO.Stick.Active() then mq.cmd('/stick off') end
            -- successfully agro'd the mob, or something else agro'd in the process
            pullEngageTimer:reset()
            if mode.currentMode:isReturnToCampMode() and camp.Active then
                logger.debug(logger.flags.routines.pull, 'got aggro, pull or xtarget, or target gone?')
                state.pullStatus = constants.pullStates.RETURNING
                movement.stop()
                pullReturn(false)
            else
                pullReturnTimer:reset()
                state.pullStatus = constants.pullStates.PULLED
            end
        elseif pullEngageTimer:expired() then
            pullEngageTimer:reset()
            pullReturnTimer:reset()
            pull.clearPullVars('pullMob-aggroTimerExpired')
        end
    elseif pull_state == constants.pullStates.RETURNING then
        if helpers.distance(camp.X, camp.Y, mq.TLO.Me.X(), mq.TLO.Me.Y()) < config.get('CAMPRADIUS') ^ 2 then
            state.pullStatus = constants.pullStates.PULLED
        else
            pullReturn(false)
        end
    end
end

return pull
