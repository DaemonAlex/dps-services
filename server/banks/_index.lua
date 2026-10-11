--[[
    dps-services server/banks/
    One file per licence: LicenceBanks.<id> = { { id, text, options = {4}, answer = n, image? }, ... }
    Server only, so the answers never reach a player. Written in step 2 and read
    by Damon before they go live.
]]
LicenceBanks = LicenceBanks or {}
