local atms = {}
local points = {}
local scenes = {}
local fresh = {}

local isLoaded, prying, picking = false, false, false

local CROWBAR = GetHashKey(Config.weapon)
local PRY_TARGET = 'meteo_atmrobbery_pry'
local PICKUP_DICT, PICKUP_CLIP = 'pickup_object', 'pickup_low'

local PULL_MS, FALL_MS, BOUNCE_MS = 350, 650, 200
local PUSH = 0.2
local BODY_PUSH = 0.23

local pieces = {}
for name, set in pairs(Config.atmPieces or {}) do
    pieces[joaat(name) % 0x100000000] = set
end
local SPRAY_MS, SPRAY_GAP, SPRAY_ARC = 700, 90, 0.5
local BURST_GRAVITY = 4.0
local BURST_DRAG = 1.2
local BURST_LINGER = 3000

local FX = {
    sparks = { asset = 'core', name = 'ent_sht_electrical_box' },
    cash = { asset = 'scr_ornate_heist', name = 'scr_heist_ornate_banknotes', looped = true },
}

local function notify(msg, type)
    Bridge.Notify(msg, type or 'primary')
end

local function loadModel(name)
    local hash = type(name) == 'number' and name or joaat(name)
    if not IsModelInCdimage(hash) then return end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function loadFx()
    for _, fx in pairs(FX) do RequestNamedPtfxAsset(fx.asset) end
    local timeout = GetGameTimer() + 2000
    for _, fx in pairs(FX) do
        while not HasNamedPtfxAssetLoaded(fx.asset) and GetGameTimer() < timeout do Wait(0) end
    end
end

