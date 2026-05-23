if SERVER then
	util.AddNetworkString( "Rag_Death" )
	util.AddNetworkString( "Rag_Cleanup" )

	hook.Add( "PlayerDeath", "Rag_SendDeath", function( ply )
		net.Start( "Rag_Death" )
			net.WriteEntity( ply )
			net.WriteVector( ply:GetVelocity() )
		net.Broadcast()
	end )

	hook.Add( "CreateEntityRagdoll", "Rag_HideServerRagdoll", function( ply, ragdoll )
		ragdoll:SetNoDraw( true )
		ragdoll:SetCollisionGroup( COLLISION_GROUP_DEBRIS )
	end )

elseif CLIENT then
	local corpses = {}

	local function CreateCorpse( ply )
		if not IsValid( ply ) then return end

		local corpse = ClientsideRagdoll( ply:GetModel() )
		if not IsValid( corpse ) then return end

		corpse:SetSkin( ply:GetSkin() )
		corpse:SetNoDraw( false )
		corpse:DrawShadow( true )

		for i = 0, corpse:GetNumBodyGroups() - 1 do
			corpse:SetBodygroup( i, ply:GetBodygroup( i ) )
		end

		if ply.GetPlayerColor then
			local col = ply:GetPlayerColor()
			corpse.GetPlayerColor = function() return col end
		end

		-- copy bone positions from the player at death
		for i = 0, corpse:GetPhysicsObjectCount() - 1 do
			local phys     = corpse:GetPhysicsObjectNum( i )
			local plyPhys  = ply:GetPhysicsObjectNum( i )

			if IsValid( phys ) and IsValid( plyPhys ) then
				phys:SetPos( plyPhys:GetPos() )
				phys:SetAngles( plyPhys:GetAngles() )
				phys:SetVelocity( ply:GetVelocity() )
				phys:EnableMotion( true )
			end
		end

		corpses[ply] = corpse
		print( "[Rag] Corpse created for " .. ply:Nick() )
	end

	net.Receive( "Rag_Death", function()
		local ply = net.ReadEntity()
		net.ReadVector()  -- velocity read, handled via physics copy above

		-- small delay so player model is in death pose
		timer.Simple( 0.1, function()
			if not IsValid( ply ) then return end
			CreateCorpse( ply )
		end )
	end )

	net.Receive( "Rag_Cleanup", function()
		for ply, corpse in pairs( corpses ) do
			if IsValid( corpse ) then corpse:Remove() end
		end
		corpses = {}
	end )

	hook.Add( "Round_Cleanup", "Rag_RoundCleanup", function()
		for ply, corpse in pairs( corpses ) do
			if IsValid( corpse ) then corpse:Remove() end
		end
		corpses = {}
	end )
end

hook.Add( "CreateEntityRagdoll", "Rag_HideServerRagdoll", function( ply, ragdoll )
	ragdoll:Remove()
end )