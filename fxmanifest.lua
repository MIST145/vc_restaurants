fx_version 'cerulean'
game 'gta5'

author 'VGroup / v2'
description 'VC-Restaurants v2 — ESX / ox_lib / ox_target'
version '2.0.0'
lua54 'yes'

-- NUI page (used by the editor to copy text to clipboard)
ui_page 'html/index.html'

files {
    'html/index.html'
}

shared_scripts {
    'config.lua',
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'shared/utils.lua'
}

client_scripts {
    'data/restaurants.lua',
    'client/main.lua',
    'client/menu.lua',
    'client/editor.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'data/restaurants.lua',
    'server/main.lua',
    'server/editor.lua'
}

-- dependencies {
--     'es_extended',
--     'object_gizmo',
--     'ox_inventory',
--     'ox_target',
--     'ox_lib'
-- }