local function playFx(fx, coords)
    if not HasNamedPtfxAssetLoaded(fx.asset) then return end
    UseParticleFxAsset(fx.asset)
    if not fx.looped then
        StartParticleFxNonLoopedAtCoord(fx.name, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 1.0, false, false, false)
        return
    end
    return StartParticleFxLoopedAtCoord(fx.name, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
end

local function stopFx(scene)
    if scene.fx then StopParticleFxLooped(scene.fx, false) end
    scene.fx = nil
end

local function toWorld(atm, x, y, z)
    local wx, wy = AtmOffset(atm, x, y)
    return vec3(wx, wy, atm.z + z)
end

local function groundAt(x, y, fromZ, fallback)
    local found, z = GetGroundZFor_3dCoord(x, y, fromZ, false)
    return found and z or fallback
end

local function keepInRoom(obj, atm)
    local interior = GetInteriorFromEntity(cache.ped)
    if interior ~= 0 and interior == GetInteriorAtCoords(atm.x, atm.y, atm.z) then
        ForceRoomForEntity(obj, interior, GetRoomKeyFromEntity(cache.ped))
    end
end

local function robbedAt(coords)
    for _, atm in pairs(atms) do
        if #(coords - vec3(atm.x, atm.y, atm.z)) < 1.0 then return true end
    end
    return false
end

local function setPose(obj, atm, dims, angle, push, drop)
    local a = math.rad(angle)
    local py, pz = dims.min.y, dims.min.z
    local y = py - (py * math.cos(a) - pz * math.sin(a)) - push
    local z = pz - (py * math.sin(a) + pz * math.cos(a)) + drop
    local pos = toWorld(atm, 0.0, y, z)
    SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
    SetEntityRotation(obj, angle, 0.0, atm.h, 2, false)
end

local function tween(ms, alive, step)
    local start = GetGameTimer()
    while true do
        if not alive() then return false end
        local t = math.min((GetGameTimer() - start) / ms, 1.0)
        step(t)
        if t >= 1.0 then return true end
        Wait(0)
    end
end

local function dropAtm(obj, atm, dims, drop, slot, alive, push, tilt)
    playFx(FX.sparks, slot)
    if not tween(PULL_MS, alive, function(t)
        setPose(obj, atm, dims, tilt * t, push * t, 0.0)
    end) then return false end

    if not tween(FALL_MS, alive, function(t)
        local k = t * t
        setPose(obj, atm, dims, tilt + (90.0 - tilt) * k, push, drop * k)
    end) then return false end

    return tween(BOUNCE_MS, alive, function(t)
        setPose(obj, atm, dims, 90.0 - math.sin(t * math.pi) * 5.0, push, drop)
    end)
end

local function removeBurstNote(scene, obj)
    scene.burst[obj] = nil
    if DoesEntityExist(obj) then DeleteEntity(obj) end
end

local function cashBurst(scene, atm, slot, groundZ, alive)
    local burst = Config.cashBurst
    local hash = burst and loadModel(burst.model)
    if not hash or not alive() then return end

    scene.fx = playFx(FX.cash, slot)

    local h = math.rad(atm.h)
    local c, s = math.cos(h), math.sin(h)
    local gap = 1000 / burst.notesPerSecond
    local start = GetGameTimer()
    local last, nextSpawn = start, start
    local flying, landed = {}, {}

    while alive() do
        local now = GetGameTimer()
        local dt = math.min((now - last) / 1000, 0.05)
        last = now

        local spraying = now - start < burst.duration * 1000
        if not spraying then stopFx(scene) end

        if nextSpawn < now - 200 then nextSpawn = now end
        while spraying and nextSpawn <= now do
            nextSpawn = nextSpawn + gap
            local obj = CreateObjectNoOffset(hash, slot.x, slot.y, slot.z, false, false, false)
            SetEntityCollision(obj, false, false)
            FreezeEntityPosition(obj, true)
            scene.burst[obj] = true

            local lx, ly = (math.random() - 0.5) * 3.0, -(1.0 + math.random() * 2.5)
            flying[obj] = {
                pos = slot,
                vel = vec3(lx * c - ly * s, lx * s + ly * c, 1.0 + math.random() * 2.5),
                rot = vec3(math.random() * 360.0, math.random() * 360.0, math.random() * 360.0),
                spin = vec3(math.random(-720, 720), math.random(-720, 720), math.random(-360, 360)),
                seed = math.random() * 10.0,
            }
        end

        local drag = 1.0 - BURST_DRAG * dt
        for obj, n in pairs(flying) do

            local wobble = math.sin(now * 0.008 + n.seed) * 0.6
            n.vel = vec3(n.vel.x * drag + wobble * dt, n.vel.y * drag, n.vel.z - BURST_GRAVITY * dt)
            n.pos = n.pos + n.vel * dt
            n.rot = n.rot + n.spin * dt

            if n.pos.z <= groundZ then
                SetEntityCoordsNoOffset(obj, n.pos.x, n.pos.y, groundZ + 0.01, false, false, false)
                SetEntityRotation(obj, 0.0, 0.0, n.rot.z, 2, false)
                flying[obj] = nil
                landed[#landed + 1] = { obj = obj, at = now }
            else
                SetEntityCoordsNoOffset(obj, n.pos.x, n.pos.y, n.pos.z, false, false, false)
                SetEntityRotation(obj, n.rot.x, n.rot.y, n.rot.z, 2, false)
            end
        end

        while landed[1] and now - landed[1].at > BURST_LINGER do
            removeBurstNote(scene, table.remove(landed, 1).obj)
        end

        if not spraying and not next(flying) and not landed[1] then break end
        Wait(0)
    end
    SetModelAsNoLongerNeeded(hash)
end

local function removeNote(scene, index)
    local zone = scene.zones[index]
    if zone then pcall(function() exports.ox_target:removeZone(zone) end) end
    local obj = scene.notes[index]
    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
    scene.zones[index], scene.notes[index] = nil, nil
end

local function syncNotes(id)
    local scene, atm = scenes[id], atms[id]
    if not scene or not atm then return end
    for i, note in ipairs(atm.notes) do
        if note.taken then removeNote(scene, i) end
    end
end

local function pickupNote(id, index)
    if picking then return end
    picking = true

    if loadDict(PICKUP_DICT) then
        TaskPlayAnim(cache.ped, PICKUP_DICT, PICKUP_CLIP, 8.0, -8.0, -1, 0, 0, false, false, false)
    end
    Wait(Config.pickupTime)

    local ok, result = lib.callback.await('meteo-atmrobbery:server:pickup', false, id, index)
    picking = false

    if ok then
        if scenes[id] then removeNote(scenes[id], index) end
        notify(result, 'success')
    elseif result then
        notify(result, 'error')
    end
end

local function addNoteZone(id, index, coords)
    return exports.ox_target:addSphereZone({
        coords = coords,
        radius = 0.35,
        debug = Config.debug,
        options = {
            {
                name = 'meteo_atmrobbery_pickup',
                icon = 'fas fa-money-bill-wave',
                label = locale('target_pickup'),
                distance = 2.0,
                canInteract = function() return not picking end,
                onSelect = function() pickupNote(id, index) end,
            },
        },
    })
end

local function landNote(scene, id, index, spot)
    local obj = scene.notes[index]
    if not obj or scene.zones[index] then return end
    SetEntityCoordsNoOffset(obj, spot.x, spot.y, spot.z, false, false, false)
    SetEntityRotation(obj, 0.0, 0.0, index * 47.0, 2, false)
    PlaceObjectOnGroundProperly(obj)
    SetEntityVisible(obj, true, false)
    scene.zones[index] = addNoteZone(id, index, spot)
end

local function sprayGap(count)
    local burst = Config.cashBurst
    if not burst or count < 2 then return SPRAY_GAP end
    return math.max(SPRAY_GAP, (burst.duration * 1000 - SPRAY_MS) / (count - 1))
end

local function sprayNotes(scene, id, slot, spots, alive)
    local gap = sprayGap(#spots)
    local start = GetGameTimer()
    while true do
        if not alive() then return false end
        local elapsed = GetGameTimer() - start
        local done = true
        for i, obj in pairs(scene.notes) do
            if not scene.zones[i] then
                local t = math.min(math.max((elapsed - (i - 1) * gap) / SPRAY_MS, 0.0), 1.0)
                if t >= 1.0 then
                    landNote(scene, id, i, spots[i])
                else
                    done = false
                    local pos = slot + (spots[i] - slot) * t
                    SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z + SPRAY_ARC * 4.0 * t * (1.0 - t), false, false, false)
                    SetEntityRotation(obj, 0.0, 0.0, i * 47.0 + t * 720.0, 2, false)
                    SetEntityVisible(obj, t > 0.0, false)
                end
            end
        end
        if done then return true end
        Wait(0)
    end
end

local function spawnScene(id, animate)
    local atm = atms[id]
    if not atm or scenes[id] then return end

    local scene = { notes = {}, zones = {}, burst = {} }
    scenes[id] = scene
    local function alive() return scenes[id] == scene end

    local set = pieces[atm.model % 0x100000000]
    local atmHash, noteHash = loadModel(set and set.body or atm.model), loadModel(Config.noteModel)
    local frameHash = set and loadModel(set.frame)
    if animate then loadFx() end

    if not alive() then return end
    if not atmHash or not noteHash or (set and not frameHash) then
        DebugPrint('Model missing', set and set.body or atm.model, set and set.frame, Config.noteModel)
        return
    end
    local push, tilt = set and BODY_PUSH or PUSH, set and 0.0 or 4.0

    local min, max = GetModelDimensions(atmHash)
    local dims = { min = min, max = max }
    local height = max.z - min.z
    local landing = toWorld(atm, 0.0, min.y - height * 0.5 - push, 0.0)
    local floor = atm.z + min.z
    local drop = math.min(0.0, groundAt(landing.x, landing.y, atm.z + max.z, floor) - floor)
    local slot = toWorld(atm, 0.0, min.y + 0.05, min.z + height * 0.55)

    if frameHash then
        local frame = CreateObjectNoOffset(frameHash, atm.x, atm.y, atm.z, false, false, false)
        SetEntityRotation(frame, 0.0, 0.0, atm.h, 2, false)
        FreezeEntityPosition(frame, true)
        keepInRoom(frame, atm)
        scene.frame = frame
        SetModelAsNoLongerNeeded(frameHash)
    end

    local obj = CreateObjectNoOffset(atmHash, atm.x, atm.y, atm.z, false, false, false)
    SetEntityRotation(obj, 0.0, 0.0, atm.h, 2, false)
    FreezeEntityPosition(obj, true)
    keepInRoom(obj, atm)
    scene.atm = obj

    local spots = {}
    for i, note in ipairs(atm.notes) do
        local x, y = AtmOffset(atm, note.x, note.y)
        spots[i] = vec3(x, y, groundAt(x, y, atm.z + max.z, floor + drop) + 0.02)
        if not note.taken then
            local n = CreateObjectNoOffset(noteHash, slot.x, slot.y, slot.z, false, false, false)
            SetEntityCollision(n, false, false)
            FreezeEntityPosition(n, true)
            if animate then SetEntityVisible(n, false, false) end
            scene.notes[i] = n
        end
    end
    SetModelAsNoLongerNeeded(atmHash)
    SetModelAsNoLongerNeeded(noteHash)

    if animate then
        SetEntityCollision(obj, false, false)
        if not dropAtm(obj, atm, dims, drop, slot, alive, push, tilt) then return end
        SetEntityCollision(obj, true, true)
        CreateThread(function() cashBurst(scene, atm, slot, floor + drop, alive) end)
        if not sprayNotes(scene, id, slot, spots, alive) then return end
    else
        setPose(obj, atm, dims, 90.0, push, drop)
        for i in pairs(scene.notes) do landNote(scene, id, i, spots[i]) end
    end

    DebugPrint('ATM in range', id)
end

local function despawnScene(id)
    local scene = scenes[id]
    if not scene then return end
    scenes[id] = nil
    stopFx(scene)
    for obj in pairs(scene.burst) do removeBurstNote(scene, obj) end
    for i in pairs(scene.notes) do removeNote(scene, i) end
    if scene.atm and DoesEntityExist(scene.atm) then DeleteEntity(scene.atm) end
    if scene.frame and DoesEntityExist(scene.frame) then DeleteEntity(scene.frame) end
end

local function addAtm(atm, animate)
    local id = atm.id
    atms[id] = atm
    fresh[id] = animate or nil
    CreateModelHideExcludingScriptObjects(atm.x, atm.y, atm.z, Atm.hideRadius, atm.model, true)

    local point = lib.points.new({
        coords = vec3(atm.x, atm.y, atm.z),
        distance = Config.renderDistance,
    })
    function point:onEnter()
        local play = fresh[id]
        fresh[id] = nil
        CreateThread(function() spawnScene(id, play) end)
    end
    function point:onExit()
        fresh[id] = nil
        despawnScene(id)
    end
    points[id] = point
end

local function removeAtm(id)
    local atm = atms[id]
    despawnScene(id)
    if points[id] then points[id]:remove() end
    if atm then RemoveModelHide(atm.x, atm.y, atm.z, Atm.hideRadius, atm.model, false) end
    atms[id], points[id], fresh[id] = nil, nil, nil
end

local function applyAtms(list, animate)
    local here = GetEntityCoords(cache.ped)
    local seen = {}
    for _, atm in ipairs(list or {}) do
        seen[atm.id] = true
        if atms[atm.id] then
            atms[atm.id] = atm
            syncNotes(atm.id)
        else
            addAtm(atm, animate and #(here - vec3(atm.x, atm.y, atm.z)) <= Config.renderDistance)
        end
    end
    for id in pairs(atms) do
        if not seen[id] then removeAtm(id) end
    end
end

AddStateBagChangeHandler(Atm.globalKey, 'global', function(_, _, value)
    if isLoaded then applyAtms(value, true) end
end)

local function pryAtm(entity)
    if prying then return end
    prying = true

    local coords, heading = GetEntityCoords(entity), GetEntityHeading(entity)
    local ok, result = lib.callback.await('meteo-atmrobbery:server:start', false, coords, GetEntityModel(entity), heading)
    if not ok then
        prying = false
        notify(result or locale('pry_failed'), 'error')
        return
    end

    local id = result

    local anim = Config.minigame.anim
    SetEntityHeading(cache.ped, heading)
    if loadDict(anim.dict) then
        TaskPlayAnim(cache.ped, anim.dict, anim.clip, 3.0, 3.0, -1, 1, 0, false, false, false)
    end

    CreateThread(function()
        while prying do
            if not isLoaded or IsEntityDead(cache.ped) or #(GetEntityCoords(cache.ped) - coords) > 3.0 then
                Minigame.Cancel()
                return
            end
            Wait(500)
        end
    end)

    local success = Minigame.Keymash(Config.minigame)
    prying = false
    StopAnimTask(cache.ped, anim.dict, anim.clip, 1.0)

    if not isLoaded then return end

    if lib.callback.await('meteo-atmrobbery:server:finish', false, id, success == true) then
        notify(locale('atm_opened'), 'success')
    else
        notify(locale('pry_failed'), 'error')
    end
end

local function atmOptions()
    return {
        {
            name = PRY_TARGET,
            icon = 'fas fa-hammer',
            label = locale('target_pry'),
            distance = 1.5,
            canInteract = function(entity)
                return isLoaded and not prying
                    and GetSelectedPedWeapon(cache.ped) == CROWBAR
                    and not robbedAt(GetEntityCoords(entity))
            end,
            onSelect = function(data) pryAtm(data.entity) end,
        },
    }
end

local function initialize()
    if isLoaded then return end
    isLoaded = true
    exports.ox_target:addModel(Config.atmModels, atmOptions())
    applyAtms(GlobalState[Atm.globalKey], false)
end

local function cleanup()
    if prying then Minigame.Cancel() end
    isLoaded, prying, picking = false, false, false
    pcall(function() exports.ox_target:removeModel(Config.atmModels, PRY_TARGET) end)
    for id in pairs(atms) do removeAtm(id) end
end

Bridge.OnPlayerLoaded(initialize)
Bridge.OnPlayerUnload(cleanup)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1000)
    if Bridge.IsLoggedIn() then initialize() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanup()
end)
