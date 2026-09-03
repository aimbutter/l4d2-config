// ==========================================
// Auto-configure cvars to suppress game clutter
// ==========================================
SendToConsole("gameinstructor_enable 1");
SendToConsole("cl_autohelp 0");
SendToConsole("locator_split_len 0");

printl("<mt2> Bhop Tracker Script Loaded ------------------------------------")

const FL_ONGROUND = 1;

::BhopVars <-
{
    BunnyHopTimerEnabled = false,
    LastLandingSpeed = array(32, 0.0), // Speed recorded on prior landing
    WasOnGround = array(32, true),     // Ground state tracking
    GroundTicks = array(32, 0),        // Ground-contact frame counter
    MaxGroundTicks = 3,                // Max frames touching ground before resetting streak
    playerHints = {}                   
}

::BhopFunc <-
{
    addThinkTimer = function()
    {
        local ent = null;
        while (ent = Entities.FindByClassname(ent, "info_target"))
        {
            if (ent.IsValid() && ent.GetName() == "bhopTimer")
            {
                ent.Kill();
                break;
            }
        }

        ::BhopVars._bhop_detect_timer <- SpawnEntityFromTable("info_target", { targetname = "bhopTimer" });
        if (::BhopVars._bhop_detect_timer != null)
        {
            ::BhopVars.BunnyHopTimerEnabled = true;
            ::BhopVars._bhop_detect_timer.ValidateScriptScope();
            local scrScope = ::BhopVars._bhop_detect_timer.GetScriptScope();
            scrScope["ThinkTimer"] <- ::BhopFunc.Think;
            AddThinkToEnt(::BhopVars._bhop_detect_timer, "ThinkTimer");
        }
    },

    IsAlive = function(player)
    {
        if (!player.IsValid()) return false;
        return player.GetClassname() == "player" && NetProps.GetPropInt(player, "m_lifeState") == 0;
    },

    GetHorizontalSpeed = function(player)
    {
        local velocity = player.GetVelocity();
        return sqrt(velocity.x * velocity.x + velocity.y * velocity.y);
    },

    FormatFloat = function(value)
    {
        local intValue = (value * 10).tointeger();
        return (intValue / 10.0).tostring();
    },

    ShowHintText = function(player, message, iconName, color = "255 255 255")
    {
        local index = player.GetEntityIndex();

        if (index in ::BhopVars.playerHints)
        {
            local oldHint = ::BhopVars.playerHints[index];
            if (oldHint != null && oldHint.IsValid())
            {
                oldHint.Kill();
            }
        }

        local hint = SpawnEntityFromTable("env_instructor_hint", {
            targetname = "bhop_hint_" + index,
            hint_name = "bhop_slot_" + index,
            hint_replace_key = "bhop_slot_" + index,
            hint_caption = message,
            hint_color = color,
            hint_icon_onscreen = iconName,
            hint_timeout = 1.0,
            hint_static = 1,        // Center HUD static box
            hint_nofadeout = 1,     // No fade-out swipe animation
            hint_pulseoption = 0,   // No zooming/pulsing
            hint_forcecaption = 1,
            hint_nooffscreen = 1,
            hint_suppress_rest = 1, // Suppresses other game hints
            hint_flags = 0
        });

        if (hint != null && hint.IsValid())
        {
            ::BhopVars.playerHints[index] <- hint;
            DoEntFire("!self", "ShowHint", "", 0, player, hint);
        }
    },

    Think = function()
    {
        local player = null;
        while ((player = Entities.FindByClassname(player, "player")) != null)
        {
            if (!::BhopFunc.IsAlive(player) || IsPlayerABot(player))
                continue;

            local index = player.GetEntityIndex();
            local flags = NetProps.GetPropInt(player, "m_fFlags");
            local isOnGround = (flags & FL_ONGROUND) != 0;
            local wasOnGround = ::BhopVars.WasOnGround[index];

            // Landing Transition: Air -> Ground
            if (!wasOnGround && isOnGround)
            {
                local currentLandingSpeed = ::BhopFunc.GetHorizontalSpeed(player);
                local prevLandingSpeed = ::BhopVars.LastLandingSpeed[index];

                // Displays starting from the 2nd jump landing onward
                if (prevLandingSpeed > 0.0)
                {
                    local delta = currentLandingSpeed - prevLandingSpeed;
                    local sign = (delta >= 0.0) ? "+" : "";
                    local message = "Vel: " + ::BhopFunc.FormatFloat(currentLandingSpeed) + 
                                    " | Gain: " + sign + ::BhopFunc.FormatFloat(delta);

                    // Green + icon_arrow_up on Gain | Red + icon_alert on Loss
                    local hintColor = (delta >= 0.0) ? "0 255 120" : "255 80 80";
                    local hintIcon  = (delta >= 0.0) ? "icon_arrow_up" : "icon_alert";

                    ::BhopFunc.ShowHintText(player, message, hintIcon, hintColor);
                }

                ::BhopVars.LastLandingSpeed[index] = currentLandingSpeed;
                ::BhopVars.GroundTicks[index] = 0;
            }
            else if (isOnGround)
            {
                ::BhopVars.GroundTicks[index]++;

                // Reset streak if touching ground too long (walked, lingered, or stopped)
                if (::BhopVars.GroundTicks[index] > ::BhopVars.MaxGroundTicks)
                {
                    ::BhopVars.LastLandingSpeed[index] = 0.0;
                }
            }

            ::BhopVars.WasOnGround[index] = isOnGround;
        }

        return 0.015;
    }
}

::BhopEvent <-
{
    OnGameEvent_player_disconnect = function(params)
    {
        local player = GetPlayerFromUserID(params.userid);
        if (player && player.IsValid())
        {
            local index = player.GetEntityIndex();
            
            if (index in ::BhopVars.playerHints)
            {
                local hint = ::BhopVars.playerHints[index];
                if (hint != null && hint.IsValid())
                {
                    hint.Kill();
                }
                delete ::BhopVars.playerHints[index];
            }

            ::BhopVars.LastLandingSpeed[index] = 0.0;
            ::BhopVars.GroundTicks[index] = 0;
            ::BhopVars.WasOnGround[index] = true;
        }
    }
}

::BhopFunc.addThinkTimer();
__CollectEventCallbacks(::BhopEvent, "OnGameEvent_", "GameEventCallbacks", RegisterScriptGameEventListener);