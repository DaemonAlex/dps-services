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
    ok, reason = S.cleanRequest('repair', { netId = 12, plate = 'ABC', coords = { x = 1, y = 'two', z = 3 } })
    T.falsy(ok); T.eq(reason, 'bad_coords')
end)

T.test('cleanRequest requires a numeric netId', function()
    local ok, reason = S.cleanRequest('repair', { plate = 'ABC', coords = { x = 1, y = 2, z = 3 } })
    T.falsy(ok); T.eq(reason, 'no_vehicle')
    ok, reason = S.cleanRequest('repair', { netId = 'abc', plate = 'ABC', coords = { x = 1, y = 2, z = 3 } })
    T.falsy(ok); T.eq(reason, 'no_vehicle')
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
    T.eq(S.statusText({ status = 'arrived', driverName = 'City Tow', cityTow = true }).line, 'City Tow has arrived. Leave the vehicle empty.')
    T.eq(S.statusText({ status = 'cancelled', reason = 'vehicle_gone', fee = 200 }).line, 'Cancelled: the vehicle was no longer there. Nothing was charged.')
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

T.test('reasonText covers not_owner; statusText covers the City Tow cancel reasons', function()
    T.eq(S.reasonText('not_owner'), 'A repair tow is for your own vehicle. This one is not registered to you.')
    T.truthy(S.reasonText('not_owner') ~= S.reasonText('something_unknown'), 'not_owner has its own sentence')

    local vehicleGone = S.statusText({ status = 'cancelled', reason = 'vehicle_gone', fee = 200 }).line
    local vehicleOccupied = S.statusText({ status = 'cancelled', reason = 'vehicle_occupied', fee = 200 }).line
    local noDestination = S.statusText({ status = 'cancelled', reason = 'no_destination', fee = 200 }).line
    T.eq(vehicleGone, 'Cancelled: the vehicle was no longer there. Nothing was charged.')
    T.eq(vehicleOccupied, 'Cancelled: someone was in the vehicle. Nothing was charged.')
    T.eq(noDestination, 'Cancelled: no yard could take the vehicle. Nothing was charged.')
    T.truthy(vehicleGone ~= vehicleOccupied, 'vehicle_gone differs from vehicle_occupied')
    T.truthy(vehicleGone ~= noDestination, 'vehicle_gone differs from no_destination')
    T.truthy(vehicleOccupied ~= noDestination, 'vehicle_occupied differs from no_destination')
    T.truthy(vehicleGone ~= 'Request cancelled.', 'vehicle_gone differs from the plain fallback')
    T.truthy(vehicleOccupied ~= 'Request cancelled.', 'vehicle_occupied differs from the plain fallback')
    T.truthy(noDestination ~= 'Request cancelled.', 'no_destination differs from the plain fallback')
end)

T.test('delivered names the place the owner can collect the vehicle from', function()
    T.eq(S.statusText({ status = 'delivered', kind = 'repair', destination = 'LS Customs Burton', handoff = 'Legion Square garage' }).line,
        'Delivered. Your vehicle is in the Legion Square garage.')
    T.eq(S.statusText({ status = 'delivered', kind = 'impound', destination = 'LSPD Impound', handoff = 'Impound A' }).line,
        'Delivered to Impound A.')
    -- no hand-off (an unowned vehicle): the old sentence stands
    T.eq(S.statusText({ status = 'delivered', kind = 'repair', destination = 'LS Customs Burton' }).line,
        'Delivered to LS Customs Burton.')
end)

T.test('feeLine says what happened to the money, and never lies about it', function()
    T.eq(S.feeLine({ fee = 200 }), 'Nothing was charged.')
    T.eq(S.feeLine({ fee = 200, feeCharged = true, refund = 'refunded' }), 'Your $200 was paid back.')
    T.eq(S.feeLine({ fee = 200, refund = 'owed' }), 'Your $200 will be paid back when you next open the app.')
    T.eq(S.feeLine({ fee = 200, feeCharged = true }), nil)
    T.eq(S.feeLine({ fee = 0 }), nil)
    T.eq(S.feeLine(nil), nil)
end)

T.test('a cancelled request tells the truth about the fee', function()
    T.eq(S.statusText({ status = 'cancelled', reason = 'vehicle_gone', fee = 200, refund = 'refunded' }).line,
        'Cancelled: the vehicle was no longer there. Your $200 was paid back.')
    T.eq(S.statusText({ status = 'cancelled', reason = 'vehicle_gone', fee = 200, refund = 'owed' }).line,
        'Cancelled: the vehicle was no longer there. Your $200 will be paid back when you next open the app.')
    T.eq(S.statusText({ status = 'cancelled', reason = 'vehicle_occupied', fee = 0 }).line,
        'Cancelled: someone was in the vehicle.')
end)

T.test('pickPhoto: our own image or nil', function()
    T.eq(S.pickPhoto({ image = 'https://a/x.webp', fallbacks = { 'https://b/y.webp' } }), 'https://a/x.webp')
    T.eq(S.pickPhoto({ fallbacks = { 'https://b/y.webp', 'https://c/z.png' } }), nil)
    T.eq(S.pickPhoto({ image = '', fallbacks = {} }), nil)
    T.eq(S.pickPhoto(nil), nil)
    T.eq(S.pickPhoto('text'), nil)
    T.eq(S.pickPhoto({ image = 12 }), nil)
    T.eq(S.pickPhoto({ image = 'javascript:alert(1)' }), nil)
    T.eq(S.pickPhoto({ image = 'http://a/x.webp' }), nil)
end)
