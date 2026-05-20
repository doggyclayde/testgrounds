SWEP.PrintName       = ""
SWEP.Author          = "DoggyClayde"
SWEP.Slot            = 0
SWEP.SlotPos         = 0
SWEP.DrawAmmo        = false
SWEP.DrawCrosshair   = false
SWEP.HoldType        = "normal"

SWEP.Primary.ClipSize       = -1
SWEP.Primary.DefaultClip    = -1
SWEP.Primary.Automatic      = false
SWEP.Primary.Ammo           = "none"

SWEP.Secondary.ClipSize     = -1
SWEP.Secondary.DefaultClip  = -1
SWEP.Secondary.Automatic    = false
SWEP.Secondary.Ammo         = "none"

SWEP.WorldModel = ""
SWEP.ViewModel  = ""

function SWEP:Initialize()
    self:SetHoldType( "normal" )
end

function SWEP:Deploy()
    return true
end

function SWEP:Holster()
    return true
end

function SWEP:PrimaryAttack()
    if not SERVER then return end

    local ply = self:GetOwner()
    if not IsValid( ply ) then return end

    self:SetNextPrimaryFire( CurTime() + 0.5 )
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire( CurTime() + 0.5 )
end

function SWEP:DrawWorldModel() end
function SWEP:DrawViewModel() end