AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "testhud.lua" )
AddCSLuaFile( "ragdoll.lua" )
AddCSLuaFile( "config.lua" )

include( "shared.lua" )
include( "config.lua" )
include( "ragdoll.lua" )

util.AddNetworkString( "Role_Assigned" )
util.AddNetworkString( "Poltergeist_Throw" )
util.AddNetworkString( "Poltergeist_CooldownStatus" )
util.AddNetworkString( "Round_StateChanged" )
util.AddNetworkString( "Round_PlayerReady" )
util.AddNetworkString( "Round_ReadyStatus" )
util.AddNetworkString( "Sanity_Update" )
util.AddNetworkString( "Player_BecomingSpectator" )
util.AddNetworkString( "Hunt_Started" )
util.AddNetworkString( "Hunt_Ended" )
util.AddNetworkString( "Hunt_LOSUpdate" )

-- globals
local roundState     = ROUND_WAITING
local readyPlayers   = {}
local deadSpectators = {}

local THROW_RADIUS   = CONFIG.THROW_RADIUS
local THROW_FORCE    = CONFIG.THROW_FORCE
local THROW_COOLDOWN = CONFIG.THROW_COOLDOWN
local cooldowns      = {}

local validClasses = {
    ["prop_physics"]             = true,
    ["prop_physics_multiplayer"] = true,
    ["prop_physics_override"]    = true,
}

function GetRoundState()
    return roundState
end

function GetRole( ply )
    if not IsValid( ply ) then return ROLE_NONE end
    return ply:GetNWInt( "Role", ROLE_NONE )
end

function GetAverageSanity()
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

local function SetRoundState( state )
    roundState = state
    net.Start( "Round_StateChanged" )
        net.WriteInt( state, 8 )
    net.Broadcast()
    print( "[Round] State changed to: " .. state )
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

local function CalculateSanityDrain( ply )
    local hpRatio = ply:Health() / ply:GetMaxHealth()
    return sceneActivity * hpRatio
end

local function ResetSanity()
    sceneActivity       = SCENE_BASELINE
    sceneTargetActivity = SCENE_BASELINE

    for _, ply in ipairs( player.GetAll() ) do
        ply:SetNWFloat( "Sanity", SANITY_MAX )
    end
end

timer.Create( "Sanity_DrainTick", 1, 0, function()
    if GetRoundState() != ROUND_ACTIVE then return end
    if huntActive then return end  -- hunt has its own drain ticker

    local ghostPos = nil
    for _, p in ipairs( player.GetAll() ) do
        if GetRole( p ) == ROLE_GHOST and p:Alive() then
            ghostPos = p:GetPos()
            break
        end
    end

    for _, ply in ipairs( player.GetAll() ) do
        if not ply:Alive() then continue end
        if GetRole( ply ) != ROLE_EXORCIST then continue end
        if deadSpectators[ply] then continue end

        local drain = 0

        if ghostPos then
            local dist     = ply:GetPos():Distance( ghostPos )
            local maxDist  = CONFIG.SANITY_GHOST_PROXIMITY
            if dist < maxDist then
                local fraction = 1 - math.Clamp( dist / maxDist, 0, 1 )
                drain = Lerp( fraction, CONFIG.SANITY_GHOST_DRAIN_MIN, CONFIG.SANITY_GHOST_DRAIN_MAX )
            end
        end

        if drain > 0 then
            local current = ply:GetNWFloat( "Sanity", SANITY_MAX )
            ply:SetNWFloat( "Sanity", math.Clamp( current - drain, 0, SANITY_MAX ) )
        end
    end
end )

local function SetGhostVisible( ghost, visible )
    if not IsValid( ghost ) then return end
    if visible then
        ghost:SetRenderMode( RENDERMODE_NORMAL )
        ghost:SetColor( Color( 255, 255, 255, 255 ) )
    else
        ghost:SetRenderMode( RENDERMODE_TRANSALPHA )
        ghost:SetColor( Color( 255, 255, 255, 0 ) )
    end
