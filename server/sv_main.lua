local atms = {}
local prying = {}
local cooldowns = {}
local lastPickup = {}
local nextId = 0

local PRY_TIMEOUT = 90000
local MIN_PRY_MS = 1000
local SAME_ATM = 1.0
local USE_RANGE = 3.0
local PICKUP_RANGE = 2.5

local function modelKey(hash)
    return hash % 0x100000000
end

local allowedModels = {}
for _, name in ipairs(Config.atmModels) do
    allowedModels[modelKey(joaat(name))] = true
end

local function atmCoords(atm)
    return vec3(atm.x, atm.y, atm.z)
end

local function pedNear(src, coords, range)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - coords) <= range
end

local function hasCrowbar(src)
    local weapon = exports.ox_inventory:GetCurrentWeapon(src)
    return weapon ~= nil and weapon.name:upper() == Config.weapon:upper()
end

local function findAtm(coords)
    for _, atm in pairs(atms) do
        if #(atmCoords(atm) - coords) < SAME_ATM then return atm end
    end
end

local function publish()
    local list = {}
    for _, atm in pairs(atms) do
        if atm.state == 'open' then
            local notes = {}
            for i, note in ipairs(atm.notes) do
                notes[i] = { x = note.x, y = note.y, taken = note.taken }
            end
            list[#list + 1] = { id = atm.id, model = atm.model, x = atm.x, y = atm.y, z = atm.z, h = atm.h, notes = notes }
        end
    end
    GlobalState[Atm.globalKey] = list
end

local function rollNotes()
    local count = math.random(Config.reward.notes.min, math.max(Config.reward.notes.min, Config.reward.notes.max))
    local total = math.random(Config.reward.total.min, math.max(Config.reward.total.min, Config.reward.total.max))

    count = math.max(1, math.min(count, total))
    local share = math.floor(total / count)

    local notes = {}
    for i = 1, count do
        local side = i % 2 == 0 and 1 or -1
        notes[i] = {
            x = side * (0.6 + math.random() * 0.8),
            y = -(0.5 + math.random() * 1.7),
            amount = i == count and total - share * (count - 1) or share,
            taken = false,
        }
    end
    return notes
end

local function isItemReward()
    return Config.reward.type == 'item'
end

local function itemLabel(name)
    local item = exports.ox_inventory:Items(name)
    return item and item.label or name
end

local function giveReward(src, amount)
    if not isItemReward() then
        return Bridge.AddMoney(src, 'cash', amount, 'atm-robbery')
    end
    if not exports.ox_inventory:CanCarryItem(src, Config.reward.item, amount) then
        return false, locale('cant_carry')
    end
    return exports.ox_inventory:AddItem(src, Config.reward.item, amount) and true or false, locale('cant_carry')
end

local function rewardText(amount)
    if isItemReward() then
        return locale('picked_up_item', amount, itemLabel(Config.reward.item))
    end
    return locale('picked_up', Config.currencySymbol, amount)
end

local function endPry(atm)
    if atms[atm.id] == atm and atm.state == 'prying' then
        atms[atm.id] = nil
        DebugPrint('Pry ended', atm.id)
    end
    if prying[atm.robber] == atm.id then prying[atm.robber] = nil end
end

local function releaseBySource(src)
    local id = prying[src]
    if not id then return end
    if atms[id] then
        endPry(atms[id])
    else
        prying[src] = nil
    end
end

lib.callback.register('meteo-atmrobbery:server:start', function(src, coords, model, heading)
    if type(coords) ~= 'vector3' or type(model) ~= 'number' or type(heading) ~= 'number' then return false end

    local cid = Bridge.GetCitizenId(src)
    if not cid or prying[src] then return false end
    if not allowedModels[modelKey(model)] or not pedNear(src, coords, USE_RANGE) then return false end
    if not hasCrowbar(src) then return false, locale('need_crowbar') end

    local now = os.time()
    if cooldowns[cid] and cooldowns[cid] > now then
        return false, locale('cooldown', math.ceil((cooldowns[cid] - now) / 60))
    end

    local existing = findAtm(coords)
    if existing then
        return false, locale(existing.state == 'open' and 'already_robbed' or 'atm_busy')
    end

    if Config.requiredCops > 0 and Bridge.GetCopCount() < Config.requiredCops then
        return false, locale('not_enough_police')
    end

    nextId = nextId + 1
    local atm = {
        id = nextId,
        state = 'prying',
        robber = src,
        model = model,
        x = coords.x, y = coords.y, z = coords.z,
        h = heading,
        startedAt = GetGameTimer(),
    }
    atms[atm.id] = atm
    prying[src] = atm.id

    SetTimeout(PRY_TIMEOUT, function() endPry(atm) end)

    if Config.dispatch.enabled and math.random(100) <= Config.dispatch.chance then
        CreateThread(function() Bridge.Dispatch(src, coords) end)
    end

    DebugPrint('Pry started', atm.id, 'by', src)
    return true, atm.id
end)

lib.callback.register('meteo-atmrobbery:server:finish', function(src, id, success)
    local atm = atms[id]
    if not atm or atm.state ~= 'prying' or atm.robber ~= src then return false end

    if success ~= true
        or GetGameTimer() - atm.startedAt < MIN_PRY_MS
        or not pedNear(src, atmCoords(atm), USE_RANGE + 1.0) then
        endPry(atm)
        return false
    end

    prying[src] = nil
    atm.state = 'open'
    atm.robber = nil
    atm.notes = rollNotes()

    local cid = Bridge.GetCitizenId(src)
    if cid then cooldowns[cid] = os.time() + Config.playerCooldown end

    publish()

    SetTimeout(Config.resetTime * 1000, function()
        if atms[atm.id] ~= atm then return end
        atms[atm.id] = nil
        publish()
        DebugPrint('ATM reset', atm.id)
    end)

    DebugPrint('ATM opened', atm.id, 'by', src)
    return true
end)

lib.callback.register('meteo-atmrobbery:server:pickup', function(src, id, index)
    local atm = atms[id]
    local note = atm and atm.state == 'open' and type(index) == 'number' and atm.notes[index]
    if not note or note.taken then return false, locale('note_gone') end

    local now = GetGameTimer()
    if lastPickup[src] and now - lastPickup[src] < Config.pickupTime * 0.5 then return false end
    lastPickup[src] = now

    local ped = GetPlayerPed(src)
    if ped == 0 then return false end

    local x, y = AtmOffset(atm, note.x, note.y)
    local pos = GetEntityCoords(ped)
    if #(pos.xy - vec2(x, y)) > PICKUP_RANGE or math.abs(pos.z - atm.z) > 4.0 then return false end

    note.taken = true
    local given, reason = giveReward(src, note.amount)
    if not given then
        note.taken = false
        return false, reason
    end

    publish()
    DebugPrint('Note taken', id, index, note.amount, 'by', src)
    return true, rewardText(note.amount)
end)

Bridge.OnPlayerUnload(releaseBySource)

AddEventHandler('playerDropped', function()
    releaseBySource(source)
    lastPickup[source] = nil
end)

GlobalState[Atm.globalKey] = {}
