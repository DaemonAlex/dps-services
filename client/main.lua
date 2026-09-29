--[[
    dps-services client/main.lua
    Registers the app, answers the page, and pushes updates into it.
]]

local APP = Config.AppIdentifier

-- A data: address, because the page and its icon are loaded from inside the
-- phone's frame where relative paths do not resolve.
local ICON = 'data:image/svg+xml;utf8,' ..
    '%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 72 72%22%3E' ..
    '%3Crect width=%2272%22 height=%2272%22 rx=%2216%22 fill=%22%23111522%22/%3E' ..
    '%3Cpath d=%22M14 46h30V30H14zM44 46h14V38l-6-8h-8z%22 fill=%22%23ff7a45%22/%3E' ..
    '%3Ccircle cx=%2224%22 cy=%2248%22 r=%225%22 fill=%22%23f4f1ea%22/%3E' ..
    '%3Ccircle cx=%2250%22 cy=%2248%22 r=%225%22 fill=%22%23f4f1ea%22/%3E%3C/svg%3E'

local function registerPhoneApp()
    local ok, err = pcall(function()
        exports['lb-phone']:AddCustomApp({
            identifier = APP,
            name = Config.AppName,
            description = Config.AppDescription,
            developer = Config.AppDeveloper,
            defaultApp = true,
            size = 96,
            ui = GetCurrentResourceName() .. '/ui/index.html',
            icon = ICON,
        })
    end)
    if not ok then print('^1[dps-services] AddCustomApp failed: ' .. tostring(err) .. '^7') end
end

-- Register on start, and again whenever the phone restarts after us, or the
-- icon disappears from the phone until this resource restarts too.
CreateThread(function()
    while GetResourceState('lb-phone') ~= 'started' do Wait(1000) end
    Wait(2000)
    registerPhoneApp()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'lb-phone' then return end
    SetTimeout(5000, registerPhoneApp)
end)

--- Push into the page on whichever device has it open. SendNUIMessage cannot
--- reach a page that lives in another resource's frame.
local function sendApp(action, data)
    pcall(function()
        exports['lb-phone']:SendCustomAppMessage(APP, { action = action, data = data })
    end)
    pcall(function()
        exports['lb-tablet']:SendCustomAppMessage(APP, action, data)
    end)
end

RegisterNetEvent('dps-services:client:push', function(topic, data)
    if topic ~= 'request' and topic ~= 'driver' then return end
    sendApp('push', { topic = topic, data = data or false })
end)

local function trim(text)
    local clean = (text or ''):gsub('^%s+', '')
    clean = clean:gsub('%s+$', '')
    return clean
end

local function locationLabel(c)
    local streetHash = GetStreetNameAtCoord(c.x, c.y, c.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    if street and street ~= '' then return street .. ', ' .. zone end
    return zone
end

--- The vehicle the player is in, or the closest one within range.
local function scanVehicle()
    local vehicle = cache.vehicle
    if not vehicle or vehicle == 0 then
        vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), Config.ScanRange, false)
    end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    local c = GetEntityCoords(vehicle)
    local plate = trim(GetVehicleNumberPlateText(vehicle))
    if plate == '' then return false end
    local netId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    return {
        netId = netId,
        plate = plate,
        model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)),
        coords = { x = c.x, y = c.y, z = c.z },
        location = locationLabel(c),
    }
end

RegisterNUICallback('getState', function(_, cb)
    cb(lib.callback.await('dps-services:getState', false) or { available = false })
end)

RegisterNUICallback('scan', function(_, cb)
    cb({ vehicle = scanVehicle() })
end)

RegisterNUICallback('requestTow', function(data, cb)
    local scan = scanVehicle()
    if not scan then
        cb({ ok = false, reason = 'no_vehicle', message = Services.reasonText('no_vehicle') })
        return
    end
    cb(lib.callback.await('dps-services:requestTow', false, data and data.kind, scan)
        or { ok = false, message = Services.reasonText('unavailable') })
end)

RegisterNUICallback('cancelRequest', function(_, cb)
    cb(lib.callback.await('dps-services:cancelRequest', false)
        or { ok = false, message = Services.reasonText('unavailable') })
end)

RegisterNUICallback('driverAnswer', function(data, cb)
    cb(lib.callback.await('dps-services:driverAnswer', false, data and data.jobId, data and data.accept == true)
        or { ok = false, message = Services.reasonText('unavailable') })
end)

RegisterNUICallback('gps', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
    cb({ ok = x ~= nil and y ~= nil })
end)