end

-- ghost phases through doors and props in stalk mode
hook.Add( "PlayerTick", "Ghost_PhaseThrough", function( ply, mv )
    if GetRole( ply ) != ROLE_GHOST then return end
    if huntActive then return end  -- solid during hunt
    ply:SetCollisionGroup( COLLISION_GROUP_PASSABLE_DOOR )
end )

-- restore collision during hunt
hook.Add( "Think", "Ghost_HuntCollision", function()
    for _, ply in ipairs( player.GetAll() ) do
        if GetRole( ply ) != ROLE_GHOST then continue end
        if huntActive then
            ply:SetCollisionGroup( COLLISION_GROUP_NONE )
        else
            ply:SetCollisionGroup( COLLISION_GROUP_PASSABLE_DOOR )
        end
    end
end )

-- Hunt system
local huntActive  = false
local huntCooldownUntil = 0

local function StartHunt( ghost )
    if huntActive then return end
    if CurTime() < huntCooldownUntil then
        print( "[Hunt] On cooldown." )
        return
    end
    if GetAverageSanity() > CONFIG.HUNT_SANITY_THRESH then
        print( "[Hunt] Sanity too high to hunt." )
        return
    end

    huntActive = true
    SetGhostVisible( ghost, true )
    print( "[Hunt] Hunt started by " .. ghost:Nick() )

    -- TBD. Can be improved.
    ghost:SetRunSpeed( CONFIG.HUNT_BASE_SPEED )
    ghost:SetWalkSpeed( CONFIG.HUNT_BASE_SPEED )

    net.Start( "Hunt_Started" )
    net.Broadcast()

    timer.Create( "Hunt_SanityDrain", 1, 0, function()
        if not huntActive then
            timer.Remove( "Hunt_SanityDrain" )
            return
        end

        local ghostPos = IsValid( ghost ) and ghost:GetPos() or nil
        if not ghostPos then return end

        for _, ply in ipairs( player.GetAll() ) do
            if not ply:Alive() then continue end
            if GetRole( ply ) != ROLE_EXORCIST then continue end
            if deadSpectators[ply] then continue end

            local dist     = ply:GetPos():Distance( ghostPos )
            local maxDist  = CONFIG.SANITY_HUNT_PROXIMITY
            local fraction = 1 - math.Clamp( dist / maxDist, 0, 1 )
            local drain    = Lerp( fraction, CONFIG.SANITY_HUNT_DRAIN_MIN, CONFIG.SANITY_HUNT_DRAIN_MAX )

            local current = ply:GetNWFloat( "Sanity", SANITY_MAX )
            ply:SetNWFloat( "Sanity", math.Clamp( current - drain, 0, SANITY_MAX ) )
        end
    end )

    timer.Create( "Hunt_LOSTick", 0.1, 0, function()
        if not huntActive then
            timer.Remove( "Hunt_LOSTick" )
            return
        end
        if not IsValid( ghost ) then return end

        local ghostPos = ghost:GetPos() + Vector( 0, 0, 64 )
        local hasLOS   = false

        for _, ply in ipairs( player.GetAll() ) do
            if not ply:Alive() then continue end
            if GetRole( ply ) != ROLE_EXORCIST then continue end
            if deadSpectators[ply] then continue end

            local dist = ghost:GetPos():Distance( ply:GetPos() )
            if dist > CONFIG.HUNT_LOS_RANGE then continue end

            local trace = util.TraceLine({
                start  = ghostPos,
                endpos = ply:GetPos() + Vector( 0, 0, 64 ),
                filter = ghost,
                mask   = MASK_SOLID
            })

            if not trace.Hit or trace.Entity == ply then
                hasLOS = true
                break
            end
        end

        if hasLOS then
            ghost:SetRunSpeed( CONFIG.HUNT_LOS_SPEED )
            ghost:SetWalkSpeed( CONFIG.HUNT_LOS_SPEED )
        else
            ghost:SetRunSpeed( CONFIG.HUNT_BASE_SPEED )
            ghost:SetWalkSpeed( CONFIG.HUNT_BASE_SPEED )
        end

        net.Start( "Hunt_LOSUpdate" )
            net.WriteBool( hasLOS )
        net.Send( ghost )
    end )

    timer.Simple( CONFIG.HUNT_DURATION, function()
        if not huntActive then return end
        EndHunt( ghost )
    end )
