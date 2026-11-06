Config = {}

Config.debug = false
Config.framework = 'auto'  -- 'auto', 'qbox', 'qbcore'

Config.atmModels = { 'prop_atm_03'}

-- Frame stays, body falls out
Config.atmPieces = {
    prop_atm_03 = { frame = 'meteo_prop_atm03_frame', body = 'meteo_prop_atm03_body' },
}
Config.weapon = 'WEAPON_CROWBAR'  -- must be in hand
Config.requiredCops = 0

-- Keymash, one ring segment per key
Config.minigame = {
    keys = { 'Q', 'SPACE', 'E', 'E' },  -- letters or 'SPACE'
    presses = 10,              -- taps per key
    drain = 3.5,               -- seconds to drain empty
    time = 6,                  -- seconds per key, 0 = no limit
    anim = { dict = 'missheistfbi3b_ig7', clip = 'lift_fibagent_loop' },
}

Config.reward = {
    type = 'cash',               -- 'cash' or 'item'
    item = 'meteo_foldedcash',   -- when type is 'item'
    total = { min = 1500, max = 3000 },  -- $ or item count, split over the notes
    notes = { min = 6, max = 9 },
}

Config.noteModel = 'h4_prop_h4_cash_stack_02a'
Config.currencySymbol = '$'
Config.pickupTime = 1200       -- ms per note

-- Flying cash
Config.cashBurst = {
    duration = 10,          -- seconds
    notesPerSecond = 20,
    model = 'prop_anim_cash_note',
}

Config.resetTime = 1800        -- seconds until the ATM is back
Config.playerCooldown = 600    -- seconds between robberies
Config.renderDistance = 60.0

Config.dispatch = {
    enabled = true,
    chance = 100,  -- % per attempt
    code = '10-90',
    priority = 'medium',
    jobs = { 'police' },
}
