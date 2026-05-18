AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "testhud.lua" )
AddCSLuaFile( "ragdoll.lua" )

include( "shared.lua" )
include( "ragdoll.lua" )

util.AddNetworkString( "Role_Assigned" )
util.AddNetworkString( "Poltergeist_Throw" )
util.AddNetworkString( "Poltergeist_CooldownStatus" )
util.AddNetworkString( "Round_StateChanged" )
util.AddNetworkString( "Round_PlayerReady" )
util.AddNetworkString( "Round_ReadyStatus" )
util.AddNetworkString( "Player_BecomingSpectator" )
util.AddNetworkString( "Sanity_Update" )

-- I apologize if the code is so messy honestly my head is about to explode LMAO
-- I haven't organized them yet

-- ── SCENE ACTIVITY ────────────────────────────────────────
local sceneActivity  = SCENE_BASELINE
local sceneTargetActivity = SCENE_BASELINE

local function SetSceneActivity( level )
    sceneTargetActivity = level
end

-- smoothly lerp scene activity toward target each tick
timer.Create( "Scene_ActivityDecay", 1, 0, function()
    if GetRoundState() != ROUND_ACTIVE then return end
    sceneActivity = math.Clamp(
        Lerp( 0.3, sceneActivity, sceneTargetActivity ),
        SCENE_BASELINE,
        SCENE_HUNT
    )
    -- decay target back to baseline over time
    sceneTargetActivity = math.max( sceneTargetActivity - 0.1, SCENE_BASELINE )
end )

-- ── SANITY FORMULA ────────────────────────────────────────
local function CalculateSanityDrain( ply )
    local hpRatio = ply:Health() / ply:GetMaxHealth()
    return sceneActivity * hpRatio
end

-- ── AVERAGE SANITY ────────────────────────────────────────
local function GetAverageSanity()
    local total = 0
    local count = 0

    for _, ply in ipairs( player.GetAll() ) do
        if GetRole( ply ) != ROLE_EXORCIST then continue end
        if deadSpectators[ply] then continue end
        if not ply:Alive() then continue end
        total = total + ply:GetNWFloat( "Sanity", SANITY_MAX )
        count = count + 1
    end

    if count == 0 then return 100 end
    return total / count
end

function GetAverageSanity() return GetAverageSanity() end

-- ── DRAIN TICK ────────────────────────────────────────────
timer.Create( "Sanity_DrainTick", 1, 0, function()
    if GetRoundState() != ROUND_ACTIVE then return end

    for _, ply in ipairs( player.GetAll() ) do
        if not ply:Alive() then continue end
        if GetRole( ply ) != ROLE_EXORCIST then continue end
        if deadSpectators[ply] then continue end

        local current   = ply:GetNWFloat( "Sanity", SANITY_MAX )
        local drain     = CalculateSanityDrain( ply )
        local newSanity = math.Clamp( current - drain, 0, SANITY_MAX )

        ply:SetNWFloat( "Sanity", newSanity )
    end
end )

-- ── RESET SANITY ON ROUND START ───────────────────────────
local function ResetSanity()
    sceneActivity       = SCENE_BASELINE
    sceneTargetActivity = SCENE_BASELINE

    for _, ply in ipairs( player.GetAll() ) do
        ply:SetNWFloat( "Sanity", SANITY_MAX )
    end
end

