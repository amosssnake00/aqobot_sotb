local mq     = require('mq')
local actor  = require('interface.actor')
local Timer  = require('libaqo.timer')
local mode   = require('mode')
local state  = require('state')

local status = {}

function status.init()
    actor.register('status', status.callback)
end

local function processTable(parent, tableName, tableValue)
    parent[tableName] = {}
    for key, value in pairs(tableValue) do
        if type('value') == 'table' then
            processTable(parent[tableName], key, value)
        else
            parent[tableName][key] = value
        end
    end
end

function status.callback(message)
    state.actors[message.content.Name] = state.actors[message.content.Name] or {}
    for key, value in pairs(message.content) do
        if key ~= 'Name' and key ~= 'id' then
            if type(value) == 'table' then
                processTable(state.actors[message.content.Name], key, value)
            else
                state.actors[message.content.Name][key] = value
            end
        end
    end
    if not message.content.Buffs then state.actors[message.content.Name].Buffs = nil end
    if not message.content.Songs then state.actors[message.content.Name].Songs = nil end
    if not message.content.wantBuffs then state.actors[message.content.Name].wantBuffs = nil end
    if not message.content.gimme then state.actors[message.content.Name].gimme = nil end
    for toon, toonState in pairs(state.actors) do
        if mq.gettime() - (toonState.LastSent or 0) > 30000 then
            state.actors[toon] = nil
        end
    end
end

local ignoredebuffs = { ['HC Jugular Gash'] = true, ['Resurrection Sickness'] = true, ['Revival Sickness'] = true,
    ['HC Roar of Challenge'] = true, ['Aura of Destruction'] = true, ['HC Knuckle Smash'] = true }
local statusTimer = Timer:new(1000)

-- Cache for buff/song data to avoid repeated processing
local cachedBuffs = {}
local cachedSongs = {}
local lastBuffCheck = 0
local lastSongCheck = 0

local function getDebuffs()
    local currentTime = mq.gettime()
    if currentTime - lastBuffCheck < 500 then  -- Cache for 500ms
        return cachedBuffs
    end
    
    local buffs = {}
    local me = mq.TLO.Me
    local buffCount = me.BuffsPopulated() and 42 or 0
    
    for i = 1, buffCount do
        local aBuff = me.Buff(i)
        if aBuff() then
            local spell = aBuff.Spell()
            if spell then
                local beneficial = spell.Beneficial and spell.Beneficial() or false
                if not beneficial then
                    local buffName = aBuff.Name()
                    if not ignoredebuffs[buffName] then
                        local buffData = { Name = buffName, Duration = aBuff.Duration.TotalSeconds() }
                        local counterNum = aBuff.CounterNumber()
                        if counterNum and counterNum > 0 then
                            buffData.CounterNumber = counterNum
                            buffData.CounterType = aBuff.CounterType()
                        end
                        table.insert(buffs, buffData)
                    end
                end
            end
        end
    end
    
    cachedBuffs = buffs
    lastBuffCheck = currentTime
    return buffs
end

local function getDebuffSongs()
    local currentTime = mq.gettime()
    if currentTime - lastSongCheck < 500 then  -- Cache for 500ms
        return cachedSongs
    end
    
    local songs = {}
    local me = mq.TLO.Me
    
    for i = 1, 20 do
        local aSong = me.Song(i)
        if aSong() then
            local spell = aSong.Spell()
            if spell then
                local beneficial = spell.Beneficial and spell.Beneficial() or false
                if not beneficial then
                    local songData = { Name = aSong.Name(), Duration = aSong.Duration.TotalSeconds() }
                    local counterNum = aSong.CounterNumber()
                    if counterNum and counterNum > 0 then
                        songData.CounterNumber = counterNum
                        songData.CounterType = aSong.CounterType()
                    end
                    table.insert(songs, songData)
                end
            end
        end
    end
    
    cachedSongs = songs
    lastSongCheck = currentTime
    return songs
end

function status.send(class)
    if not statusTimer:expired() then return end
    statusTimer:reset()
    local header = { script = 'aqo', server = mq.TLO.EverQuest.Server() }
    
    -- Get cached debuffs and songs
    local buffs = getDebuffs()
    local songs = getDebuffSongs()
    
    if state.testCures then
        table.insert(buffs, { Name = 'Poison Debuff', Duration = 60, CounterNumber = 10, CounterType = 'Poison' })
    end
    
    -- Send info on any missing or fading buffs
    local wantBuffs = class:wantBuffs()
    local availableBuffs = class:getRequestAliases()
    local gimme = {}
    local availableSupplies = {}
    local missingAggro = {}
    
    if mode.currentMode:isTankMode() then
        local me = mq.TLO.Me
        local xTargetSlots = me.XTargetSlots()
        for i = 1, xTargetSlots do
            local xTarget = me.XTarget(i)
            if xTarget and (xTarget.PctAggro() or 100) < 100 then
                table.insert(missingAggro, xTarget.ID())
            end
        end
    end

    local status = {
        id = 'status',
        Name = mq.TLO.Me.CleanName(),
        Class = mq.TLO.Me.Class.ShortName(),
        Buffs = buffs,
        Songs = songs,
        wantBuffs = wantBuffs,
        availableBuffs = availableBuffs,
        missingAggro = missingAggro,
        gimme = gimme,
        availableSupplies = availableSupplies,
        LastSent = mq.gettime(),
    }
    actor.actor:send(header, status)
end

return status
