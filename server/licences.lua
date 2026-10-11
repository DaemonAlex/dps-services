--[[
    dps-services server/licences.lua
    The licence office. Hands out a test, marks it, takes the fee and issues
    the licence into the character's Qbox metadata (licences.<id> = true), next
    to the driver and weapon licences police already see. The answers never
    leave the server: the page only ever gets the question sheet.
]]

LicenceBanks = LicenceBanks or {} -- licence id -> questions, from server/banks/*.lua

local LC = Config.Licences
local Open = {}     -- source -> { id, served, startedAt }
local Issuing = {}  -- source -> true while a payment is in flight

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS dps_licence_tests (
            citizenid VARCHAR(50) NOT NULL,
            licence VARCHAR(32) NOT NULL,
            attempts INT NOT NULL DEFAULT 0,
            best_score INT NOT NULL DEFAULT 0,
            last_fail_at INT NULL,
            passed_at INT NULL,
            issued_at INT NULL,
            PRIMARY KEY (citizenid, licence)
        )
    ]])
end)

local function getPlayer(source)
    return exports.qbx_core:GetPlayer(source)
end

local function heldBy(player)
    local l = player and player.PlayerData.metadata and player.PlayerData.metadata.licences
    return type(l) == 'table' and l or {}
end

local function record(cid, id)
    local row = MySQL.single.await(
        'SELECT attempts, best_score, last_fail_at, passed_at, issued_at FROM dps_licence_tests WHERE citizenid = ? AND licence = ?',
        { cid, id })
    if not row then return nil end
    return { attempts = row.attempts, best = row.best_score, lastFailAt = row.last_fail_at,
             passedAt = row.passed_at, issuedAt = row.issued_at }
end

--- What the licence rules need to know besides the licences held: the
--- trucker career level from the trucker script's own table (0 if none).
local function ctxFor(cid)
    local ok, level = pcall(function()
        return MySQL.scalar.await('SELECT level FROM trucker_players WHERE citizenid = ?', { cid })
    end)
    return { truckerLevel = ok and tonumber(level) or 0 }
end

local function bankFor(id)
    local bank = LicenceBanks[id]
    return type(bank) == 'table' and bank or {}
end

--- One row per licence for the Licences tab.
local function listFor(source)
    local player = getPlayer(source)
    if not player then return {} end
    local have = heldBy(player)
    local cid = player.PlayerData.citizenid
    local now = os.time()
    local ctx = ctxFor(cid)
    local rows = {}
    for id, row in pairs(LC.list) do
        local rec = record(cid, id)
        local ok, reason = Licences.canTake(have, id, ctx)
        rows[#rows + 1] = {
            id = id, label = row.label, group = row.group, fee = row.fee,
            questions = row.questions, pass = row.pass,
            truckerLevel = row.truckerLevel, myTruckerLevel = ctx.truckerLevel,
            held = have[id] == true,
            passed = rec ~= nil and rec.passedAt ~= nil and have[id] ~= true,
            waitSec = Licences.waitLeft(rec, now),
            canTake = ok, reason = reason,
            ready = #bankFor(id) >= row.questions,
        }
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
end

lib.callback.register('dps-services:licences:list', function(source)
    return listFor(source)
end)

lib.callback.register('dps-services:licences:start', function(source, id)
    local row = LC.list[id]
    local player = getPlayer(source)
    if not row or not player then return { ok = false, reason = 'unknown' } end
    local ok, reason = Licences.canTake(heldBy(player), id, ctxFor(player.PlayerData.citizenid))
    if not ok then return { ok = false, reason = reason } end
    local rec = record(player.PlayerData.citizenid, id)
    if rec and rec.passedAt then return { ok = false, reason = 'already_passed' } end
    local wait = Licences.waitLeft(rec, os.time())
    if wait > 0 then return { ok = false, reason = 'wait', waitSec = wait } end
    local served, sheet = Licences.pick(bankFor(id), row.questions)
    if not served then return { ok = false, reason = 'not_ready' } end
    Open[source] = { id = id, served = served, startedAt = os.time() }
    return { ok = true, id = id, label = row.label, pass = row.pass, sheet = sheet }
end)

lib.callback.register('dps-services:licences:submit', function(source, answers)
    local open = Open[source]
    Open[source] = nil
    if not open then return { ok = false, reason = 'no_test' } end
    if os.time() - open.startedAt > LC.testTimeoutSec then return { ok = false, reason = 'timed_out' } end
    local player = getPlayer(source)
    if not player then return { ok = false, reason = 'unknown' } end
    local row = LC.list[open.id]
    local score, passed = Licences.mark(open.served, answers, row.pass)
    local now = os.time()
    -- Two statements, so no parameter is ever nil (a nil in the list can
    -- shift every value after it).
    local column = passed and 'passed_at' or 'last_fail_at'
    MySQL.insert.await(([[
        INSERT INTO dps_licence_tests (citizenid, licence, attempts, best_score, %s)
        VALUES (?, ?, 1, ?, ?)
        ON DUPLICATE KEY UPDATE attempts = attempts + 1,
            best_score = GREATEST(best_score, VALUES(best_score)), %s = VALUES(%s)
    ]]):format(column, column, column), { player.PlayerData.citizenid, open.id, score, now })
    return { ok = true, id = open.id, score = score, total = #open.served, pass = row.pass,
             passed = passed, fee = row.fee, waitSec = passed and 0 or LC.retrySec }
end)

lib.callback.register('dps-services:licences:pay', function(source, id)
    local row = LC.list[id]
    local player = getPlayer(source)
    if not row or not player then return { ok = false, reason = 'unknown' } end
    if Issuing[source] then return { ok = false, reason = 'busy' } end
    Issuing[source] = true
    local result = (function()
        local have = heldBy(player)
        if have[id] == true then return { ok = false, reason = 'already_held' } end
        local cid = player.PlayerData.citizenid
        local ok, reason = Licences.canTake(have, id, ctxFor(cid)) -- still holds what it needs (police may have taken the DL)
        if not ok then return { ok = false, reason = reason } end
        local rec = record(cid, id)
        if not rec or not rec.passedAt then return { ok = false, reason = 'not_passed' } end
        if not player.Functions.RemoveMoney('bank', row.fee, 'licence-' .. id) then
            return { ok = false, reason = 'no_money' }
        end
        have[id] = true
        player.Functions.SetMetaData('licences', have)
        MySQL.update.await('UPDATE dps_licence_tests SET issued_at = ? WHERE citizenid = ? AND licence = ?',
            { os.time(), cid, id })
        return { ok = true, id = id, label = row.label, fee = row.fee }
    end)()
    Issuing[source] = nil
    return result
end)

AddEventHandler('playerDropped', function()
    Open[source] = nil
    Issuing[source] = nil
end)

--- Does this online player hold the licence? cdl_a also counts as cdl_b.
exports('HasLicence', function(source, id)
    return Licences.holds(heldBy(getPlayer(source)), id)
end)

--- Does this online player hold every licence in the list?
exports('HasLicences', function(source, ids)
    return Licences.holdsAll(heldBy(getPlayer(source)), ids)
end)

RegisterCommand('licencedebug', function(source)
    if source ~= 0 then return end
    local ids = {}
    for id in pairs(LC.list) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local row = LC.list[id]
        print(('[licencedebug] %-17s fee=%-5d test=%d/%d bank=%d %s'):format(
            id, row.fee, row.pass, row.questions, #bankFor(id),
            #bankFor(id) >= row.questions and 'ready' or 'NO QUESTIONS YET'))
    end
    local n = MySQL.scalar.await('SELECT COUNT(*) FROM dps_licence_tests')
    print(('[licencedebug] %d test records'):format(n or 0))
end, true)
