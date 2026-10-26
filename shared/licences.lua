--[[
    dps-services shared/licences.lua
    Pure licence rules. No natives, so tests/ can run them under plain lua5.4.
]]

Licences = {}

-- A higher licence that also counts as a lower one.
local COVERS = { cdl_b = { 'cdl_a' } }

--- Does this set of licences (Qbox metadata `licences`) count as holding id?
function Licences.holds(have, id)
    if type(have) ~= 'table' then return false end
    if have[id] == true then return true end
    for _, higher in ipairs(COVERS[id] or {}) do
        if have[higher] == true then return true end
    end
    return false
end

function Licences.holdsAll(have, ids)
    for _, id in ipairs(ids or {}) do
        if not Licences.holds(have, id) then return false end
    end
    return true
end

--- May someone holding `have` sit the test for id?
--- ctx.truckerLevel: their trucker career level (0 when they have none).
--- @return boolean ok, string|nil reason
function Licences.canTake(have, id, ctx)
    local row = Config.Licences.list[id]
    if not row then return false, 'unknown' end
    have = type(have) == 'table' and have or {}
    if have[id] == true then return false, 'already_held' end
    for _, anyOf in ipairs(row.needs or {}) do
        local met = false
        for _, need in ipairs(anyOf) do
            if Licences.holds(have, need) then met = true break end
        end
        if not met then return false, 'need_' .. anyOf[1] end
    end
    if row.truckerLevel and ((ctx and ctx.truckerLevel) or 0) < row.truckerLevel then
        return false, 'need_trucker_level'
    end
    return true
end

--- A trucker delivered a load: 'unlicensed' when it was hazardous and they
--- hold no Hazmat licence (the pay is taken back and police are told).
function Licences.hazmatVerdict(hazardous, have)
    if not hazardous then return 'ok' end
    return Licences.holds(have, 'hazmat') and 'ok' or 'unlicensed'
end

--- Draw n questions from a bank, shuffling each one's options.
--- `served` keeps the answer (server only); `sheet` is what the player sees.
--- @param rand function(m, n) like math.random
function Licences.pick(bank, n, rand)
    if type(bank) ~= 'table' or #bank < n then return nil end
    rand = rand or math.random
    local order = {}
    for i = 1, #bank do order[i] = i end
    for i = #order, 2, -1 do
        local j = rand(1, i)
        order[i], order[j] = order[j], order[i]
    end
    local served, sheet = {}, {}
    for k = 1, n do
        local q = bank[order[k]]
        local idx = {}
        for i = 1, #q.options do idx[i] = i end
        for i = #idx, 2, -1 do
            local j = rand(1, i)
            idx[i], idx[j] = idx[j], idx[i]
        end
        local options, answer = {}, nil
        for pos, from in ipairs(idx) do
            options[pos] = q.options[from]
            if from == q.answer then answer = pos end
        end
        served[k] = { id = q.id, answer = answer }
        sheet[k] = { text = q.text, image = q.image, options = options }
    end
    return served, sheet
end

--- @return integer score, boolean passed
function Licences.mark(served, answers, passMark)
    local score = 0
    if type(answers) == 'table' then
        for i, q in ipairs(served) do
            if tonumber(answers[i]) == q.answer then score = score + 1 end
        end
    end
    return score, score >= passMark
end

--- Seconds until another try is allowed. `record` is the stored row for this
--- player and licence (lastFailAt in os.time seconds), or nil.
function Licences.waitLeft(record, now)
    if type(record) ~= 'table' or not record.lastFailAt then return 0 end
    local left = record.lastFailAt + Config.Licences.retrySec - now
    return left > 0 and left or 0
end
