include( "shared.lua" )
include( "ragdoll.lua" )

local myRole             = ROLE_NONE
local roundState         = ROUND_WAITING
local thirdPerson        = false
local thirdPersonKeyHeld = false
local canThrow           = true
local readyKeyHeld       = false
local myGhostType        = GHOST_TYPE_NONE
local sprintHeld         = false
local stamina            = 1  -- local copy for HUD use
local ghostEventKeyHeld  = false
local minThrowKeyHeld    = false
local ghostEnergy        = 100
local free_cam_active = false
local free_cam_pos    = nil
local free_cam_angles = nil

function LocalEnergy()
    return ghostEnergy
end

net.Receive( "Energy_Update", function()
    ghostEnergy = net.ReadFloat()
end )

net.Receive( "Ghost_Event", function()
    local active = net.ReadBool()
    print( "[GhostEvent] Ghost event active: " .. tostring( active ) )
end )

local was_dead = false

hook.Add( "Think", "Freecam_DeathWatch", function()
	local ply     = LocalPlayer()
	local is_dead = ply:GetNWBool( "PendingSpectator", false )
		or ply:GetNWBool( "IsDeadSpectator", false )

	if is_dead and not was_dead then
		was_dead        = true
		free_cam_active = false
		free_cam_pos    = ply:EyePos()
		free_cam_angles = ply:EyeAngles()

		timer.Simple( 3, function()
			free_cam_active = true
		end )
	elseif not is_dead then
		was_dead = false
	end
end )

hook.Add( "CalcView", "Freecam_DeadView", function( ply, origin, angles, fov )
	local is_dead = ply:GetNWBool( "IsDeadSpectator", false )
		or ply:GetNWBool( "PendingSpectator", false )
	if not is_dead then return end
	if not free_cam_active then return end
	if not free_cam_pos then return end

	local view  = {}
	view.origin = free_cam_pos
	view.angles = free_cam_angles
	view.fov    = fov

	return view
end )

hook.Add( "Think", "Freecam_Movement", function()
	local ply = LocalPlayer()
	local is_dead = ply:GetNWBool( "IsDeadSpectator", false )
		or ply:GetNWBool( "PendingSpectator", false )
	if not is_dead then return end
	if not free_cam_active then return end
	if not free_cam_pos then return end

	local speed = 700
	local ang   = free_cam_angles
	local move  = Vector( 0, 0, 0 )

	if input.IsKeyDown( KEY_W ) then move = move + ang:Forward() end
	if input.IsKeyDown( KEY_S ) then move = move - ang:Forward() end
	if input.IsKeyDown( KEY_A ) then move = move - ang:Right() end
	if input.IsKeyDown( KEY_D ) then move = move + ang:Right() end
	if input.IsKeyDown( KEY_SPACE ) then move = move + Vector( 0, 0, 1 ) end
	if input.IsKeyDown( KEY_LCONTROL ) then move = move - Vector( 0, 0, 1 ) end

	if move:LengthSqr() > 0 then
		free_cam_pos = free_cam_pos + move:GetNormalized() * speed * FrameTime()
	end

	free_cam_angles = ply:EyeAngles()
end )

hook.Add( "Round_Cleanup", "Freecam_Reset", function()
	free_cam_active = false
	free_cam_pos    = nil
	free_cam_angles = nil
end )

hook.Add( "Think", "Ghost_EventInput", function()
    if LocalRole() != ROLE_GHOST then return end
    if LocalRoundState() != ROUND_ACTIVE then return end

    if input.IsKeyDown( KEY_H ) and not ghostEventKeyHeld then
        ghostEventKeyHeld = true
        net.Start( "Ghost_EventRequest" )
        net.SendToServer()
    elseif not input.IsKeyDown( KEY_H ) then
        ghostEventKeyHeld = false
    end
end )

hook.Add( "Think", "Ghost_MinThrowInput", function()
    if LocalRole() != ROLE_GHOST then return end
    if LocalRoundState() != ROUND_ACTIVE then return end

    if input.IsKeyDown( KEY_M ) and not minThrowKeyHeld then
        minThrowKeyHeld = true
        net.Start( "Ghost_MinThrowRequest" )
        net.SendToServer()
    elseif not input.IsKeyDown( KEY_M ) then
        minThrowKeyHeld = false
    end
end )

function LocalStamina()
    return stamina
end

function LocalGhostType()
    return myGhostType
end

net.Receive( "Role_Assigned", function()
    myRole = net.ReadInt( 8 )
    print( "[Roles] I am role: " .. myRole )
end )

net.Receive( "GhostType_Assigned", function()
    myGhostType = net.ReadInt( 8 )
    print( "[Ghost] I am ghost type: " .. myGhostType )
end )

