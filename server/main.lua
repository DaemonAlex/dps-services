--[[
    dps-services server/main.lua
    Forwards to dps-towjob and relays its updates to the right player.
    Decides nothing about the queue.
]]

local TOW = Config.TowResource

local function towUp()
    return GetResourceState(TOW) == 'started'
end

--- Call a dps-towjob export without letting an error reach the player.
local function tow(name, ...)
    if not towUp() then return false, 'unavailable' end
    local args = { ... }
    local ok, a, b = pcall(function()
        return exports[TOW][name](exports[TOW], table.unpack(args))
    end)
    if not ok then
        print(('[dps-services] %s failed: %s'):format(name, tostring(a)))
        return false, 'unavailable'
    end
    return a, b
end

local function fail(reason)
    return { ok = false, reason = reason, message = Services.reasonText(reason) }
end

local PHOTOS = {} -- spawn code -> address or false, kept for this server run

local function photoFor(code)
    if type(code) ~= 'string' or code == '' then return nil end
    if PHOTOS[code] ~= nil then return PHOTOS[code] or nil end
    if GetResourceState('jg-vehiclestudio') ~= 'started' then return nil end
    local found = false
    local ok, images = pcall(function()
        return exports['jg-vehiclestudio']:getImages({ code }, 'default')
    end)
    if ok and type(images) == 'table' then
        found = Services.pickPhoto(images[code]) or false
        PHOTOS[code] = found
    end
    return found or nil
end

local function withRequestPhoto(view)
    if type(view) ~= 'table' then return view end
    local copy = {}
    for k, v in pairs(view) do copy[k] = v end
    copy.photo = photoFor(view.code)
    return copy
end

local function withDriverPhotos(view)
    if type(view) ~= 'table' then return view end
    local copy = {}
    for k, v in pairs(view) do copy[k] = v end
    if type(view.offer) == 'table' then
        local offer = {}
        for k, v in pairs(view.offer) do offer[k] = v end
        offer.photo = photoFor(view.offer.vehicleCode)
        copy.offer = offer
    end
    if type(view.job) == 'table' then
        local job = {}
        for k, v in pairs(view.job) do job[k] = v end
        job.photo = photoFor(view.job.vehicleCode)
        copy.job = job
    end
    return copy
end

local function trim(text)
    if type(text) ~= 'string' then return '' end
    local clean = text:gsub('^%s+', '')
    clean = clean:gsub('%s+$', '')
    return clean
end

local function notAvailable(name)
    return { available = false, me = { name = name or 'Citizen', canImpound = false, isTowDriver = false }, fees = false, request = false, driver = false }
end

local function stateFor(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return notAvailable() end
    local pd = player.PlayerData
    local job = pd.job or {}
    local charinfo = pd.charinfo or {}
    local name = trim(trim(charinfo.firstname) .. ' ' .. trim(charinfo.lastname))
    if name == '' then name = 'Citizen' end
    local cfg = tow('GetRequestConfig')
    if type(cfg) ~= 'table' then return notAvailable(name) end
    return {
        available = true,
        me = {
            name = name,
            canImpound = job.onduty == true and cfg.emergencyJobTypes[job.type] == true,
            isTowDriver = job.name == cfg.jobName,
        },
        fees = { repair = cfg.repairTowFee, impound = cfg.emergencyTowFee },
        request = withRequestPhoto(tow('GetRequestStatus', source)) or false,
        driver = withDriverPhotos(tow('GetDriverView', source)) or false,
    }
end

lib.callback.register('dps-services:getState', function(source)
    return stateFor(source)
end)

lib.callback.register('dps-services:requestTow', function(source, kind, scan)
    local ok, payload = Services.cleanRequest(kind, scan)
    if not ok then return fail(payload) end
    local done, result = tow('RequestService', source, payload)
    if not done then return fail(result) end
    return { ok = true, request = withRequestPhoto(result) }
end)

lib.callback.register('dps-services:cancelRequest', function(source)
    local done, reason = tow('CancelRequest', source)
    if not done then return fail(reason) end
    return { ok = true }
end)

lib.callback.register('dps-services:driverAnswer', function(source, jobId, accept)
    if type(jobId) ~= 'string' then return fail('no_offer') end
    local done, reason = tow(accept == true and 'AcceptOffer' or 'DeclineOffer', source, jobId)
    if not done then return fail(reason) end
    return { ok = true, driver = withDriverPhotos(tow('GetDriverView', source)) or false }
end)

lib.callback.register('dps-services:vehicleInfo', function(source, netId)
    netId = tonumber(netId)
    local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false end
    local ped = GetPlayerPed(source)
    if ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(entity)) > 30.0 then return false end
    local ok, entry = pcall(function() return exports.qbx_core:GetVehiclesByHash(GetEntityModel(entity)) end)
    if not ok or type(entry) ~= 'table' or type(entry.model) ~= 'string' then return false end
    local code = entry.model:lower()
    local label = type(entry.name) == 'string' and entry.name ~= ''
        and (((type(entry.brand) == 'string' and entry.brand ~= '') and (entry.brand .. ' ') or '') .. entry.name) or nil
    return { code = code, label = label, photo = photoFor(code) or false }
end)

local function notify(source, text)
    local sent = pcall(function()
        exports['lb-phone']:SendNotification(source, {
            app = Config.AppIdentifier,
            title = text.title,
            content = text.line,
        })
    end)
    if not sent then
        TriggerClientEvent('ox_lib:notify', source, { title = text.title, description = text.line, type = 'inform' })
    end
end

-- These are server events raised by dps-towjob with TriggerEvent. They are
-- NOT registered as net events, so a client cannot fire them.
AddEventHandler('dps-towjob:requestUpdate', function(citizenid, view, changed)
    if type(citizenid) ~= 'string' or type(view) ~= 'table' then return end
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if not player then return end
    local source = player.PlayerData.source
    TriggerClientEvent('dps-services:client:push', source, 'request', withRequestPhoto(view))
    if changed then notify(source, Services.statusText(view)) end
    -- A finished request stays on the page until the player presses Done. It
    -- used to be swept off after 15 s, so "Delivered to X" lived only in the
    -- notification.
end)

AddEventHandler('dps-towjob:driverUpdate', function(source)
    if type(source) ~= 'number' or not GetPlayerName(source) then return end
    TriggerClientEvent('dps-services:client:push', source, 'driver', withDriverPhotos(tow('GetDriverView', source)) or false)
end)

-- Server console only: one line of proof that the app can reach the tow script.
RegisterCommand('servicesdebug', function(source)
    if source ~= 0 then return end
    local cfg = tow('GetRequestConfig')
    print(('[servicesdebug] tow resource=%s state=%s repair fee=%s impound fee=%s range=%s'):format(
        TOW, GetResourceState(TOW), type(cfg) == 'table' and cfg.repairTowFee or 'n/a',
        type(cfg) == 'table' and cfg.emergencyTowFee or 'n/a', type(cfg) == 'table' and cfg.vehicleRange or 'n/a'))
end, true)
