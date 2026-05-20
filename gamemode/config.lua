-- ── CONFIGURATIONS ────────────────────────────────────────
-- Edit values here to adjust difficulty and balance.
-- All distance values are in GMod units.
-- All speed values are in GMod units per second.
-- ──────────────────────────────────────────────────────────

CONFIG = {}

-- ── PLAYER SPEEDS ─────────────────────────────────────────
CONFIG.EXORCIST_WALK_SPEED  = 160   -- 200 default * 0.8
CONFIG.EXORCIST_RUN_SPEED   = 320   -- 400 default * 0.8

CONFIG.GHOST_WALK_SPEED = math.floor( CONFIG.EXORCIST_WALK_SPEED * 1.5 )  -- 240
CONFIG.GHOST_RUN_SPEED  = math.floor( CONFIG.EXORCIST_RUN_SPEED * 1.5 )   -- 480

-- ── HUNT SPEEDS ───────────────────────────────────────────
CONFIG.HUNT_BASE_SPEED      = 112   -- ghost base hunt speed (30% slower than exorcist)
CONFIG.HUNT_LOS_SPEED       = 480   -- ghost LOS speed (50% faster than exorcist run)
CONFIG.HUNT_DURATION        = 60    -- seconds
CONFIG.HUNT_COOLDOWN        = 75    -- seconds (1m 15s)
CONFIG.HUNT_SANITY_THRESH   = 65    -- average sanity % required to hunt
CONFIG.HUNT_LOS_RANGE       = 600   -- units, max distance for LOS detection

-- ── REVENANT SPRINT ───────────────────────────────────────
CONFIG.REVENANT_SPRINT_SPEED    = 512   -- 60% faster than exorcist run
CONFIG.REVENANT_SPRINT_DURATION = 7     -- seconds
CONFIG.REVENANT_SPRINT_REGEN    = 7     -- seconds to regenerate

-- ── SANITY ────────────────────────────────────────────────
CONFIG.SANITY_MAX               = 100
CONFIG.SANITY_HUNT_THRESH       = 65    -- hunt becomes available below this
CONFIG.SANITY_EXORCISM_MIN      = 10    -- exorcism penalty below this
CONFIG.SANITY_GHOST_PROXIMITY   = 300   -- units, passive drain near ghost
CONFIG.SANITY_GHOST_DRAIN_MIN   = 0.1   -- drain per second at max distance
CONFIG.SANITY_GHOST_DRAIN_MAX   = 0.1   -- drain per second at min distance
CONFIG.SANITY_HUNT_PROXIMITY    = 600   -- units, drain near hunting ghost
CONFIG.SANITY_HUNT_DRAIN_MIN    = 0.2   -- drain per second at max hunt distance
CONFIG.SANITY_HUNT_DRAIN_MAX    = 0.9   -- drain per second at min hunt distance
CONFIG.SANITY_THROW_DEDUCT      = 5     -- flat % deducted on successful throw

-- ── POLTERGEIST THROW ─────────────────────────────────────
CONFIG.THROW_RADIUS             = 300
CONFIG.THROW_FORCE              = 80000
CONFIG.THROW_COOLDOWN           = 8