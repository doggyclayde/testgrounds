function HideHud(name)
    for k, v in pairs({"CHudHealth", "CHudBattery", "CHudAmmo", "CHudSecondaryAmmo", "CHudCrosshair"}) do
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

    -- INTERMISSION ROUND (ROUND_END doesnt work AGHHHHHHHHHHHHH)
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
    
    -- ── SANITY BAR (exorcists only, during active round) ─────
    -- this is temporary
    if LocalRoundState() == ROUND_ACTIVE and LocalRole() == ROLE_EXORCIST then
        local ply     = LocalPlayer()
        local sanity  = ply:GetNWFloat( "Sanity", 100 )
        local barW    = 200
        local barH    = 14
        local barX    = sw * 0.5 - barW * 0.5
        local barY    = sh - 80

        surface.SetDrawColor( Color( 0, 0, 0, 150 ) )
        surface.DrawRect( barX, barY, barW, barH )

        local r = math.Clamp( ( 1 - sanity / 100 ) * 255 * 2, 0, 255 )
        local g = math.Clamp( ( sanity / 100 ) * 255 * 2, 0, 255 )
        surface.SetDrawColor( Color( r, g, 0, 200 ) )
        surface.DrawRect( barX, barY, barW * ( sanity / 100 ), barH )

        surface.SetDrawColor( Color( 255, 255, 255, 60 ) )
        surface.DrawOutlinedRect( barX, barY, barW, barH )

        draw.SimpleText(
            "SANITY  " .. math.ceil( sanity ) .. "%",
            "DermaDefault",
            barX + barW * 0.5, barY - 14,
            Color( 255, 255, 255, 180 ),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP
        )
    end

    -- ── GHOST ONLY BELOW THIS LINE ────────────────────────
    if LocalRole() != ROLE_GHOST then return end

    -- CUSTOM CROSSHAIR (TBD)
    -- you can suggest what kind of crosshair the ghost should have. I would appreciate it!
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

    -- COOLDOWN ARC
    local radius   = 22
    local segments = 64
    local fraction = cooldownRemaining / cooldownMax

    -- color arc (ts took me hours btw for this simple ahh crosshair)
    surface.SetDrawColor(Color(255, 255, 255, 40))
    for i = 0, segments do
        local a1 = math.rad((i / segments) * 180 + 90)
        local a2 = math.rad(((i + 1) / segments) * 180 + 90)
        surface.DrawLine(
            cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
            cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
        )
    end

    -- cooldown fill
    if fraction > 0 then
        surface.SetDrawColor(fraction > 0.5 and Color(100, 100, 255, 220) or Color(255, 80, 80, 220))
        for i = 0, segments do
            local t = i / segments
            if t > fraction then break end
            local a1 = math.rad(t * 180 + 90)
            local a2 = math.rad(((i + 1) / segments) * 180 + 90)
            surface.DrawLine(
                cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
            )
        end
    end

    -- ready indicator
    if cooldownRemaining <= 0 then
        surface.SetDrawColor(Color(100, 255, 100, 180))
        for i = 0, segments do
            local a1 = math.rad((i / segments) * 180 + 90)
            local a2 = math.rad(((i + 1) / segments) * 180 + 90)
            surface.DrawLine(
                cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
            )
        end
    end
end)