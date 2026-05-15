AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "testhud.lua" )

include( "shared.lua" )
include( "shared.lua" )

function GM:PlayerSpawn(ply)
    ply:SetGravity(.5)
    ply:SetMaxHealth(200)
    ply:SetRunSpeed(1000)
    ply:SetWalkSpeed(300)
    ply:Give("weapon_crowbar")
    ply:Give("weapon_physgun")
    ply:SetupHands()
end