dofile('shared/services.lua')
local S = Services

local SCAN = { netId = 12, plate = ' 48ABC123 ', model = 'SULTAN', coords = { x = 1.5, y = 2.5, z = 3.5 }, location = 'Zancudo Ave, Sandy Shores' }

T.test('cleanRequest builds the payload the tow script expects', function()
    local ok, p = S.cleanRequest('repair', SCAN)
    T.truthy(ok)
    T.eq(p.kind, 'repair'); T.eq(p.plate, '48ABC123'); T.eq(p.model, 'SULTAN'); T.eq(p.netId, 12)
    T.eq(p.coords.x, 1.5); T.eq(p.coords.y, 2.5); T.eq(p.coords.z, 3.5)
    T.eq(p.location, 'Zancudo Ave, Sandy Shores')
end)

T.test('cleanRequest refuses a bad kind, a missing vehicle and bad coordinates', function()
    local ok, reason = S.cleanRequest('taxi', SCAN)
    T.falsy(ok); T.eq(reason, 'bad_kind')
    ok, reason = S.cleanRequest('repair', nil)
    T.falsy(ok); T.eq(reason, 'no_vehicle')
    ok, reason = S.cleanRequest('repair', { plate = '', coords = { x = 1, y = 2, z = 3 } })
    T.falsy(ok); T.eq(reason, 'no_vehicle')
    ok, reason = S.cleanRequest('repair', { plate = 'ABC', coords = { x = 1, y = 'two', z = 3 } })
    T.falsy(ok); T.eq(reason, 'bad_coords')
end)

T.test('minutes rounds up and never shows zero while time is left', function()
    T.eq(S.minutes(0), 0)
    T.eq(S.minutes(1), 1)
    T.eq(S.minutes(60), 1)
    T.eq(S.minutes(61), 2)
    T.eq(S.minutes(nil), 0)
end)

T.test('statusText: one plain sentence per status', function()
    T.eq(S.statusText({ status = 'queued', position = 2 }).line, 'Request received. You are number 2 in line.')
    T.eq(S.statusText({ status = 'queued' }).line, 'Request received. Finding a driver.')
    T.eq(S.statusText({ status = 'accepted', driverName = 'Ana Ruiz', etaSeconds = 190 }).line, 'Ana Ruiz accepted. About 4 min away.')
    T.eq(S.statusText({ status = 'accepted', driverName = 'City Tow', cityTow = true, etaSeconds = 300 }).line, 'City Tow is on the way. About 5 min away.')
    T.eq(S.statusText({ status = 'accepted', driverName = 'Ana Ruiz' }).line, 'Ana Ruiz accepted and is on the way.')
    T.eq(S.statusText({ status = 'arrived', driverName = 'Ana Ruiz' }).line, 'Ana Ruiz has arrived.')
    T.eq(S.statusText({ status = 'hooked', destination = 'LSPD Impound' }).line, 'Your vehicle is on the truck, heading to LSPD Impound.')
    T.eq(S.statusText({ status = 'hooked' }).line, 'Your vehicle is on the truck.')
    T.eq(S.statusText({ status = 'delivered', destination = 'LSPD Impound' }).line, 'Delivered to LSPD Impound.')
    T.eq(S.statusText({ status = 'cancelled', reason = 'vehicle_gone' }).line, 'Cancelled: the vehicle was no longer there.')
    T.eq(S.statusText({ status = 'cancelled' }).line, 'Request cancelled.')
    T.eq(S.statusText({ status = 'queued' }).title, 'City Services')
end)

T.test('reasonText covers every reason the tow script can return', function()
    local reasons = { 'no_player', 'bad_request', 'bad_kind', 'open_request', 'cooldown', 'not_allowed',
        'bad_coords', 'too_far', 'no_vehicle', 'no_funds', 'queue_full', 'no_request', 'too_late',
        'no_offer', 'expired', 'gone', 'unavailable' }
    for i = 1, #reasons do
        local text = S.reasonText(reasons[i])
        T.truthy(type(text) == 'string' and #text > 10, reasons[i])
        T.truthy(text ~= S.reasonText('something_unknown'), reasons[i] .. ' has its own sentence')
    end
    T.eq(S.reasonText('something_unknown'), 'That did not work. Try again in a moment.')
end)
