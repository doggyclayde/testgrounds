AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "testhud.lua" )

include( "shared.lua" )

util.AddNetworkString( "Role_Assigned" )
util.AddNetworkString( "Poltergeist_Throw" )
util.AddNetworkString( "Poltergeist_CooldownStatus" )
util.AddNetworkString( "Round_StateChanged" )
util.AddNetworkString( "Round_PlayerReady" )
util.AddNetworkString( "Round_ReadyStatus" )

-- I apologize if the code is so messy honestly my head is about to explode LMAO
-- I haven't organized them yet

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
    for _, ply in ipairs( player.GetAll() ) do
        ply:SetNWBool( "IsDeadSpectator", false )
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
hook.Add( "PlayerDeathThink", "Round_BlockRespawn", function( ply )
    return false
end )

hook.Add( "PlayerDeath", "Round_CheckWinCondition", function( ply, inflictor, attacker )
    if GetRoundState() != ROUND_ACTIVE then return end

    -- this timer will turn a dead player into a funny invisible ghost. TBD
    timer.Simple( 5, function()
        if not IsValid( ply ) then return end

        local deathPos = ply:GetPos()

        ply:Spawn()

        deadSpectators[ply] = true
        ply:SetMoveType( MOVETYPE_NOCLIP )
        ply:SetCollisionGroup( COLLISION_GROUP_IN_VEHICLE )
        ply:SetRenderMode( RENDERMODE_TRANSALPHA )
        ply:SetColor( Color( 255, 255, 255, 0 ) )
        ply:SetPos( deathPos + Vector( 0, 0, 10 ) )
        ply:SetHealth( 1 )

        -- They cannot interact with anyone.
        ply:StripWeapons()
        ply:SetNWBool( "IsDeadSpectator", true )
    end )

    -- win condition check
    timer.Simple( 0.2, function()
        if GetRoundState() != ROUND_ACTIVE then return end

        if GetRole( ply ) == ROLE_GHOST then
            EndRound( ROLE_EXORCIST )
            return
        end

        local aliveExorcists = 0
        for _, p in ipairs( player.GetAll() ) do
            if GetRole( p ) == ROLE_EXORCIST and not deadSpectators[p] then
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

net.Receive( "Poltergeist_Throw", function( len, ply )
    if GetRole( ply ) != ROLE_GHOST then return end
    if GetRoundState() != ROUND_ACTIVE then return end

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

hook.Add( "CreateEntityRagdoll", "Round_SuppressServerRagdoll", function( ply, ragdoll )
    if GetRoundState() == ROUND_ACTIVE then
        ragdoll:Remove()
    end
end )