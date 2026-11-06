function DebugPrint(...)
    if not Config.debug then return end

    local msg = {}
    for _, v in ipairs({...}) do
        msg[#msg + 1] = tostring(v)
    end

    print('^6[METEO ATMROBBERY]^0 ' .. table.concat(msg, ', '))
end

function GetFramework()
    if Config.framework == 'qbox' or Config.framework == 'qbcore' then
        return Config.framework
    end
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    return 'qbcore'
end

Atm = {
    globalKey = 'meteo_atmrobbery',
    hideRadius = 0.25,
}

function AtmOffset(atm, x, y)
    local h = math.rad(atm.h)
    local c, s = math.cos(h), math.sin(h)
    return atm.x + x * c - y * s, atm.y + x * s + y * c
end
