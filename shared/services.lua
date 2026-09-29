--[[
    dps-services shared/services.lua
    Pure helpers. No natives, so tests/ can run them under plain lua5.4.
]]

Services = {}

local KINDS = { repair = true, impound = true }

local function trim(text)
    if type(text) ~= 'string' then return '' end
    local clean = text:gsub('^%s+', '')
    clean = clean:gsub('%s+$', '')
    return clean
end

--- Turn what the client saw into the payload dps-towjob expects.
function Services.cleanRequest(kind, scan)
    if type(kind) ~= 'string' or not KINDS[kind] then return false, 'bad_kind' end
    if type(scan) ~= 'table' then return false, 'no_vehicle' end
    local plate = trim(scan.plate)
    if #plate == 0 then return false, 'no_vehicle' end
    if type(scan.netId) ~= 'number' then return false, 'no_vehicle' end
    local c = scan.coords
    if type(c) ~= 'table' or type(c.x) ~= 'number' or type(c.y) ~= 'number' or type(c.z) ~= 'number' then
        return false, 'bad_coords'
    end
    return true, {
        kind = kind,
        plate = plate,
        model = trim(scan.model),
        netId = tonumber(scan.netId),
        coords = { x = c.x, y = c.y, z = c.z },
        location = trim(scan.location),
    }
end

function Services.minutes(seconds)
    if type(seconds) ~= 'number' or seconds <= 0 then return 0 end
    return math.ceil(seconds / 60)
end

local CANCEL_REASONS = {
    vehicle_gone = 'Cancelled: the vehicle was no longer there. Nothing was charged.',
    vehicle_occupied = 'Cancelled: someone was in the vehicle. Nothing was charged.',
    no_destination = 'Cancelled: no yard could take the vehicle. Nothing was charged.',
    requester = 'Request cancelled.',
}

function Services.statusText(view)
    local line
    local status = view.status
    local driver = view.driverName or 'A driver'
    if status == 'queued' then
        if view.position then
            line = ('Request received. You are number %d in line.'):format(view.position)
        else
            line = 'Request received. Finding a driver.'
        end
    elseif status == 'accepted' then
        local minutes = Services.minutes(view.etaSeconds)
        if view.cityTow then
            line = ('%s is on the way.'):format(driver)
            if minutes > 0 then line = ('%s is on the way. About %d min away.'):format(driver, minutes) end
        elseif minutes > 0 then
            line = ('%s accepted. About %d min away.'):format(driver, minutes)
        else
            line = ('%s accepted and is on the way.'):format(driver)
        end
    elseif status == 'arrived' then
        line = ('%s has arrived.'):format(driver)
    elseif status == 'hooked' then
        if view.destination then
            line = ('Your vehicle is on the truck, heading to %s.'):format(view.destination)
        else
            line = 'Your vehicle is on the truck.'
        end
    elseif status == 'delivered' then
        if view.destination then
            line = ('Delivered to %s.'):format(view.destination)
        else
            line = 'Your vehicle was delivered.'
        end
    else
        line = CANCEL_REASONS[view.reason] or 'Request cancelled.'
    end
    return { title = 'City Services', line = line }
end

local REASONS = {
    no_player = 'Your character is not loaded yet. Try again in a moment.',
    bad_request = 'The request was not complete. Open the app and try again.',
    bad_kind = 'Pick Repair tow or Impound tow first.',
    open_request = 'You already have a tow on the way.',
    cooldown = 'You asked a moment ago. Wait two minutes and try again.',
    not_allowed = 'Impound tows are for police, EMS and fire on duty.',
    bad_coords = 'Could not read where the vehicle is. Stand next to it and try again.',
    too_far = 'Stand next to the vehicle and try again.',
    no_vehicle = 'No vehicle found next to you. Stand beside it and scan again.',
    no_funds = 'You need $200 in the bank for a repair tow.',
    queue_full = 'Tow dispatch is full right now. Try again in a few minutes.',
    no_request = 'You have no open request.',
    too_late = 'A driver already accepted. It can no longer be cancelled here.',
    no_offer = 'That offer is no longer open.',
    expired = 'That offer ran out of time.',
    gone = 'The caller cancelled that request.',
    unavailable = 'Tow dispatch is offline right now.',
    not_owner = 'A repair tow is for your own vehicle. This one is not registered to you.',
}

function Services.reasonText(reason)
    return REASONS[reason] or 'That did not work. Try again in a moment.'
end

return Services
