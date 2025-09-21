local mq = require('mq')
require 'ImGui'
local CONSOLE = ImGui.ConsoleWidget.new("##AQOConsole")
CONSOLE.maxBufferLines = 1000

local logger = require('utils.logger')
logger.setConsole(CONSOLE)

local commands = require('interface.commands')
local config = require('interface.configuration')
local ui = require('interface.ui')
local tlo = require('interface.tlo')

local movement = require('utils.movement')
local timer = require('libaqo.timer')

local common = require('common')
local constants = require('constants')
local mode = require('mode')
local state = require('state')
local status = require('status')

ui.setConsole(CONSOLE)

local class = require('classes.' .. mq.TLO.Me.Class.ShortName():lower())

-- Store class instance in state for access by common.lua
state.classInstance = class

local aqo = {}

local routines = { 'assist', 'buff', 'camp', 'conditions', 'cure', 'debuff', 'events', 'heal', 'mez', 'pull', 'tank' }
for _, routine in ipairs(routines) do
    aqo[routine] = require('routines.' .. routine)
    aqo[routine].init(class)
end

local function init()
    class:init()
    aqo.events.initClassBasedEvents()
    commands.init(class)
    ui.init(class)
    tlo.init(class)
    status.init()

    state.currentZone = mq.TLO.Zone.ID()
    state.subscription = mq.TLO.Me.Subscription()
    config.loadIgnores()
    config.loadPolygonSets()

    if state.emu then
        mq.cmd('/hidecorpse looted')
    else
        mq.cmd('/hidecorpse alwaysnpc')
    end
    mq.cmd('/pet ghold on')
    mq.cmd('/squelch /stick set verbflags 0')
    -- mq.cmd('/squelch /stick set delaystrafe off')
    mq.cmd('/squelch /stick set delaystrafe on')
    mq.cmd('/squelch /stick set strafemindelay 500')
    mq.cmd('/squelch /stick set strafemaxdelay 1000')
    mq.cmd('/squelch /plugin melee unload noauto')
    mq.cmd('/squelch /rez accept on')
    mq.cmd('/squelch /rez pct 90')
    mq.cmd('/squelch /assist off')
    mq.cmd('/squelch /autofeed 5000')
    mq.cmd('/squelch /autodrink 5000')
    mq.cmdf('/setwintitle %s (Level %s %s)', mq.TLO.Me.CleanName(), mq.TLO.Me.Level(), state.class)
end

---Check if the current game state is not INGAME, and exit the script if it is.
---Otherwise, update state for the current loop so we don't have to go to the TLOs every time.
local function updateLoopState()
    local success, gameState = pcall(function() return mq.TLO.MacroQuest.GameState() end)
    if not success or gameState ~= 'INGAME' then
        logger.info('Not in game or TLO error, stopping aqo.')
        mq.exit()
    end
    state.actionTaken = false
end

---Reset assist/tank ID and turn off attack if we have no target or are targeting a corpse
---If targeting a corpse, also clear target unless its a healer
local clearTargetTimer = timer:new(5000)
local manastoneTimer = timer:new(500)
local function checkTarget()
    local success, target = pcall(function() return mq.TLO.Target end)
    if not success then return end
    
    local targetType = target.Type()
    local masterType = target.Master.Type()
    local isPC = targetType == 'PC' or (targetType == 'Pet' and masterType == 'PC')
    
    if not targetType or targetType == 'Corpse' then
        state.assistMobID = 0
        state.tankMobID = 0
        
        local me = mq.TLO.Me
        if me.Combat() then
            mq.cmd('/attack off')
        elseif me.AutoFire() then
            mq.cmd('/autofire off')
        end
        
        if mq.TLO.Stick.Active() then
            mq.cmd('/squelch /stick off')
        end
        
        if targetType == 'Corpse' then
            if clearTargetTimer.start_time == 0 then
                clearTargetTimer:reset()
            elseif clearTargetTimer:expired() then
                mq.cmd('/squelch /mqtarget clear')
                clearTargetTimer:reset(0)
            end
        elseif clearTargetTimer.start_time ~= 0 then
            clearTargetTimer:reset(0)
        end
    elseif isPC then
        state.assistMobID = 0
        state.tankMobID = 0
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
    end
end

local function resetClearTargets()
    if state.cleartargets and not mq.TLO.Spawn('npc radius 60').Aggressive() then
        state.cleartargets = false
        config.getOrSetOption('MODE', config.get('MODE'), state.previousmode, 'MODE')
        state.previousmode = nil
    end
end

local function checkFD()
    if mq.TLO.Me.Feigning() and (not constants.fdClasses[state.class] or not state.didFD) then
        mq.cmd('/stand')
    end
end

