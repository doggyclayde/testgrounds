GM.Name = "testgrounds"
GM.Author = "DoggyClayde"
GM.Email = "N/A"
GM.Website = "N/A"
-- DeriveGamemode is temporary for my own sake.
DeriveGamemode( "sandbox" )

include( "config.lua" )
-- Do not edit these or I will be confused af
-- role list
ROLE_NONE     = 0
ROLE_GHOST    = 1
ROLE_EXORCIST = 2

-- round list
ROUND_WAITING  = 0
ROUND_STARTING = 1
ROUND_ACTIVE   = 2
ROUND_END      = 3

-- ghost types
GHOST_TYPE_NONE        = 0
GHOST_TYPE_POLTERGEIST = 1
GHOST_TYPE_REVENANT    = 2

-- sanity constants pulled from config
SANITY_MAX          = CONFIG.SANITY_MAX
SANITY_HUNT_THRESH  = CONFIG.SANITY_HUNT_THRESH
SANITY_EXORCISM_MIN = CONFIG.SANITY_EXORCISM_MIN

function GM:Initialize()
    -- stuff
end