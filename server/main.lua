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

local function stateFor(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return { available = false } end
    local pd = player.PlayerData
    local job = pd.job or {}
    local cfg = tow('GetRequestConfig')
    if type(cfg) ~= 'table' then
        return { available = false, me = { name = 'Unknown', canImpound = false, isTowDriver = false } }
    end
    local charinfo = pd.charinfo or {}
    return {
        available = true,
        me = {
            name = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')),
            canImpound = job.onduty == true and cfg.emergencyJobTypes[job.type] == true,
            isTowDriver = job.name == cfg.jobName,
        },
        fees = { repair = cfg.repairTowFee, impound = cfg.emergencyTowFee },
        request = tow('GetRequestStatus', source) or false,
        driver = tow('GetDriverView', source) or false,
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
    return { ok = true, request = result }
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
    return { ok = true, driver = tow('GetDriverView', source) or false }
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
    local open = view.status ~= 'delivered' and view.status ~= 'cancelled'
    TriggerClientEvent('dps-services:client:push', source, 'request', view)
    if changed then notify(source, Services.statusText(view)) end
    if not open then
        SetTimeout(15000, function()
            if GetPlayerName(source) then
                TriggerClientEvent('dps-services:client:push', source, 'request', tow('GetRequestStatus', source) or false)
            end
        end)
    end
end)

AddEventHandler('dps-towjob:driverUpdate', function(source)
    if type(source) ~= 'number' or not GetPlayerName(source) then return end
    TriggerClientEvent('dps-services:client:push', source, 'driver', tow('GetDriverView', source) or false)
end)

-- Server console only: one line of proof that the app can reach the tow script.
RegisterCommand('servicesdebug', function(source)
    if source ~= 0 then return end
    local cfg = tow('GetRequestConfig')
    print(('[servicesdebug] tow resource=%s state=%s repair fee=%s impound fee=%s range=%s'):format(
        TOW, GetResourceState(TOW), type(cfg) == 'table' and cfg.repairTowFee or 'n/a',
        type(cfg) == 'table' and cfg.emergencyTowFee or 'n/a', type(cfg) == 'table' and cfg.vehicleRange or 'n/a'))
end, true)
