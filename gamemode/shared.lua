GM.Name = "testgrounds"
GM.Author = "DoggyClayde"
GM.Email = "N/A"
GM.Website = "N/A"
-- DeriveGamemode is temporary for my own sake.
DeriveGamemode( "sandbox" )

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

-- !! CONFIGS HERE BELOW
-- sanity list
SANITY_MAX          = 100
SANITY_HUNT_THRESH  = 65   -- ghost can hunt below this average
SANITY_EXORCISM_MIN = 10   -- exorcism penalty below this

SCENE_BASELINE      = 1.0  -- passive drain
SCENE_ACTIVE        = 2.5  -- ghost doing things
SCENE_HUNT          = 5.0  -- hunt in progress

function GM:Initialize()
    -- stuff
end