-- ── SCENE ACTIVITY TRIGGERS ───────────────────────────────
-- poltergeist throw spikes activity
local originalThrowReceive = nil
net.Receive( "Poltergeist_Throw", function( len, ply )
    if GetRole( ply ) != ROLE_GHOST then return end
    if GetRoundState() != ROUND_ACTIVE then return end

    -- spike scene activity on throw
    SetSceneActivity( SCENE_ACTIVE )

    local now = CurTime()
    if cooldowns[ply] and now < cooldowns[ply] then
        local remaining = math.ceil( cooldowns[ply] - now )
        net.Start( "Poltergeist_CooldownStatus" )
            net.WriteFloat( remaining )
        net.Send( ply )
        return
    end
    cooldowns[ply] = now + THROW_COOLDOWN

    net.Start( "Poltergeist_CooldownStatus" )
        net.WriteFloat( THROW_COOLDOWN )
    net.Send( ply )

    local origin = ply:GetPos()
    local found  = ents.FindInSphere( origin, THROW_RADIUS )

    local thrown = 0
    for _, ent in ipairs( found ) do
        if not IsValid( ent ) then continue end
        if not validClasses[ent:GetClass()] then continue end

        local entPos = ent:GetPos()
        if not entPos then continue end

        local phys = ent:GetPhysicsObject()
        if not IsValid( phys ) then continue end

        local diff = entPos - origin
        if diff:LengthSqr() < 1 then continue end
        local dir = diff:GetNormalized()

        local force = math.Clamp( THROW_FORCE, 0, 120000 )
        phys:ApplyForceCenter( dir * force )
        thrown = thrown + 1
    end

    print( "[Poltergeist] Server: threw " .. thrown .. " props" )
end )

-- ROUND STATE
local roundState    = ROUND_WAITING
local readyPlayers  = {}
local deadSpectators = {}

local function SetRoundState( state )
    roundState = state
    net.Start( "Round_StateChanged" )
        net.WriteInt( state, 8 )
    net.Broadcast()
    print( "[Round] State changed to: " .. state )
end

local function GetRoundState()
    return roundState
end