---Remove harmful buffs such as lich if HP is getting low, regardless of paused state
local torporLandedInCombat = false
local function buffSafetyCheck()
    local me = mq.TLO.Me
    local myHPs = me.PctHPs()
    local combatState = me.CombatState()
    
    if state.class == 'NEC' and myHPs < 40 then
        if class.spells.lich then
            mq.cmdf('/removebuff %s', class.spells.lich.Name)
            if class.spells.flesh then
                mq.cmdf('/removebuff %s', class.spells.flesh.Name)
            end
        end
        if not me.Feigning() and not me.Sitting() and combatState ~= 'COMBAT' then
            mq.cmd('/sit')
        end
    end
    
    local hasTorpor = me.Song('Transcendent Torpor')()
    if not torporLandedInCombat and hasTorpor and combatState == 'COMBAT' then
        torporLandedInCombat = true
    end
    if (torporLandedInCombat or mq.TLO.SpawnCount('xtarhater radius 25')() == 0) and combatState ~= 'COMBAT' and hasTorpor then
        mq.cmdf('/removebuff "Transcendent Torpor"')
        torporLandedInCombat = false
    end
    
    if state.class == 'MNK' and myHPs < config.get('HEALPCT') and me.AbilityReady('Mend')() then
        mq.cmd('/doability mend')
    end
    
    if not state.paused and state.mobCountNoPets > 0 and state.fadeTimer:expired() then 
        mq.cmd('/makemevis') 
    end
    
    local resurrectionSickness = me.Buff('Resurrection Sickness')()
    if resurrectionSickness and me.Aura(1)() then
        mq.cmdf('/removeaura %s', me.Aura(1)())
    end
end

local function handleStates(class)
    -- Async state handling
    if not state.handlePositioningState() then return true end
    if not state.handleMemSpell() then return true end
    if not state.handleCastingState(class) then return true end
    if not state.handleQueuedAction() then return true end
end

local function main()
    init()

    local debugTimer = timer:new(3000)
    local statusTimer = timer:new(1000)
    local delay = 500
    -- Main Loop
    while true do
        if state.restart then
            mq.cmd('/timed 5 /lua run aqo')
            return
        end
        
        local loopStart = mq.gettime()
        if state.debug and debugTimer:expired() then
            logger.debug(logger.flags.aqo.main, 'Start Main Loop')
            debugTimer:reset()
        end

        -- Wrap critical operations in error handling
        local success, err = pcall(function()
            mq.doevents()
            updateLoopState()
            state.handleZoneChange() -- Memory cleanup on zone changes
            buffSafetyCheck()
        end)
        
        if not success then
            logger.info('Error in main loop: %s', err or 'unknown error')
            mq.delay(1000) -- Delay before retry
            goto continue_loop
        end
        if not state.paused and common.inControl() then
            if not handleStates(class) then
                if state.reacquireTargetID then
                    mq.cmdf('/mqtar id %s', state.reacquireTargetID)
                    state.reacquireTargetID = nil
                end
                aqo.camp.cleanTargets()
                checkTarget()
                resetClearTargets()
                if not mq.TLO.Me.Invis() and not common.isBlockingWindowOpen() then
                    -- do active combat assist things when not paused and not invis
                    checkFD()
                    common.checkCursor()
                   --[[  if state.emu then
                        doLooting()
                    end ]]
                    if not state.actionTaken then
                        class:mainLoop()
                    end
                    delay = 16
                else
                    -- stay in camp or stay chasing chase target if not paused but invis
                    local pet_target_id = mq.TLO.Pet.Target.ID() or 0
                    if mq.TLO.Pet.ID() > 0 and pet_target_id > 0 then mq.cmd('/pet back') end
                    aqo.camp.mobRadar()
                    if (mode:isTankMode() and state.mobCount > 0) or (mode:isAssistMode() and aqo.assist.shouldAssist()) or mode:getName() == 'huntertank' then
                        mq.cmd('/makemevis') end
                    aqo.camp.checkCamp()
                    common.checkChase()
                    common.rest()
                    delay = 16
                end
            end
            if state.useManastone and state.manastoneCount < 10 and not state.actionTaken then
                local me = mq.TLO.Me
                if not me.Casting() and me.PctHPs() > 50 and me.PctMana() < 90 then
                    mq.cmd('/useitem Manastone')
                    manastoneTimer:reset()
                    state.manastoneCount = state.manastoneCount + 1
                    if state.manastoneCount >= 10 then
                        state.useManastone = false
                        state.manastoneCount = 0
                    end
                end
            end
        else
            if mq.TLO.Me.Invis() then
                -- if paused and invis, back pet off, otherwise let it keep doing its thing if we just paused mid-combat for something
                local pet_target_id = mq.TLO.Pet.Target.ID() or 0
                if mq.TLO.Pet.ID() > 0 and pet_target_id > 0 then mq.cmd('/pet back') end
            end
            if config.get('CHASEPAUSED') then
                common.checkChase()
            end
            delay = 500
        end
        if statusTimer:expired() then
            status.send(class)
            statusTimer:reset()
        end
        logger.debug(logger.flags.aqo.main, 'loop execution time: %s loop delay: %s', mq.gettime() - loopStart, delay)
        
        ::continue_loop::
        mq.delay(delay)
    end
end

main()
