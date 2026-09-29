fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-services'
author 'DPS Development'
description 'City Services - request a tow and follow it live, on the lb-phone and the lb-tablet'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/services.lua',
}

client_script 'client/main.lua'
server_script 'server/main.lua'

-- The page is served into the phone and tablet frames. It is deliberately NOT
-- a ui_page: this resource never takes NUI focus of its own.
files { 'ui/index.html' }

-- dps-towjob is NOT listed: FiveM force-stops dependents when a dependency
-- restarts and does not bring them back, which would drop the app from the
-- phone. Every call into dps-towjob is guarded instead.
dependencies { 'ox_lib', 'lb-phone' }
