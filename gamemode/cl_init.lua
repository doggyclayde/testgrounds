include( "shared.lua" )
include( "ragdoll.lua" )
include( "testhud.lua" )

local myRole             = ROLE_NONE
local roundState         = ROUND_WAITING
local thirdPerson        = true
local thirdPersonKeyHeld = false
local canThrow           = true
local readyKeyHeld       = false

-- ── ROLE ──────────────────────────────────────────────────
net.Receive( "Role_Assigned", function()
    myRole = net.ReadInt( 8 )
    print( "[Roles] I am role: " .. myRole )
end )

function LocalRole()
    return myRole
end

function LocalRoundState()
    return roundState
end

-- ── ROUND STATE ───────────────────────────────────────────
net.Receive( "Round_StateChanged", function()
    roundState = net.ReadInt( 8 )
    print( "[Round] Round state: " .. roundState )

    if roundState == ROUND_WAITING then
        hook.Run( "Round_Cleanup" )
    end
end )

-- ── READY UP ──────────────────────────────────────────────
net.Receive( "Round_ReadyStatus", function()
    readyCount = net.ReadInt( 8 )
    totalCount = net.ReadInt( 8 )
end )

hook.Add( "Think", "Round_ReadyInput", function()
    if roundState != ROUND_WAITING then return end

    if input.IsKeyDown( KEY_F3 ) and not readyKeyHeld then
        readyKeyHeld = true
        net.Start( "Round_PlayerReady" )
        net.SendToServer()
    elseif not input.IsKeyDown( KEY_F3 ) then
        readyKeyHeld = false
    end
end )

-- ── THROW ABILITY ─────────────────────────────────────────
hook.Add( "Think", "Poltergeist_ThrowInput", function()
    if LocalRole() != ROLE_GHOST then return end
    if LocalRoundState() != ROUND_ACTIVE then return end

    if input.IsKeyDown( KEY_J ) and canThrow then
        canThrow = false
        net.Start( "Poltergeist_Throw" )
        net.SendToServer()
    elseif not input.IsKeyDown( KEY_J ) then
        canThrow = true
    end
end )

net.Receive( "Poltergeist_CooldownStatus", function()
    cooldownRemaining = net.ReadFloat()
end )

-- ── THIRD PERSON ──────────────────────────────────────────
hook.Add( "Think", "Poltergeist_ThirdPerson", function()
    local ply = LocalPlayer()
    if not IsValid( ply ) then return end
    if LocalRole() != ROLE_GHOST then return end

    if input.IsKeyDown( KEY_F ) and not thirdPersonKeyHeld then
        thirdPersonKeyHeld = true
        thirdPerson = not thirdPerson
    elseif not input.IsKeyDown( KEY_F ) then
        thirdPersonKeyHeld = false
    end
end )

hook.Add( "CalcView", "Poltergeist_ThirdPersonCam", function( ply, origin, angles, fov )
    if not IsValid( ply ) then return end
    if LocalRole() != ROLE_GHOST then return end
    if not thirdPerson then return end

    local view  = {}
    view.origin = origin - angles:Forward() * 80 + angles:Up() * 10
    view.angles = angles
    view.fov    = fov

    local trace = util.TraceLine({
        start  = origin,
        endpos = view.origin,
        filter = ply,
        mask   = MASK_SOLID
    })

    if trace.Hit then
        view.origin = trace.HitPos + trace.HitNormal * 5
    end

    return view
end )

hook.Add( "ShouldDrawLocalPlayer", "Poltergeist_DrawSelf", function( ply )
    if LocalRole() != ROLE_GHOST then return false end
    return thirdPerson
end )

-- ── DISABLE JUMP ──────────────────────────────────────────
hook.Add( "PlayerBindPress", "DisableJump", function( ply, bind, pressed )
    if bind == "+jump" then return true end
end )

-- ── SPECTATOR SOUNDS ──────────────────────────────────────
hook.Add( "EntityEmitSound", "Spectator_NoSound", function( data )
    local ent = data.Entity
    if not IsValid( ent ) then return end
    if not ent:IsPlayer() then return end
    if ent:GetNWBool( "IsDeadSpectator", false ) then return false end
end )