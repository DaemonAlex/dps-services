--[[
    dps-services config_licences.lua
    City work licences, agreed with Damon 2026-10-11 (pages 3yCHJycK, Fsiz1g5j).
    Taken and paid for in the City Services app; stored with the driver and
    weapon licences in the character's Qbox metadata (licences.<id> = true).

    questions  how many a test serves     pass  how many must be right
    fee        paid from the bank when the licence is issued
    needs      licences that must be held before the test (any one of each
               inner list; 'cdl_b' is also met by 'cdl_a')
]]

Config.Licences = {
    retrySec = 30 * 60,      -- wait after a failed test
    testTimeoutSec = 30 * 60, -- an unanswered test is dropped after this

    list = {
        cdl_b = { label = 'Commercial B', group = 'commercial', questions = 20, pass = 16, fee = 1500,
            needs = { { 'driver' } } },
        cdl_a = { label = 'Commercial A', group = 'commercial', questions = 20, pass = 16, fee = 3000,
            needs = { { 'driver' } } },
        tow = { label = 'Tow', group = 'commercial', questions = 10, pass = 8, fee = 750,
            needs = { { 'driver' }, { 'cdl_b' } } },
        hazmat = { label = 'Hazmat', group = 'commercial', questions = 10, pass = 8, fee = 1000,
            needs = { { 'driver' }, { 'cdl_a' } } },
        passenger = { label = 'Passenger', group = 'commercial', questions = 10, pass = 8, fee = 500,
            needs = { { 'driver' }, { 'cdl_b' } } },

        taxi = { label = 'Taxi (hack)', group = 'passenger', questions = 10, pass = 8, fee = 500,
            needs = { { 'driver' } } },
        chauffeur = { label = 'Chauffeur', group = 'passenger', questions = 10, pass = 8, fee = 1000,
            needs = { { 'driver' }, { 'taxi' } } },

        pilot_private = { label = 'Private Pilot', group = 'pilot', questions = 20, pass = 16, fee = 1500,
            needs = { { 'driver' } } },
        pilot_commercial = { label = 'Commercial Pilot', group = 'pilot', questions = 20, pass = 16, fee = 3000,
            needs = { { 'driver' }, { 'pilot_private' } } },
        pilot_atp = { label = 'Airline Transport Pilot', group = 'pilot', questions = 20, pass = 16, fee = 5000,
            needs = { { 'driver' }, { 'pilot_commercial' } } },
        heli = { label = 'Helicopter', group = 'pilot', questions = 10, pass = 8, fee = 1500,
            needs = { { 'driver' }, { 'pilot_private' } } },
    },
}
