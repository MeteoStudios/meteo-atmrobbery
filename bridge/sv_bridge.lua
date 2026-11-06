Bridge = {}

if GetFramework() == 'qbox' then
    function Bridge.GetCitizenId(src)
        local player = exports.qbx_core:GetPlayer(src)
        return player and player.PlayerData.citizenid
    end

    function Bridge.GetCopCount()
        return (exports.qbx_core:GetDutyCountType('leo'))
    end

    function Bridge.AddMoney(src, account, amount, reason)
        return exports.qbx_core:AddMoney(src, account, amount, reason) == true
    end
else
    local QBCore = exports['qb-core']:GetCoreObject()

    function Bridge.GetCitizenId(src)
        local player = QBCore.Functions.GetPlayer(src)
        return player and player.PlayerData.citizenid
    end

    function Bridge.GetCopCount()
        local count = 0
        for _, player in pairs(QBCore.Functions.GetQBPlayers()) do
            local job = player.PlayerData.job
            if job.type == 'leo' and job.onduty then count = count + 1 end
        end
        return count
    end

    function Bridge.AddMoney(src, account, amount, reason)
        local player = QBCore.Functions.GetPlayer(src)
        return player ~= nil and player.Functions.AddMoney(account, amount, reason) == true
    end
end

function Bridge.Dispatch(src, coords)
    if GetResourceState('meteo-mdt') ~= 'started' then return end
    exports['meteo-mdt']:SendAlert({
        code = Config.dispatch.code,
        title = locale('dispatch_title'),
        description = locale('dispatch_desc'),
        coords = coords,
        priority = Config.dispatch.priority,
        jobs = Config.dispatch.jobs,
        suspect = src,
    })
end

function Bridge.OnPlayerUnload(cb)
    AddEventHandler('QBCore:Server:OnPlayerUnload', cb)
end