net.Receive( "Stamina_Update", function()
    stamina = net.ReadFloat()
end )

function LocalRole()
    return myRole
end

function LocalRoundState()
    return roundState
end

net.Receive( "Round_StateChanged", function()
    roundState = net.ReadInt( 8 )
    print( "[Round] Round state: " .. roundState )

    if roundState == ROUND_WAITING then
        hook.Run( "Round_Cleanup" )
    end
end )

hook.Add( "Round_Cleanup", "Ghost_ResetThirdPerson", function()
    thirdPerson = false
end )

net.Receive( "Round_ReadyStatus", function()
    readyCount = net.ReadInt( 8 )
    totalCount = net.ReadInt( 8 )
end )

hook.Add( "Think", "Stamina_SprintInput", function()
    local role      = LocalRole()
    local ghostType = LocalGhostType()

    local canSprint = role == ROLE_EXORCIST
        or ( role == ROLE_GHOST and ghostType == GHOST_TYPE_REVENANT and LocalRoundState() == ROUND_ACTIVE )

    if not canSprint then return end

    local held = input.IsKeyDown( KEY_LSHIFT )

    if held != sprintHeld then
        sprintHeld = held
        net.Start( "Stamina_SprintRequest" )
            net.WriteBool( held )
        net.SendToServer()
    end
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

hook.Add( "Think", "Poltergeist_ThrowInput", function()
    if LocalRole() != ROLE_GHOST then return end
    if LocalRoundState() != ROUND_ACTIVE then return end
    if LocalGhostType() != GHOST_TYPE_POLTERGEIST then return end

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

hook.Add( "PlayerBindPress", "DisableJump", function( ply, bind, pressed )
    if bind == "+jump" then return true end
end )

hook.Add( "EntityEmitSound", "Spectator_NoSound", function( data )
    local ent = data.Entity
    if not IsValid( ent ) then return end
    if not ent:IsPlayer() then return end
    if ent:GetNWBool( "IsDeadSpectator", false ) then return false end
end )

local huntActive    = false
local huntKeyHeld   = false
local losActive     = false
local highlightedPlayers = {}

net.Receive( "Hunt_Started", function()
    huntActive = true
    print( "[Hunt] Hunt started." )
end )

net.Receive( "Hunt_Ended", function()
    huntActive = false
    losActive  = false
    highlightedPlayers = {}
    print( "[Hunt] Hunt ended." )
end )

net.Receive( "Hunt_LOSUpdate", function()
    losActive = net.ReadBool()
end )

hook.Add( "Think", "Hunt_KeyInput", function()
    if LocalRole() != ROLE_GHOST then return end
    if LocalRoundState() != ROUND_ACTIVE then return end
    if huntActive then return end

    if input.IsKeyDown( KEY_N ) and not huntKeyHeld then
        huntKeyHeld = true
        net.Start( "Hunt_KeyPress" )
        net.SendToServer()
    elseif not input.IsKeyDown( KEY_N ) then
        huntKeyHeld = false
    end
end )

-- highlight exorcists in LOS during hunt (temporary)
hook.Add( "PostDrawOpaqueRenderables", "Hunt_HighlightPlayers", function()
    if LocalRole() != ROLE_GHOST then return end
    if not huntActive then return end
    if not losActive then return end

    for _, ply in ipairs( player.GetAll() ) do
        if not IsValid( ply ) then continue end
        if ply == LocalPlayer() then continue end
        if not ply:Alive() then continue end
        if ply:GetNWBool( "IsDeadSpectator", false ) then continue end
        if ply:GetNWInt( "Role", ROLE_NONE ) != ROLE_EXORCIST then continue end

        render.SetColorModulation( 1, 0, 0 )
        render.SetBlend( 0.3 )
        ply:DrawModel()
        render.SetColorModulation( 1, 1, 1 )
        render.SetBlend( 1 )
    end
end )

hook.Add( "HUDShouldDraw", "HideExtraHUD", function( name )
    if name == "CHudDeathNotice" then return false end
end )

hook.Add( "DrawDeathNotice", "HideDeathNotice", function()
    return true
end )

hook.Add( "PostDrawTranslucentRenderables", "HideNametags", function()
end )

hook.Add( "HUDDrawTargetID", "HideTargetID", function()
    return true
end )

hook.Add( "PlayerFootstep", "Ghost_NoFootsteps", function( ply, pos, foot, sound, volume, filter )
    if ply:GetNWInt( "Role", ROLE_NONE ) != ROLE_GHOST then return end
    if LocalRoundState() != ROUND_ACTIVE then return end
    if huntActive then return end
    return true
end )

include( "testhud.lua" )