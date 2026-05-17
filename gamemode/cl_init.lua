include( "shared.lua" )
include( "testhud.lua" )

local myRole         = ROLE_NONE
local roundState     = ROUND_WAITING
local thirdPerson    = true
local thirdPersonKeyHeld = false
local canThrow       = true
local readyKeyHeld   = false

-- ROLE
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

-- ROUND STATE
net.Receive( "Round_StateChanged", function()
    roundState = net.ReadInt( 8 )
    -- debug print
    print( "[Round] Round state: " .. roundState )
end )

-- PLAYER_READY INPUT
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

-- POLTERGEIST: THROW ABILITY
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

-- THIRD PERSON (ghost only)
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

    local view   = {}
    view.origin  = origin - angles:Forward() * 80 + angles:Up() * 20
    view.angles  = angles
    view.fov     = fov

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

net.Receive( "Round_ReadyStatus", function()
    readyCount = net.ReadInt( 8 )
    totalCount = net.ReadInt( 8 )
end )

hook.Add( "PlayerBindPress", "DisableJump", function( ply, bind, pressed )
    if bind == "+jump" then
        return true
    end
end )

-- clientside ragdoll on death (still needs fix)
hook.Add( "PostEntityTakeDamage", "Round_ClientRagdoll", function( ent, dmginfo, tookDamage )
    if not ent:IsPlayer() then return end
    if ent:Alive() then return end
    if LocalRoundState() != ROUND_ACTIVE then return end

    local ragdoll = ClientsideRagdoll( ent:GetModel(), RENDERMODE_NORMAL )
    ragdoll:SetPos( ent:GetPos() )
    ragdoll:SetAngles( ent:GetAngles() )
    ragdoll:SetColor( ent:GetColor() )

    -- copy bone positions
    for i = 0, ent:GetBoneCount() - 1 do
        local bonePos, boneAng = ent:GetBonePosition( i )
        if bonePos then
            local phys = ragdoll:GetPhysicsObjectNum( i )
            if IsValid( phys ) then
                phys:SetPos( bonePos )
                phys:SetAngles( boneAng )
                phys:Wake()
            end
        end
    end

    -- clean up when round ends (server-side ragdolls don't work here for magical reasons)
    -- don't make me do server-side ragdolls or I will kill you
    hook.Add( "Round_Cleanup", "RemoveRagdoll_" .. ent:EntIndex(), function()
        if IsValid( ragdoll ) then ragdoll:Remove() end
        hook.Remove( "Round_Cleanup", "RemoveRagdoll_" .. ent:EntIndex() )
    end )
end )

-- ts added so spectators don't make sounds lma
hook.Add( "EntityEmitSound", "Spectator_NoSound", function( data )
    local ent = data.Entity
    if not IsValid( ent ) then return end
    if not ent:IsPlayer() then return end
    if ent:GetNWBool( "IsDeadSpectator", false ) then
        return false
    end
end )

net.Receive( "Round_StateChanged", function()
    local newState = net.ReadInt( 8 )
    roundState = newState

    -- fire cleanup hook when round ends or resets
    if newState == ROUND_END or newState == ROUND_WAITING then
        hook.Run( "Round_Cleanup" )
    end
end )