local function ResetReady()
    readyPlayers = {}
    net.Start( "Round_ReadyStatus" )
        net.WriteInt( 0, 8 )
        net.WriteInt( #player.GetAll(), 8 )
    net.Broadcast()
end

local function BroadcastReadyStatus()
    local readyCount = 0
    for _ in pairs( readyPlayers ) do readyCount = readyCount + 1 end
    net.Start( "Round_ReadyStatus" )
        net.WriteInt( readyCount, 8 )
        net.WriteInt( #player.GetAll(), 8 )
    net.Broadcast()
end

-- ROLE ASSIGN
local function AssignRoles()
    local players = player.GetAll()
    if #players == 0 then return end

    for i = #players, 2, -1 do
        local j = math.random(i)
        players[i], players[j] = players[j], players[i]
    end

    for i, ply in ipairs( players ) do
        local role = i == 1 and ROLE_GHOST or ROLE_EXORCIST
        ply:SetNWInt( "Role", role )

        net.Start( "Role_Assigned" )
            net.WriteInt( role, 8 )
        net.Send( ply )

        print( "[Roles] " .. ply:Nick() .. " assigned role " .. role )
    end
end

local function GetRole( ply )
    if not IsValid( ply ) then return ROLE_NONE end
    return ply:GetNWInt( "Role", ROLE_NONE )
end

-- ROUND FLOW
local function StartRound()
    deadSpectators = {}
    ResetSanity()
    for _, ply in ipairs( player.GetAll() ) do
        ply:SetNWBool( "IsDeadSpectator", false )
        ply:SetNWBool( "PendingSpectator", false )
    end
    AssignRoles()
    SetRoundState( ROUND_ACTIVE )
    for _, ply in ipairs( player.GetAll() ) do
        ply:Spawn()
    end
end

local function EndRound( winnerRole )
    SetRoundState( ROUND_END )
    print( "[Round] Round ended. Winner role: " .. winnerRole )

    timer.Simple( 5, function()
        deadSpectators = {}
        ResetReady()
        SetRoundState( ROUND_WAITING )

        -- cleanup happens at round state 0 (ROUND_WAITING)
        -- remove player spawned props only
        for _, ent in ipairs( ents.GetAll() ) do
            if not IsValid( ent ) then continue end
            local class = ent:GetClass()

            if ( class == "prop_physics" or class == "prop_physics_multiplayer" )
            and ent:GetNWBool( "PlayerSpawned", false ) then
                ent:Remove()
                continue
            end

            if class == "prop_door_rotating" then
                ent:Fire( "Close" )
                ent:Fire( "Unlock" )
                continue
            end
        end

        -- restore all breakables
        for _, ent in ipairs( ents.GetAll() ) do
            if not IsValid( ent ) then continue end
            local class = ent:GetClass()
            if class == "func_breakable" or class == "func_breakable_surf" then
                ent:SetHealth( ent:GetMaxHealth() )
                ent:Fire( "Repair", "", 0 )
            end
        end

        for _, ply in ipairs( player.GetAll() ) do
            ply:Spawn()
        end
    end )
end

-- PLAYER_READY STATUS
net.Receive( "Round_PlayerReady", function( len, ply )
    if GetRoundState() != ROUND_WAITING then return end

    local players = player.GetAll()
    if #players < 2 then
        print( "[Round] Not enough players." )
        return
    end

    if readyPlayers[ply] then
        readyPlayers[ply] = nil
        print( "[Round] " .. ply:Nick() .. " unreadied" )
    else
        readyPlayers[ply] = true
        print( "[Round] " .. ply:Nick() .. " readied up" )
    end

    BroadcastReadyStatus()

    local readyCount = 0
    for _ in pairs( readyPlayers ) do readyCount = readyCount + 1 end

    if readyCount >= #players and #players >= 2 then
        SetRoundState( ROUND_STARTING )
        print( "[Round] All players ready. Starting in 5 seconds..." )

        timer.Simple( 5, function()
            if GetRoundState() == ROUND_STARTING then
                StartRound()
            end
        end )
    end
end )

-- DEATH & SPECTATE (broken asf)

-- !! Make spectator be able to phase through players.
-- !! client-side ragdolls still don't work genuinely dying bruh
hook.Add( "PlayerDeath", "Round_CheckWinCondition", function( ply, inflictor, attacker )
    if GetRoundState() != ROUND_ACTIVE then return end

    -- immediately flag as pending spectator so respawn is blocked
    ply:SetNWBool( "PendingSpectator", true )

    timer.Simple( 5, function()
        if not IsValid( ply ) then return end
        ply:SetNWBool( "PendingSpectator", false )

        local deathPos = ply:GetPos()

        -- tell client BEFORE spawning so it can protect the ragdoll
        net.Start( "Player_BecomingSpectator" )
        net.Send( ply )

        ply:Spawn()

        deadSpectators[ply] = true
        ply:SetNWBool( "IsDeadSpectator", true )
        ply:SetMoveType( MOVETYPE_NOCLIP )
        ply:SetCollisionGroup( COLLISION_GROUP_IN_VEHICLE )
        ply:SetRenderMode( RENDERMODE_TRANSALPHA )
        ply:SetColor( Color( 255, 255, 255, 0 ) )
        ply:SetPos( deathPos + Vector( 0, 0, 10 ) )
        ply:SetHealth( 1 )
        ply:StripWeapons()
    end )

    -- win condition unchanged
    timer.Simple( 0.2, function()
        if GetRoundState() != ROUND_ACTIVE then return end

        if GetRole( ply ) == ROLE_GHOST then
            EndRound( ROLE_EXORCIST )
            return
        end

        local aliveExorcists = 0
        for _, p in ipairs( player.GetAll() ) do
            if GetRole( p ) == ROLE_EXORCIST 
            and not deadSpectators[p]
            and not p:GetNWBool( "PendingSpectator", false ) then
                aliveExorcists = aliveExorcists + 1
            end
        end

        if aliveExorcists == 0 then
            EndRound( ROLE_GHOST )
        end
    end )
end )

-- block weapon pickup
hook.Add( "PlayerCanPickupWeapon", "Spectator_NoPickup", function( ply, wep )
    if ply:GetNWBool( "IsDeadSpectator", false ) then return false end
end )

-- block weapon switching
hook.Add( "PlayerSwitchWeapon", "Spectator_NoSwitch", function( ply, oldwep, newwep )
    if ply:GetNWBool( "IsDeadSpectator", false ) then return true end
end )

-- block attacking
hook.Add( "PlayerShouldTakeDamage", "Spectator_NoDamage", function( ply, attacker )
    if ply:GetNWBool( "IsDeadSpectator", false ) then return false end
end )

-- block dealing damage to others
hook.Add( "EntityTakeDamage", "Spectator_NoDealDamage", function( ent, dmg )
    local attacker = dmg:GetAttacker()
    if not IsValid( attacker ) then return end
    if not attacker:IsPlayer() then return end
    if attacker:GetNWBool( "IsDeadSpectator", false ) then
        dmg:SetDamage( 0 )
    end
end )
-- remove the PlayerDeathThink hook entirely
hook.Remove( "PlayerDeathThink", "Round_BlockRespawn" )

-- PLAYER SPAWN & CLEANUP (not tested)
hook.Add( "PlayerSpawn", "Round_ClearSpectate", function( ply )
    if deadSpectators[ply] then return end

    ply:SetNWBool( "IsDeadSpectator", false )
    ply:SetMoveType( MOVETYPE_WALK )
    ply:SetCollisionGroup( COLLISION_GROUP_NONE )
    ply:SetRenderMode( RENDERMODE_NORMAL )
    ply:SetColor( Color( 255, 255, 255, 255 ) )
    ply:SetHealth( ply:GetMaxHealth() )
end )

hook.Add( "PlayerFullLoad", "Round_SendStateOnJoin", function( ply )
    net.Start( "Round_StateChanged" )
        net.WriteInt( roundState, 8 )
    net.Send( ply )

    local readyCount = 0
    for _ in pairs( readyPlayers ) do readyCount = readyCount + 1 end
    net.Start( "Round_ReadyStatus" )
        net.WriteInt( readyCount, 8 )
        net.WriteInt( #player.GetAll(), 8 )
    net.Send( ply )
end )

function GM:PlayerSpawn( ply )
    if ply:GetNWBool( "IsDeadSpectator", false ) then return end

    ply:SetModel( ply:GetInfo( "cl_playermodel" ) )
    ply:SetPlayerColor( Vector( ply:GetInfo( "cl_color" ) ) )
    ply:SetGravity( .5 )
    ply:SetMaxHealth( 200 )
    ply:SetHealth( 200 )
    ply:SetRunSpeed( 1000 )
    ply:SetWalkSpeed( 300 )
    ply:Give( "weapon_crowbar" )
    ply:SetupHands()
end

-- POLTERGEIST: THROW ABILITY
local THROW_RADIUS   = 300
local THROW_FORCE    = 80000
local THROW_COOLDOWN = 8
local cooldowns      = {}

local validClasses = {
    ["prop_physics"]             = true,
    ["prop_physics_multiplayer"] = true,
    ["prop_physics_override"]    = true,
}

hook.Add( "EntityTakeDamage", "Poltergeist_PropImpactDamage", function( ent, dmg )
    if not ent:IsPlayer() then return end
    if dmg:GetDamageType() != DMG_CRUSH then return end

    local attacker = dmg:GetAttacker()
    if not IsValid( attacker ) then return end
    if not validClasses[attacker:GetClass()] then return end

    local phys = attacker:GetPhysicsObject()
    if not IsValid( phys ) then return end

    local speed  = phys:GetVelocity():Length()
    local damage = math.Clamp( speed * 0.05, 10, 80 )
    dmg:SetDamage( damage )
end )

hook.Add( "PlayerDeathThink", "Round_BlockRespawn", function( ply )
    if GetRoundState() != ROUND_ACTIVE then return end
    if ply:GetNWBool( "PendingSpectator", false ) then return false end
    if deadSpectators[ply] then return false end
end )

hook.Add( "PlayerSpawnedProp", "Round_TagSpawnedProp", function( ply, model, ent )
    ent:SetNWBool( "PlayerSpawned", true )
end )