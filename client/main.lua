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
local function registerWhenReady(triesLeft)
    local state = GetResourceState('lb-phone')
    if state == 'started' then
        registerPhoneApp()
    elseif state == 'starting' and triesLeft > 0 then
        SetTimeout(3000, function() registerWhenReady(triesLeft - 1) end)
    end
end
SetTimeout(2000, function() registerWhenReady(5) end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'lb-phone' then return end
    SetTimeout(5000, registerPhoneApp)
end)

local warnedPhone, warnedTablet = false, false

--- Push into the page on whichever device has it open. SendNUIMessage cannot
--- reach a page that lives in another resource's frame.
local function sendApp(action, data)
    local phoneOk = pcall(function()
        exports['lb-phone']:SendCustomAppMessage(APP, { action = action, data = data })
    end)
    if not phoneOk and not warnedPhone and GetResourceState('lb-phone') == 'started' then
        warnedPhone = true
        print('^1[dps-services] SendCustomAppMessage (lb-phone) failed^7')
    end
    local tabletOk = pcall(function()
        exports['lb-tablet']:SendCustomAppMessage(APP, action, data)
    end)
    if not tabletOk and not warnedTablet and GetResourceState('lb-tablet') == 'started' then
        warnedTablet = true
        print('^1[dps-services] SendCustomAppMessage (lb-tablet) failed^7')
    end
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
    if street == '' or street == 'NULL' then street = nil end
    local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    if zone == '' or zone == 'NULL' then zone = nil end
    if street and zone then return street .. ', ' .. zone end
    if street then return street end
    if zone then return zone end
    return 'Unknown area'
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
    if not NetworkGetEntityIsNetworked(vehicle) then return false end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    return {
        netId = netId,
        plate = plate,
        model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)),
        coords = { x = c.x, y = c.y, z = c.z },
        location = locationLabel(c),
    }
end

local function ask(name, fallback, ...)
    local ok, result = pcall(lib.callback.await, name, false, ...)
    if ok and result then return result end
    return fallback
end

RegisterNUICallback('getState', function(_, cb)
    cb(ask('dps-services:getState', { available = false }))
end)

RegisterNUICallback('scan', function(_, cb)
    local vehicle = scanVehicle()
    if vehicle and type(vehicle.netId) == 'number' then
        local info = ask('dps-services:vehicleInfo', false, vehicle.netId)
        if info then
            vehicle.photo = info.photo or nil
            if info.label then vehicle.model = info.label end
        end
    end
    cb({ vehicle = vehicle })
end)

RegisterNUICallback('requestTow', function(data, cb)
    local scan = scanVehicle()
    if not scan then
        cb({ ok = false, reason = 'no_vehicle', message = Services.reasonText('no_vehicle') })
        return
    end
    cb(ask('dps-services:requestTow', { ok = false, message = Services.reasonText('unavailable') }, data and data.kind, scan))
end)

RegisterNUICallback('cancelRequest', function(_, cb)
    cb(ask('dps-services:cancelRequest', { ok = false, message = Services.reasonText('unavailable') }))
end)

RegisterNUICallback('driverAnswer', function(data, cb)
    cb(ask('dps-services:driverAnswer', { ok = false, message = Services.reasonText('unavailable') }, data and data.jobId, data and data.accept == true))
end)

RegisterNUICallback('gps', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
    cb({ ok = x ~= nil and y ~= nil })
end)
