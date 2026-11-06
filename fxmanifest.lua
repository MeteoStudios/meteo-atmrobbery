fx_version 'cerulean'
game 'gta5'

name 'meteo-atmrobbery'
description 'Pry ATMs out of the wall with a crowbar and grab the cash'
author 'Meteo Studios'
version '1.0.0'
copyright 'Copyright (c) 2026 Meteo Studios. All rights reserved.'
-- Website: https://meteostudios.net
-- Discord: https://discord.gg/9kMhSUfuRm

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/cl_bridge.lua',
    'client/cl_minigame.lua',
    'client/cl_main.lua',
}

server_scripts {
    'bridge/sv_bridge.lua',
    'server/sv_main.lua',
}

ui_page 'web/index.html'

files {
    'locales/*.json',
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/sounds/*',
}

data_file 'DLC_ITYP_REQUEST' 'stream/meteo_prop_atm03.ytyp'

lua54 'yes'

escrow_ignore {
    'shared/config.lua',
    -- source access
    '*.lua',
    'bridge/*.lua',
    'client/*.lua',
    'server/*.lua',
    'shared/*.lua',
}