end

function EndHunt( ghost )
    if not huntActive then return end
    huntActive          = false
    huntCooldownUntil   = CurTime() + CONFIG.HUNT_COOLDOWN

    timer.Remove( "Hunt_SanityDrain" )
    timer.Remove( "Hunt_LOSTick" )

    if IsValid( ghost ) then
        SetGhostVisible( ghost, false )
        ghost:SetRunSpeed( CONFIG.GHOST_RUN_SPEED )
        ghost:SetWalkSpeed( CONFIG.GHOST_WALK_SPEED )
    end

    print( "[Hunt] Hunt ended." )

    -- restore ghost speed
    if IsValid( ghost ) then
        ghost:SetRunSpeed( CONFIG.GHOST_RUN_SPEED )
        ghost:SetWalkSpeed( CONFIG.GHOST_WALK_SPEED )
    end

    net.Start( "Hunt_Ended" )
    net.Broadcast()
end

-- expose hunt state for other systems
function IsHuntActive()
    return huntActive
end

-- weapon_ghost SWEP stuff
hook.Add( "KeyPress", "Hunt_GhostKill", function( ply, key )
    if key != IN_ATTACK then return end
    if not huntActive then return end
    if GetRole( ply ) != ROLE_GHOST then return end

    local eyePos = ply:EyePos()
    local eyeAng = ply:EyeAngles()

    local trace = util.TraceLine({
        start  = eyePos,
        endpos = eyePos + eyeAng:Forward() * 100,
        filter = ply,
        mask   = MASK_SHOT
    })

    if not IsValid( trace.Entity ) then return end
    if not trace.Entity:IsPlayer() then return end

    local target = trace.Entity
    if GetRole( target ) != ROLE_EXORCIST then return end
    if deadSpectators[target] then return end

    target:Kill()
end )

util.AddNetworkString( "Hunt_KeyPress" )
net.Receive( "Hunt_KeyPress", function( len, ply )
    if GetRole( ply ) != ROLE_GHOST then return end
    if GetRoundState() != ROUND_ACTIVE then return end
    if huntActive then return end
    StartHunt( ply )
end )

hook.Add( "Think", "Hunt_ResetOnRoundEnd", function()
    if GetRoundState() != ROUND_ACTIVE and huntActive then
        huntActive = false
        timer.Remove( "Hunt_SanityDrain" )
        timer.Remove( "Hunt_LOSTick" )

        for _, p in ipairs( player.GetAll() ) do
            if GetRole( p ) == ROLE_GHOST then
                SetGhostVisible( p, false )
                p:SetRunSpeed( CONFIG.GHOST_RUN_SPEED )
                p:SetWalkSpeed( CONFIG.GHOST_WALK_SPEED )
            end
        end
    end
end )

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

            if class == "func_breakable" or class == "func_breakable_surf" then
                ent:SetHealth( ent:GetMaxHealth() )
                ent:Fire( "Repair", "", 0 )
                continue
            end
        end

        for _, ply in ipairs( player.GetAll() ) do
            ply:Spawn()
        end
    end )
end

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

hook.Add( "PlayerDeathThink", "Round_BlockRespawn", function( ply )
    if GetRoundState() != ROUND_ACTIVE then return end
    if ply:GetNWBool( "PendingSpectator", false ) then return false end
    if deadSpectators[ply] then return false end
end )

