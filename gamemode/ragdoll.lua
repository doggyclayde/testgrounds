-- I will remove these soon.

if SERVER then
    util.AddNetworkString( "Rag_Watch" )
    util.AddNetworkString( "Rag_Create" )
    util.AddNetworkString( "Rag_Cleanup" )

    hook.Add( "PlayerDeath", "Rag_SendDeathSignal", function( ply )
        net.Start( "Rag_Watch" )
            net.WriteEntity( ply )
        net.Broadcast()
    end )

    hook.Add( "PlayerSpawn", "Rag_SendSpawnSignal", function( ply )
        timer.Simple( 0.2, function()
            if not IsValid( ply ) then return end
            net.Start( "Rag_Create" )
                net.WriteEntity( ply )
            net.Broadcast()
        end )
    end )

    hook.Add( "PlayerDisconnected", "Rag_SendCleanup", function( ply )
        net.Start( "Rag_Cleanup" )
            net.WriteEntity( ply )
        net.Broadcast()
    end )

    hook.Add( "CreateEntityRagdoll", "Rag_KeepServerRagdoll", function( ply, ragdoll )
    end )

elseif CLIENT then
    local ragdolls       = {}
    local activeRagdolls = {}
    local pendingOrDead  = {}

    local function BuildRagdoll( ply )
        local ragData = ragdolls[ply]
        if not ragData then
            print( "[Rag] BuildRagdoll: no ragData for " .. tostring( IsValid(ply) and ply:Nick() or "invalid" ) )
            return
        end

        if activeRagdolls[ply] and IsValid( activeRagdolls[ply] ) then
            activeRagdolls[ply]:Remove()
        end

        local clientRag = ClientsideRagdoll( ragData.model )
        if not IsValid( clientRag ) then
            print( "[Rag] BuildRagdoll: ClientsideRagdoll failed" )
            return
        end

        activeRagdolls[ply] = clientRag
        clientRag:SetSkin( ragData.skin )
        clientRag:SetNoDraw( false )
        clientRag:DrawShadow( true )

        if ragData.playerColor then
            clientRag.GetPlayerColor = function()
                return ragData.playerColor
            end
        end

        if IsValid( ply ) then
            for i = 0, clientRag:GetNumBodyGroups() - 1 do
                clientRag:SetBodygroup( i, ply:GetBodygroup( i ) )
            end
        end

        for i = 0, clientRag:GetPhysicsObjectCount() - 1 do
            local phys     = clientRag:GetPhysicsObjectNum( i )
            local physData = ragData.physicsData[i]

            if IsValid( phys ) and physData then
                phys:EnableMotion( false )
                phys:SetPos( physData.pos )
                phys:SetAngles( physData.ang )
                phys:SetVelocity( physData.vel or Vector( 0, 0, 0 ) )
                phys:SetAngleVelocity( physData.angVel or Angle( 0, 0, 0 ) )
                phys:EnableMotion( true )
            end
        end

        print( "[Rag] Built clientside ragdoll for " .. tostring( IsValid(ply) and ply:Nick() or "invalid" ) )
    end

    net.Receive( "Rag_Watch", function()
        local ply = net.ReadEntity()
        if not IsValid( ply ) then return end
        print( "[Rag] Watching ragdoll for: " .. ply:Nick() )

        pendingOrDead[ply] = true

        local sid64    = ply:SteamID64()
        local plyColor = ply:GetPlayerColor()
        local plySkin  = ply:GetSkin()
        local plyModel = ply:GetModel()
        local rag      = nil
        local saved    = false

        if activeRagdolls[ply] and IsValid( activeRagdolls[ply] ) then
            activeRagdolls[ply]:Remove()
            activeRagdolls[ply] = nil
        end

        hook.Add( "Think", "Rag_Think_" .. sid64, function()
            if not saved and IsValid( ply ) and not IsValid( rag ) then
                rag = ply:GetRagdollEntity()
                if IsValid( rag ) then
                    print( "[Rag] Found ragdoll entity for " .. ply:Nick() )
                    -- hide serverside ragdoll, our clientside copy handles visuals
                    rag:SetNoDraw( true )
                end
            end

            if not saved and IsValid( rag ) then
                local physicsData = {}
                local hasData     = false

                for i = 0, rag:GetPhysicsObjectCount() - 1 do
                    local phys = rag:GetPhysicsObjectNum( i )
                    if IsValid( phys ) then
                        physicsData[i] = {
                            pos    = phys:GetPos(),
                            ang    = phys:GetAngles(),
                            vel    = phys:GetVelocity(),
                            angVel = phys:GetAngleVelocity(),
                        }
                        hasData = true
                    end
                end

                if hasData then
                    ragdolls[ply] = {
                        model       = plyModel,
                        skin        = plySkin,
                        playerColor = plyColor,
                        physicsData = physicsData,
                    }
                    saved = true
                    print( "[Rag] Physics data saved for " .. ply:Nick() .. " (" .. table.Count(physicsData) .. " bones)" )
                    BuildRagdoll( ply )
                    hook.Remove( "Think", "Rag_Think_" .. sid64 )
                end
            end
        end )

        timer.Simple( 5, function()
            hook.Remove( "Think", "Rag_Think_" .. sid64 )
        end )
    end )

    hook.Add( "CalcView", "Rag_DeathCam", function( ply, origin, angles, fov )
        if ply:Alive() then return end
        if ply:GetNWBool( "IsDeadSpectator", false ) then return end

        local rag = activeRagdolls[ply]
        if not IsValid( rag ) then return end

        local headBone = rag:LookupBone( "ValveBiped.Bip01_Pelvis" )
        local ragPos

        if headBone then
            local bonePos, _ = rag:GetBonePosition( headBone )
            ragPos = bonePos or rag:GetPos()
        else
            ragPos = rag:GetPos()
        end

        local camPos   = ragPos + Vector( 0, 0, 10 )
        local camBack  = camPos - angles:Forward() * 90

        local trace = util.TraceLine({
            start  = camPos,
            endpos = camBack,
            filter = ply,
            mask   = MASK_SOLID
        })

        local view    = {}
        view.origin   = trace.Hit and ( trace.HitPos + trace.HitNormal * 4 ) or camBack
        view.angles   = angles
        view.fov      = fov

        return view
    end )
    
    net.Receive( "Rag_Create", function()
        local ply = net.ReadEntity()
        print( "[Rag] Rag_Create received for: " .. tostring( IsValid(ply) and ply:Nick() or "invalid" ) )

        if IsValid( ply ) then
            hook.Remove( "Think", "Rag_Think_" .. ply:SteamID64() )
            if not ply:GetNWBool( "IsDeadSpectator", false ) then
                pendingOrDead[ply] = nil
            end
        end
    end )

    net.Receive( "Rag_Cleanup", function()
        local ply = net.ReadEntity()
        if activeRagdolls[ply] and IsValid( activeRagdolls[ply] ) then
            activeRagdolls[ply]:Remove()
        end
        activeRagdolls[ply] = nil
        ragdolls[ply]       = nil
        pendingOrDead[ply]  = nil
    end )

    hook.Add( "Round_Cleanup", "Rag_RoundCleanup", function()
        for ply, rag in pairs( activeRagdolls ) do
            if IsValid( rag ) then rag:Remove() end
        end
        activeRagdolls = {}
        ragdolls       = {}
        pendingOrDead  = {}
    end )

    hook.Add( "Think", "Rag_CleanupOnSpawn", function()
        for ply, rag in pairs( activeRagdolls ) do
            if IsValid( ply ) and ply:Alive() and IsValid( rag ) then
                if pendingOrDead[ply] then continue end
                rag:Remove()
                activeRagdolls[ply] = nil
                ragdolls[ply]       = nil
            end
        end
    end )
end