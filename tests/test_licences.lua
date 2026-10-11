-- City work licences (Damon 2026-10-11): the catalogue, who may sit which
-- test, marking, the retry wait, and what counts as holding a licence.
Config = Config or {}
dofile('config_licences.lua')
dofile('shared/licences.lua')
local L = Licences

T.test('the eleven licences carry the agreed tests and fees', function()
    local want = {
        cdl_b            = { 20, 16, 1500 },
        cdl_a            = { 20, 16, 3000 },
        tow              = { 10, 8, 750 },
        hazmat           = { 10, 8, 1000 },
        passenger        = { 10, 8, 500 },
        taxi             = { 10, 8, 500 },
        chauffeur        = { 10, 8, 1000 },
        pilot_private    = { 20, 16, 1500 },
        pilot_commercial = { 20, 16, 3000 },
        pilot_atp        = { 20, 16, 5000 },
        heli             = { 10, 8, 1500 },
    }
    local count = 0
    for id, row in pairs(Config.Licences.list) do
        count = count + 1
        local w = want[id]
        T.truthy(w, 'unexpected licence ' .. id)
        T.eq(row.questions, w[1], id .. ' questions')
        T.eq(row.pass, w[2], id .. ' pass')
        T.eq(row.fee, w[3], id .. ' fee')
        T.truthy(type(row.label) == 'string' and row.label ~= '', id .. ' label')
    end
    T.eq(count, 11)
    T.eq(Config.Licences.retrySec, 1800)
end)

T.test('every licence needs a driver licence first', function()
    local ok, reason = L.canTake({}, 'taxi')
    T.falsy(ok); T.eq(reason, 'need_driver')
    ok = L.canTake({ driver = true }, 'taxi')
    T.truthy(ok)
end)

T.test('add-ons and levels need what sits under them', function()
    local dl = { driver = true }
    T.falsy(L.canTake(dl, 'tow'))
    T.truthy(L.canTake({ driver = true, cdl_b = true }, 'tow'))
    T.truthy(L.canTake({ driver = true, cdl_a = true }, 'tow'), 'A counts as B')
    T.truthy(L.canTake({ driver = true, cdl_a = true }, 'passenger'))
    T.falsy(L.canTake({ driver = true, cdl_b = true }, 'hazmat'), 'hazmat needs A')
    T.truthy(L.canTake({ driver = true, cdl_a = true }, 'hazmat'))
    T.falsy(L.canTake(dl, 'chauffeur'))
    T.truthy(L.canTake({ driver = true, taxi = true }, 'chauffeur'))
    T.truthy(L.canTake(dl, 'pilot_private'))
    T.falsy(L.canTake(dl, 'pilot_commercial'))
    T.truthy(L.canTake({ driver = true, pilot_private = true }, 'pilot_commercial'))
    T.falsy(L.canTake({ driver = true, pilot_private = true }, 'pilot_atp'))
    T.truthy(L.canTake({ driver = true, pilot_private = true, pilot_commercial = true }, 'pilot_atp'))
    T.truthy(L.canTake({ driver = true, pilot_private = true }, 'heli'))
end)

T.test('no test for a licence already held or one that does not exist', function()
    local ok, reason = L.canTake({ driver = true, taxi = true }, 'taxi')
    T.falsy(ok); T.eq(reason, 'already_held')
    ok, reason = L.canTake({ driver = true }, 'spaceship')
    T.falsy(ok); T.eq(reason, 'unknown')
end)

T.test('holds: A covers B, the rest must be held themselves', function()
    T.truthy(L.holds({ cdl_a = true }, 'cdl_b'))
    T.truthy(L.holds({ cdl_b = true }, 'cdl_b'))
    T.falsy(L.holds({ cdl_b = true }, 'cdl_a'))
    T.falsy(L.holds({ cdl_a = true }, 'tow'))
    T.falsy(L.holds(nil, 'cdl_b'))
    T.truthy(L.holdsAll({ driver = true, cdl_a = true, passenger = true }, { 'driver', 'cdl_b', 'passenger' }))
    T.falsy(L.holdsAll({ driver = true, cdl_b = true }, { 'driver', 'cdl_b', 'passenger' }))
end)

local function bank(n)
    local b = {}
    for i = 1, n do
        b[i] = { id = 'q' .. i, text = 'Q' .. i, options = { 'right ' .. i, 'wrong a', 'wrong b', 'wrong c' }, answer = 1 }
    end
    return b
end

-- Deterministic stand-in for math.random(m, n).
local function seq()
    local s = 7
    return function(m, n)
        s = (s * 1103515245 + 12345) % 2147483648
        return m + (s % (n - m + 1))
    end
end

T.test('pick serves n different questions, options shuffled, no answers sent', function()
    local served, sheet = L.pick(bank(30), 10, seq())
    T.eq(#served, 10); T.eq(#sheet, 10)
    local seen = {}
    for i = 1, 10 do
        T.falsy(seen[served[i].id], 'repeated question'); seen[served[i].id] = true
        T.eq(sheet[i].answer, nil, 'answer must not reach the client')
        T.eq(#sheet[i].options, 4)
        -- the correct option text is wherever served says it is
        T.eq(sheet[i].options[served[i].answer], 'right ' .. served[i].id:sub(2))
    end
end)

T.test('pick refuses a bank smaller than the test', function()
    local served = L.pick(bank(5), 10, seq())
    T.eq(served, nil)
end)

T.test('mark counts right answers against the pass mark', function()
    local served = { { answer = 2 }, { answer = 1 }, { answer = 4 }, { answer = 3 } }
    local score, passed = L.mark(served, { 2, 1, 4, 1 }, 3)
    T.eq(score, 3); T.truthy(passed)
    score, passed = L.mark(served, { 2, 2, 2, 2 }, 3)
    T.eq(score, 1); T.falsy(passed)
    score, passed = L.mark(served, { '2', nil, 4 }, 3)
    T.eq(score, 2); T.falsy(passed)
    score, passed = L.mark(served, 'junk', 1)
    T.eq(score, 0); T.falsy(passed)
end)

T.test('retry wait: 30 minutes after a fail, none after a pass', function()
    T.eq(L.waitLeft(nil, 1000), 0)
    T.eq(L.waitLeft({ lastFailAt = 1000 }, 1000), 1800)
    T.eq(L.waitLeft({ lastFailAt = 1000 }, 2800), 0)
    T.eq(L.waitLeft({ lastFailAt = 1000 }, 2000), 800)
end)
