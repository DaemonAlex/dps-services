-- Every licence has a question bank at least three times its test size, and
-- every question has four options and a valid answer.
Config = Config or {}
dofile('config_licences.lua')
LicenceBanks = nil
local files = {}
local pipe = io.popen('ls server/banks/bank_*.lua')
for line in pipe:lines() do files[#files + 1] = line end
pipe:close()
for _, f in ipairs(files) do dofile(f) end

T.test('every licence has a big enough bank', function()
    for id, row in pairs(Config.Licences.list) do
        local bank = LicenceBanks[id]
        T.truthy(bank, 'bank for ' .. id)
        T.truthy(#bank >= row.questions * 3, id .. ' bank ' .. #bank .. ' < 3x ' .. row.questions)
    end
end)

T.test('every question has 4 options, a valid answer and a unique id', function()
    local seen = {}
    for id, bank in pairs(LicenceBanks) do
        for _, q in ipairs(bank) do
            T.eq(#q.options, 4, q.id .. ' options')
            T.truthy(q.answer >= 1 and q.answer <= 4, q.id .. ' answer')
            T.falsy(seen[q.id], 'duplicate id ' .. q.id); seen[q.id] = true
        end
    end
end)
