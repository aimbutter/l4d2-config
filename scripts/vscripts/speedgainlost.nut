// Copy beepclear.wav to your sound folder so you won't get annoyed.
// This thing counts the jump only and not your bhop streak.
// The counter will reset if you have touched the ground for more than 3 seconds.

SendToConsole("gameinstructor_enable 1");
SendToConsole("cl_autohelp 0");
SendToConsole("locator_split_len 0");

// ==========================================
// Speed Tracker
// ==========================================
printl("<mt2> Bhop Tracker Script Loaded ------------------------------------")

const FL_ONGROUND = 1;

::BhopVars <-
{
    BunnyHopTimerEnabled = false,
    LastLandingSpeed = array(32, 0.0), // Stores previous landing speed
    TakeoffSpeed = array(32, 0.0),     // Stores speed when leaving ground on jump 1
    HasLandedOnce = array(32, false),  // Tracks if jump 1 has already landed
    JumpCount = array(32, 0),          // Jump streak counter
    WasOnGround = array(32, true),     // Ground state tracking
    GroundTicks = array(32, 0),        // Ground contact frames
    MaxGroundTicks = 3,                // Max frames on ground before streak resets
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
            local currentSpeed = ::BhopFunc.GetHorizontalSpeed(player);

            // Takeoff: Ground -> Air
            if (wasOnGround && !isOnGround)
            {
                if (!::BhopVars.HasLandedOnce[index])
                {
                    ::BhopVars.TakeoffSpeed[index] = currentSpeed;
                }
            }
            // Landing: Air -> Ground
            else if (!wasOnGround && isOnGround)
            {
                local delta = 0.0;
                ::BhopVars.JumpCount[index]++;

                if (!::BhopVars.HasLandedOnce[index])
                {
                    // Jump 1: Compare landing speed against takeoff speed
                    delta = currentSpeed - ::BhopVars.TakeoffSpeed[index];
                    ::BhopVars.HasLandedOnce[index] = true;
                }
                else
                {
                    // Jump 2+: Compare landing speed against previous landing speed
                    delta = currentSpeed - ::BhopVars.LastLandingSpeed[index];
                }

                local sign = (delta >= 0.0) ? "+" : "";
                local message = "Jump: " + ::BhopVars.JumpCount[index] + 
                                " | Vel: " + ::BhopFunc.FormatFloat(currentSpeed) + 
                                " | Gain: " + sign + ::BhopFunc.FormatFloat(delta);

                // Green + icon_arrow_up on Gain | Red + icon_alert on Loss
                local hintColor = (delta >= 0.0) ? "0 255 120" : "255 80 80";
                local hintIcon  = (delta >= 0.0) ? "icon_arrow_up" : "icon_alert";

                ::BhopFunc.ShowHintText(player, message, hintIcon, hintColor);

                ::BhopVars.LastLandingSpeed[index] = currentSpeed;
                ::BhopVars.GroundTicks[index] = 0;
            }
            else if (isOnGround)
            {
                ::BhopVars.GroundTicks[index]++;

                // Reset streak if touching ground too long (walked, lingered, or stopped)
                if (::BhopVars.GroundTicks[index] > ::BhopVars.MaxGroundTicks)
                {
                    ::BhopVars.LastLandingSpeed[index] = 0.0;
                    ::BhopVars.TakeoffSpeed[index] = 0.0;
                    ::BhopVars.HasLandedOnce[index] = false;
                    ::BhopVars.JumpCount[index] = 0;
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
            ::BhopVars.TakeoffSpeed[index] = 0.0;
            ::BhopVars.HasLandedOnce[index] = false;
            ::BhopVars.JumpCount[index] = 0;
            ::BhopVars.GroundTicks[index] = 0;
            ::BhopVars.WasOnGround[index] = true;
        }
    }
}

::BhopFunc.addThinkTimer();
__CollectEventCallbacks(::BhopEvent, "OnGameEvent_", "GameEventCallbacks", RegisterScriptGameEventListener);
