--[[
    dps-services server/trucker.lua
    The trucker script (m-TruckerSimulator) and the city licences, working as
    one (Damon 2026-10-11, page NN1GLRtA). Its core is escrowed, but its open
    server/sv_webhooks.lua fires these two events from the job accepted and job
    completed hooks (two DPS lines in that file; carry them over at updates).

    A hazardous load (Explosives, Compressed Gas, Fuel) without a Hazmat
    licence: a warning when the job is taken; on delivery the shipper's pay is
    taken back and police get a dispatch alert.

    Server-side events only (AddEventHandler, never RegisterNetEvent), so a
    client cannot fire them.
]]

local function playerByCid(cid)
    local ok, player = pcall(function() return exports.qbx_core:GetPlayerByCitizenId(cid) end)
    return ok and player or nil
end

local function heldBy(player)
    local l = player and player.PlayerData.metadata and player.PlayerData.metadata.licences
    return type(l) == 'table' and l or {}
end

local function notify(source, title, text, kind)
    TriggerClientEvent('ox_lib:notify', source, { title = title, description = text, type = kind, duration = 10000 })
end

AddEventHandler('dps-services:trucker:jobAccepted', function(cid, cargo, hazardous)
    print(('[dps-services] trucker job accepted cid=%s cargo=%s hazardous=%s'):format(
        tostring(cid), tostring(cargo), tostring(hazardous)))
    local player = playerByCid(cid)
    if not player then return end
    if Licences.hazmatVerdict(hazardous == true, heldBy(player)) == 'unlicensed' then
        notify(player.PlayerData.source, 'No Hazmat licence',
            'This is a hazardous load. Without a city Hazmat licence the shipper will not pay, and the police will be told.',
            'warning')
    end
end)

local function alertPolice(source, cargo)
    if GetResourceState('wasabi_mdt') ~= 'started' then return end
    local coords = GetEntityCoords(GetPlayerPed(source))
    local ok, err = pcall(function()
        exports.wasabi_mdt:CreateDispatch({
            type = 'traffic',
            code = '10-55',
            title = 'Illegal hazmat haul',
            description = ('A truck delivered %s without a Hazmat licence.'):format(tostring(cargo)),
            location = 'Hazmat delivery',
            coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
            priority = 2,
            metadata = { caller_name = 'Shipper', weapons_involved = false, injuries_reported = false, suspects = 1 },
        })
    end)
    if not ok then print('[dps-services] hazmat dispatch failed: ' .. tostring(err)) end
end

AddEventHandler('dps-services:trucker:jobCompleted', function(cid, cargo, payment, hazardous)
    print(('[dps-services] trucker job completed cid=%s cargo=%s pay=%s hazardous=%s'):format(
        tostring(cid), tostring(cargo), tostring(payment), tostring(hazardous)))
    local player = playerByCid(cid)
    if not player then return end
    if Licences.hazmatVerdict(hazardous == true, heldBy(player)) ~= 'unlicensed' then return end
    local source = player.PlayerData.source
    local amount = math.floor(tonumber(payment) or 0)
    local taken = amount > 0 and (player.Functions.RemoveMoney('bank', amount, 'hazmat-unlicensed')
        or player.Functions.RemoveMoney('cash', amount, 'hazmat-unlicensed'))
    notify(source, 'Pay taken back',
        ('No Hazmat licence: the shipper took back $%d and reported the load to the police.'):format(taken and amount or 0),
        'error')
    alertPolice(source, cargo)
end)