hook.Add( "PlayerDeath", "Round_CheckWinCondition", function( ply, inflictor, attacker )
    if GetRoundState() != ROUND_ACTIVE then return end

    ply:SetNWBool( "PendingSpectator", true )

    timer.Simple( 5, function()
        if not IsValid( ply ) then return end
        ply:SetNWBool( "PendingSpectator", false )

        local deathPos = ply:GetPos()

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

hook.Add( "PlayerDeath", "Round_SetDeathTime", function( ply )
    ply:SetNWFloat( "DeathTime", CurTime() )
end )

-- these spectator features might get removed but I will test these soon :)
hook.Add( "PlayerCanPickupWeapon", "Spectator_NoPickup", function( ply, wep )
    if ply:GetNWBool( "IsDeadSpectator", false ) then return false end
end )

hook.Add( "PlayerSwitchWeapon", "Spectator_NoSwitch", function( ply, oldwep, newwep )
    if ply:GetNWBool( "IsDeadSpectator", false ) then return true end
end )

hook.Add( "PlayerShouldTakeDamage", "Spectator_NoDamage", function( ply, attacker )
    if ply:GetNWBool( "IsDeadSpectator", false ) then return false end
end )

hook.Add( "EntityTakeDamage", "Spectator_NoDealDamage", function( ent, dmg )
    local attacker = dmg:GetAttacker()
    if not IsValid( attacker ) then return end
    if not attacker:IsPlayer() then return end
    if attacker:GetNWBool( "IsDeadSpectator", false ) then
        dmg:SetDamage( 0 )
    end
end )

hook.Add( "PlayerSpawn", "Round_ClearSpectate", function( ply )
    if deadSpectators[ply] then return end

    ply:SetNWBool( "IsDeadSpectator", false )
    ply:SetNWBool( "PendingSpectator", false )
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

hook.Add( "PlayerSpawnedProp", "Round_TagSpawnedProp", function( ply, model, ent )
    ent:SetNWBool( "PlayerSpawned", true )
end )

function GM:PlayerSpawn( ply )
    if ply:GetNWBool( "IsDeadSpectator", false ) then return end

    ply:SetModel( ply:GetInfo( "cl_playermodel" ) )
    ply:SetPlayerColor( Vector( ply:GetInfo( "cl_color" ) ) )
    ply:SetGravity( .5 )
    ply:SetMaxHealth( 200 )
    ply:SetHealth( 200 )

    if GetRole( ply ) == ROLE_GHOST then
        ply:SetWalkSpeed( CONFIG.GHOST_WALK_SPEED )
        ply:SetRunSpeed( CONFIG.GHOST_RUN_SPEED )
        ply:SetRenderMode( RENDERMODE_TRANSALPHA )
        ply:SetColor( Color( 255, 255, 255, 0 ) )
        ply:Give( "weapon_ghost" )
        ply:SelectWeapon( "weapon_ghost" )
    else
        ply:SetWalkSpeed( CONFIG.EXORCIST_WALK_SPEED )
        ply:SetRunSpeed( CONFIG.EXORCIST_RUN_SPEED )
        ply:Give( "weapon_crowbar" )
    end

    ply:SetupHands()
end

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

    -- only deduct sanity if at least 1 prop was thrown
    if thrown > 0 then
        for _, p in ipairs( player.GetAll() ) do
            if GetRole( p ) != ROLE_EXORCIST then continue end
            if deadSpectators[p] then continue end
            if not p:Alive() then continue end

            local dist = p:GetPos():Distance( ply:GetPos() )
            if dist > THROW_RADIUS then continue end

            local current = p:GetNWFloat( "Sanity", SANITY_MAX )
            p:SetNWFloat( "Sanity", math.Clamp( current - 5, 0, SANITY_MAX ) )
        end
    end
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