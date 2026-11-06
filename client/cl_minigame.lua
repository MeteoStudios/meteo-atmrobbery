
Minigame = {}

local active = nil
local lastId = 0
local uiReady = false

RegisterNUICallback('uiReady', function(_, cb)
    uiReady = true
    cb({})
end)

local function finish(success)
    local current = active
    if not current then return end
    active = nil
    SetNuiFocus(false, false)
    current.promise:resolve(success)
end

RegisterNUICallback('finish', function(data, cb)
    cb({})

    if not active or data.id ~= active.id then return end
    DebugPrint('Keymash', data.success and 'success' or 'failed')
    finish(data.success == true)
end)

local function waitForUi()
    local deadline = GetGameTimer() + 5000
    while not uiReady and GetGameTimer() < deadline do Wait(50) end
    return uiReady
end

function Minigame.Keymash(settings)
    if active or not waitForUi() then return false end

    lastId = lastId + 1
    active = { id = lastId, promise = promise.new() }
    local p = active.promise

    SendNUIMessage({
        action = 'start',
        data = {
            id = lastId,
            config = { keys = settings.keys, presses = settings.presses, drain = settings.drain, time = settings.time },
        },
    })
    SetNuiFocus(true, false)

    return Citizen.Await(p)
end

function Minigame.Cancel()
    if not active then return end
    SendNUIMessage({ action = 'stop' })
    finish(false)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then SetNuiFocus(false, false) end
end)
