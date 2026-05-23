function HideHud(name)
    for k, v in pairs({"CHudHealth", "CHudBattery", "CHudAmmo", "CHudSecondaryAmmo", "CHudCrosshair", "CHudZoom"}) do
        if name == v then
            return false
        end
    end
end
hook.Add("HUDShouldDraw", "HideDefaultHud", HideHud)

cooldownRemaining = 0
local cooldownMax = 8
readyCount        = 0
totalCount        = 0

hook.Add("Think", "Poltergeist_CooldownTick", function()
    if cooldownRemaining > 0 then
        cooldownRemaining = math.max(0, cooldownRemaining - FrameTime())
    end
end)

hook.Add("HUDPaint", "Poltergeist_HUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local sw = ScrW()
    local sh = ScrH()
    local cx = sw * 0.5
    local cy = sh * 0.5

    local state = LocalRoundState()

    if state == ROUND_WAITING then
        draw.SimpleText(
            "Press F3 to ready up",
            "DermaLarge",
            sw * 0.5, sh * 0.15,
            Color(255, 255, 255, 200),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
        draw.SimpleText(
            readyCount .. " / " .. totalCount .. " ready",
            "DermaLarge",
            sw * 0.5, sh * 0.15 + 36,
            Color(100, 255, 100, 200),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
    end

    if state == ROUND_STARTING then
        draw.SimpleText(
            "Round starting...",
            "DermaLarge",
            sw * 0.5, sh * 0.15,
            Color(255, 200, 50, 220),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
    end

    if state == ROUND_END then
        draw.SimpleText(
            "Round over. Ready up for next round.",
            "DermaLarge",
            sw * 0.5, sh * 0.15,
            Color(255, 80, 80, 220),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
    end

    -- ── EXORCIST HUD ──────────────────────────────────────
    if LocalRoundState() == ROUND_ACTIVE and LocalRole() == ROLE_EXORCIST then
        local sanity  = LocalPlayer():GetNWFloat( "Sanity", 100 )
        local barW    = 200
        local barH    = 14
        local barX    = sw * 0.5 - barW * 0.5
        local sanityY = sh - 80

        surface.SetDrawColor( Color( 0, 0, 0, 150 ) )
        surface.DrawRect( barX, sanityY, barW, barH )
        local r = math.Clamp( ( 1 - sanity / 100 ) * 510, 0, 255 )
        local g = math.Clamp( ( sanity / 100 ) * 510, 0, 255 )
        surface.SetDrawColor( Color( r, g, 0, 200 ) )
        surface.DrawRect( barX, sanityY, barW * ( sanity / 100 ), barH )
        surface.SetDrawColor( Color( 255, 255, 255, 60 ) )
        surface.DrawOutlinedRect( barX, sanityY, barW, barH )
        draw.SimpleText( "SANITY  " .. math.ceil( sanity ) .. "%", "DermaDefault",
            barX + barW * 0.5, sanityY - 14, Color( 255, 255, 255, 180 ),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
    end  -- closes exorcist block

    -- ── GHOST ONLY BELOW THIS LINE ────────────────────────
    if LocalRole() != ROLE_GHOST then return end
    if LocalRoundState() != ROUND_ACTIVE then return end

    -- CUSTOM CROSSHAIR
    local crossSize  = 6
    local crossGap   = 4
    local crossThick = 2

    surface.SetDrawColor(Color(255, 255, 255, 200))
    surface.DrawRect(cx - crossGap - crossSize, cy - crossThick * 0.5, crossSize, crossThick)
    surface.DrawRect(cx + crossGap, cy - crossThick * 0.5, crossSize, crossThick)
    surface.DrawRect(cx - crossThick * 0.5, cy - crossGap - crossSize, crossThick, crossSize)
    surface.DrawRect(cx - crossThick * 0.5, cy + crossGap, crossThick, crossSize)

    surface.SetDrawColor(Color(255, 255, 255, 255))
    surface.DrawRect(cx - 1, cy - 1, 2, 2)

    -- COOLDOWN / STAMINA ARC (left half)
    local radius   = 22
    local segments = 64

    if LocalGhostType() == GHOST_TYPE_POLTERGEIST then
        local fraction = cooldownRemaining / cooldownMax

        surface.SetDrawColor( Color( 255, 255, 255, 40 ) )
        for i = 0, segments do
            local a1 = math.rad( (i / segments) * 180 + 90 )
            local a2 = math.rad( ((i + 1) / segments) * 180 + 90 )
            surface.DrawLine(
                cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
            )
        end

        if fraction > 0 then
            surface.SetDrawColor( fraction > 0.5 and Color( 100, 100, 255, 220 ) or Color( 255, 80, 80, 220 ) )
            for i = 0, segments do
                local t = i / segments
                if t > fraction then break end
                local a1 = math.rad( t * 180 + 90 )
                local a2 = math.rad( ((i + 1) / segments) * 180 + 90 )
                surface.DrawLine(
                    cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                    cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
                )
            end
        end

        if cooldownRemaining <= 0 then
            surface.SetDrawColor( Color( 100, 255, 100, 180 ) )
            for i = 0, segments do
                local a1 = math.rad( (i / segments) * 180 + 90 )
                local a2 = math.rad( ((i + 1) / segments) * 180 + 90 )
                surface.DrawLine(
                    cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                    cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
                )
            end
        end

    elseif LocalGhostType() == GHOST_TYPE_REVENANT then
        local stam = LocalStamina()

        surface.SetDrawColor( Color( 255, 255, 255, 40 ) )
        for i = 0, segments do
            local a1 = math.rad( (i / segments) * 180 + 90 )
            local a2 = math.rad( ((i + 1) / segments) * 180 + 90 )
            surface.DrawLine(
                cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
            )
        end

        surface.SetDrawColor( stam > 0.3 and Color( 180, 100, 255, 220 ) or Color( 255, 80, 80, 220 ) )
        for i = 0, segments do
            local t = i / segments
            if t > stam then break end
            local a1 = math.rad( t * 180 + 90 )
            local a2 = math.rad( ((i + 1) / segments) * 180 + 90 )
            surface.DrawLine(
                cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
            )
        end

        if stam >= 1 then
            surface.SetDrawColor( Color( 100, 255, 100, 180 ) )
            for i = 0, segments do
                local a1 = math.rad( (i / segments) * 180 + 90 )
                local a2 = math.rad( ((i + 1) / segments) * 180 + 90 )
                surface.DrawLine(
                    cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                    cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
                )
            end
        end
    end

    -- ENERGY ARC (right half) — all ghost types
    local energy        = LocalEnergy()
    local energyBase    = math.Clamp( energy / 100, 0, 1 )          -- 0-100 mapped to 0-1
    local energyOver    = math.Clamp( ( energy - 100 ) / 100, 0, 1 ) -- 100-200 mapped to 0-1

    -- track background
    surface.SetDrawColor( Color( 255, 255, 255, 40 ) )
    for i = 0, segments do
        local a1 = math.rad( -( i / segments ) * 180 + 90 )
        local a2 = math.rad( -(( i + 1 ) / segments ) * 180 + 90 )
        surface.DrawLine(
            cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
            cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
        )
    end

    -- yellow fill (0-100)
    if energyBase > 0 then
        surface.SetDrawColor( Color( 255, 220, 50, 220 ) )
        for i = 0, segments do
            local t = i / segments
            if t > energyBase then break end
            local a1 = math.rad( -t * 180 + 90 )
            local a2 = math.rad( -(( i + 1 ) / segments ) * 180 + 90 )
            surface.DrawLine(
                cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
            )
        end
    end

    -- purple overflow fill (100-200) draws on top of full yellow
    if energyOver > 0 then
        surface.SetDrawColor( Color( 180, 80, 255, 220 ) )
        for i = 0, segments do
            local t = i / segments
            if t > energyOver then break end
            local a1 = math.rad( -t * 180 + 90 )
            local a2 = math.rad( -(( i + 1 ) / segments ) * 180 + 90 )
            surface.DrawLine(
                cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
            )
        end
    end
end)