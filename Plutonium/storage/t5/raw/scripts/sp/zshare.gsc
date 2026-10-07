/*
======================================================================
    ZSHARE T5 v1.3  --  Weapon sharing for Black Ops Zombies
    Plutonium T5

    by Xep

======================================================================

    A port of ZShare (Plutonium T6) to Black Ops. Everything you can
    hand a teammate, from the button you buy everything else with:

        Weapons   Look at a teammate and press use. They see the gun in
                  your hands, look back at you and press use, and the
                  two weapons change hands -- ammo, attachment and
                  Pack-a-Punch camo travel with them.
        Points    Crouch first, then use: 1000 points go across.
        Box hits  Paid for a box weapon you do not want? Crouch and
                  press use at the box, and it is anyone's to take. The
                  same at the Pack-a-Punch machine.
        Paying    Crouch and press use at a perk machine, or at the box
                  or the Pack-a-Punch while nobody is using it, and the
                  next teammate to use that machine pays nothing.

        Install   %localappdata%\Plutonium\storage\t5\raw\scripts\sp

    Zombies scripts go in sp: Black Ops zombies runs on the singleplayer
    tree. There is no mod packaging for this game -- Plutonium's mods
    folder and its Mods menu are Black Ops II only -- so the script is
    the whole delivery.

    Everything runs on the host. Nobody else needs this file.

----------------------------------------------------------------------
    HOW IT DIFFERS FROM THE T6 BUILD

    Black Ops II hands a script hooks this game does not have: a box
    trigger built per player, a validation call before a perk's price, a
    helper that reads a weapon whole. So the machines here are driven a
    step closer to the metal -- the box's think loop and the
    Pack-a-Punch's are replaced outright, and a paid drink is poured by
    ZShare's own prompt through the stock drinking code -- and a weapon
    is read and given piece by piece. What a player sees and does is the
    same. docs/porting-t5.md in the project has the detail.

----------------------------------------------------------------------
    VERIFICATION

    There is no compiler for this engine: Plutonium T5 loads raw source
    and compiles it at load. In its place, every call is checked against
    the stock T5 dump as a real call a zombies script can reach, and
    every field, notify, flag and sound it borrows is checked for
    existence there too. See audit.py and deep_check.py.

----------------------------------------------------------------------
    CREDITS

        Xep           author
        Treyarch      _zombiemode_weapons.gsc, _zombiemode_perks.gsc --
                      everything this stands on
        plutoniummod  t5-scripts, the stock script reference

----------------------------------------------------------------------
    LICENSE

        MIT -- see LICENSE. Keep this header on copies.

======================================================================
*/

/*
    These two are the only includes that resolve. The zombiemode scripts
    are not in the loaded tree when a raw script is compiled, so neither
    an #include of maps\_zombiemode_utility nor a qualified call into it
    can compile -- either stops Black Ops at boot. Everything from that
    tree is reached at runtime through getFunction(), the way Plutonium's
    own T5 scripts do it; see FUNCTIONS.
*/
#include maps\_utility;
#include common_scripts\utility;


/* ==================================================================
    ENTRY POINT
   ================================================================== */

/*
    main() runs before _zombiemode.gsc threads the box and the machines,
    which is the one moment a stock loop can be replaced and have every
    copy of it be ZShare's. Plutonium's own zm_spawn_fix.gsc replaces its
    functions from main() for the same reason.
*/
main()
{
    if ( getdvarint( "zombietron" ) )
        return;

    zs_replace_stock();
    init();
}

init()
{
    if ( is_true( level.zs_loaded ) )
        return;

    // Dead Ops Arcade shares this script tree and none of its systems.
    if ( getdvarint( "zombietron" ) )
        return;

    level.zs_loaded = 1;

    zs_load_config();

    /*
        Switched off. The descriptor still goes up, because "not
        installed" and "installed and switched off" are different answers
        to a mod asking what ZShare is doing in this match.
    */
    if ( !level.zs.enabled )
    {
        zs_api_register( 0 );
        return;
    }

    zs_functions();

    level.zs_triggers = [];
    level.zs_player_sig = "";

    level thread zs_connect_watcher();
    level thread zs_chat_listener();
    level thread zs_trigger_updater();
    level thread zs_config_watcher();
    level thread zs_config_printer();
    level thread zs_build_watermark();

    // Last, so the first thing that reads it finds a mod already up.
    zs_api_register( 1 );
}


/* ==================================================================
    FUNCTIONS

    Every stock zombiemode function this script calls, looked up once by
    path and name. A lookup that finds nothing leaves the pointer
    undefined, and each wrapper below falls back to the plainest version
    of the same test rather than failing.
   ================================================================== */

zs_functions()
{
    level.zs_f_valid          = getfunction( "maps/_zombiemode_utility", "is_player_valid" );
    level.zs_f_revive_trigger = getfunction( "maps/_zombiemode_utility", "in_revive_trigger" );
    level.zs_f_drinking       = getfunction( "maps/_zombiemode_utility", "is_drinking" );
    level.zs_f_hacker         = getfunction( "maps/_zombiemode_utility", "hacker_active" );
    level.zs_f_offhand        = getfunction( "maps/_zombiemode_utility", "is_offhand_weapon" );
    level.zs_f_powerup_weapon = getfunction( "maps/_zombiemode_utility", "has_powerup_weapon" );

    level.zs_f_upgraded       = getfunction( "maps/_zombiemode_weapons", "is_weapon_upgraded" );
    level.zs_f_has_family     = getfunction( "maps/_zombiemode_weapons", "has_weapon_or_upgrade" );
    level.zs_f_toggle_take    = getfunction( "maps/_zombiemode_weapons", "unacquire_weapon_toggle" );
    level.zs_f_toggle_give    = getfunction( "maps/_zombiemode_weapons", "acquire_weapon_toggle" );
    level.zs_f_weapon_vo      = getfunction( "maps/_zombiemode_weapons", "play_weapon_vo" );

    level.zs_f_score_add      = getfunction( "maps/_zombiemode_score", "add_to_player_score" );
    level.zs_f_score_minus    = getfunction( "maps/_zombiemode_score", "minus_to_player_score" );
}

zs_player_valid( player )
{
    if ( !isdefined( player ) || !isplayer( player ) || !isalive( player ) )
        return 0;

    if ( isdefined( level.zs_f_valid ) )
        return [[ level.zs_f_valid ]]( player );

    return player.sessionstate == "playing";
}

zs_in_revive_trigger( player )
{
    if ( !isdefined( level.zs_f_revive_trigger ) )
        return 0;

    return player [[ level.zs_f_revive_trigger ]]();
}

zs_drinking( player )
{
    if ( isdefined( level.zs_f_drinking ) )
        return player [[ level.zs_f_drinking ]]();

    return isdefined( player.is_drinking ) && player.is_drinking;
}

zs_hacker_out( player )
{
    if ( !isdefined( level.zs_f_hacker ) )
        return 0;

    return player [[ level.zs_f_hacker ]]();
}

zs_is_offhand( weapon )
{
    if ( !isdefined( level.zs_f_offhand ) )
        return 0;

    return [[ level.zs_f_offhand ]]( weapon );
}

zs_has_powerup_weapon( player )
{
    if ( isdefined( level.zs_f_powerup_weapon ) )
        return player [[ level.zs_f_powerup_weapon ]]();

    return is_true( player.has_powerup_weapon );
}

zs_is_upgraded( weapon )
{
    if ( isdefined( level.zs_f_upgraded ) )
        return [[ level.zs_f_upgraded ]]( weapon );

    return issubstr( weapon, "_upgraded" );
}

/*
    Points onto a player through the stock helper, which draws the +N
    popup the way every stock purchase does. The second argument is
    false because a gift or a refund is not points earned: score_total is
    what the end screen and the career stat count.
*/
zs_score_add( player, amount )
{
    if ( isdefined( level.zs_f_score_add ) )
    {
        player [[ level.zs_f_score_add ]]( amount, false );
        return;
    }

    player.score = player.score + amount;
}

zs_score_minus( player, amount )
{
    if ( isdefined( level.zs_f_score_minus ) )
    {
        player [[ level.zs_f_score_minus ]]( amount );
        return;
    }

    player.score = player.score - amount;
}


/* ==================================================================
    CONFIG

    Every value below is also a dvar of the same name, created with its
    default on load so the console can reach it. Re-read every five
    seconds and on every press, so a change applies without a restart.
   ================================================================== */

zs_load_config()
{
    // Reused rather than reallocated -- spawnstruct() takes a parent
    // script variable, and this runs on every press.
    if ( !isdefined( level.zs ) )
        level.zs = spawnstruct();

    // --- general ---------------------------------------------------

    /*
        ZShare itself. On by default. Off, the script still loads, still
        says so on level.zmods -- with enabled 0 -- and does nothing else:
        no prompts, no hooks over the stock scripts, no chat words and no
        threads. The match runs as it would with the file gone.

        Read once, as the match loads. Taking prompts off players and
        handing replaced stock functions back is not something a switch
        can do safely in the middle of a game, so this one lands on the
        next match -- which is what a bundle's MODS page says about it.
    */
    level.zs.enabled = zs_cfg_int( "zs_enabled", 1 );

    // --- debug -----------------------------------------------------

    // Print what the script decides and why, to the console and the host.
    level.zs.debug            = zs_cfg_int( "zs_debug", 0 );

    // --- trading ---------------------------------------------------

    // Trade weapons with a teammate: use on them to offer, use back to accept.
    level.zs.trade            = zs_cfg_int( "zs_trade", 1 );

    // How long an offer stays open before it lapses on its own.
    level.zs.trade_offer_time = zs_cfg_float( "zs_trade_offer_time", 10 );

    /*
        Whether a Pack-a-Punched weapon can be traded. On by default --
        handing a friend the upgraded gun is most of the point -- but a
        server that wants every player to pay their own 5000 can turn it
        off, and the prompt then says so.
    */
    level.zs.trade_upgraded   = zs_cfg_int( "zs_trade_upgraded", 1 );

    /*
        How close you have to be for the prompt to appear, in units. An
        offer lapses on its own once the two of you are more than twice
        this apart. Read when a prompt is built, so a change reaches the
        prompts within a second.
    */
    level.zs.range            = zs_cfg_int( "zs_range", 64 );

    // --- points ----------------------------------------------------

    // Crouch, look at a teammate and press use to give them points.
    level.zs.points           = zs_cfg_int( "zs_points", 1 );
    level.zs.points_amount    = zs_cfg_int( "zs_points_amount", 1000 );

    // Seconds between gifts from one player, so a held button does not
    // empty a bank in a second.
    level.zs.points_cooldown  = zs_cfg_float( "zs_points_cooldown", 1 );

    // --- thanks ----------------------------------------------------

    /*
        Thank somebody who paid for you, gave up a box hit or handed you
        points: for a while the crouched prompt on them offers a small
        thank instead of the full gift, and !thank does the same from
        anywhere. !tip sends any amount to anybody, favour or not. The
        points come out of the thanker either way, so nothing is minted.
    */
    level.zs.thank            = zs_cfg_int( "zs_thank", 1 );
    level.zs.thank_amount     = zs_cfg_int( "zs_thank_amount", 100 );

    // How long a good turn stays thankable, in seconds.
    level.zs.thank_time       = zs_cfg_float( "zs_thank_time", 30 );

    // --- sharing ---------------------------------------------------

    /*
        Share a box hit: crouch and press use at the box while the weapon
        you paid for is up, and anybody can take it. The box weapon stays
        up for the same twelve seconds either way.
    */
    level.zs.box_share        = zs_cfg_int( "zs_box_share", 1 );

    // The same at the Pack-a-Punch, for the upgraded weapon waiting there.
    level.zs.pap_share        = zs_cfg_int( "zs_pap_share", 1 );

    // --- paying ----------------------------------------------------

    /*
        Pay for a teammate. Crouch and press use at a perk machine, or at
        the box or the Pack-a-Punch while nobody is using it, and the next
        teammate to use that machine pays nothing. One payment waits at a
        machine at a time, and a crouched press from whoever paid takes it
        back.

        Off stops new payments only. One already waiting still works and
        can still be taken back.
    */
    level.zs.perk_pay         = zs_cfg_int( "zs_perk_pay", 1 );
    level.zs.box_pay          = zs_cfg_int( "zs_box_pay", 1 );
    level.zs.pap_pay          = zs_cfg_int( "zs_pap_pay", 1 );

    // --- perks -----------------------------------------------------

    /*
        How many perks one player can hold. 0 is the game's own limit,
        four. Any other number replaces it, and -1 is no limit at all.

        Black Ops writes its four into the purchase loop itself, so a
        different limit is kept by ZShare: a player at the limit is shown
        no stock prompt, and a player allowed past four buys the drink
        through ZShare's prompt on the machine instead.
    */
    level.zs.perk_limit       = zs_cfg_int( "zs_perk_limit", 0 );

    // --- presentation ----------------------------------------------

    // Tell players what the prompts do, once, shortly after they spawn.
    level.zs.show_hint        = zs_cfg_int( "zs_show_hint", 1 );

    // The one-line messages. Off leaves the prompts and the sounds.
    level.zs.messages         = zs_cfg_int( "zs_messages", 1 );

    // --- sounds ----------------------------------------------------

    /*
        Stock aliases, so the script stays one drop-in file. Set any to
        none for silence.
    */
    level.zs.offer_sound      = zs_cfg_str( "zs_offer_sound", "zmb_perks_packa_ready" );
    level.zs.trade_sound      = zs_cfg_str( "zs_trade_sound", "zmb_whoosh" );
    level.zs.share_sound      = zs_cfg_str( "zs_share_sound", "zmb_perks_packa_ready" );
    level.zs.points_sound     = zs_cfg_str( "zs_points_sound", "zmb_cha_ching" );
    level.zs.deny_sound       = zs_cfg_str( "zs_deny_sound", "zmb_no_cha_ching" );

    // Height of the prompt volume, in units. Not a setting.
    level.zs.height = 72;
}

/*
    Black Ops keeps set_dvar_if_unset() in the multiplayer utility only,
    where a zombies script cannot reach it, so the same thing is done by
    hand: create the dvar with its default the first time, because the
    console can only assign to a dvar that already exists.

    An empty dvar reads as one that was never set and gets its default
    written straight back, so "" typed into the console would last until
    the next read. "none" is how a string setting is emptied instead.
*/
zs_cfg_str( dvar, def )
{
    if ( getdvar( dvar ) == "" )
        setdvar( dvar, def );

    value = zs_cfg_echo( dvar, getdvar( dvar ), def );

    if ( value == "none" )
        return "";

    return value;
}

zs_cfg_int( dvar, def )
{
    return int( zs_cfg_str( dvar, "" + def ) );
}

zs_cfg_float( dvar, def )
{
    return float( zs_cfg_str( dvar, "" + def ) );
}


/* ==================================================================
    INPUT -- CHAT

    One word. Everything else is a prompt, and a prompt is better than
    a word for an action aimed at a person or a machine -- but a box hit
    can be shared without walking back to the box.
   ================================================================== */

zs_chat_listener()
{
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "say", message, player );

        if ( !isdefined( message ) || !isdefined( player ) )
            continue;

        if ( !isstring( message ) || !isplayer( player ) )
            continue;

        msg = tolower( message );

        if ( zs_word_is( msg, "!thank" ) || zs_word_is( msg, "!t" ) )
        {
            level thread zs_chat_thank( player );
            continue;
        }

        rest = zs_word_after( msg, "!tip" );

        if ( isdefined( rest ) )
        {
            level thread zs_chat_tip( player, rest );
            continue;
        }

        if ( zs_word_is( msg, "!share" ) )
            level thread zs_chat_share( player );
    }
}

/*
    Plutonium's say notify can hand the message over behind a stray
    control character, as it does on T6. Every comparison is made twice:
    on the message, and on the message less its first character.
*/
/*
    What follows a word, or undefined when the message is not that word.
    The same two comparisons zs_word_is makes, for the same reason.
*/
zs_word_after( msg, token )
{
    /*
        getsubstr()'s third argument is where to stop, not how many
        characters to take -- stock reads a map name with
        getsubstr( mapname, 3, mapname.size ) and chops three characters
        with getsubstr( weapon, 0, weapon.size - 3 ). Given token.size
        there, the skipped-character form compared one character too few
        and never matched, so !tip was dead on any client that puts a
        character in front of the message.

        And the word has to end where the token does: "!tipsy" is not
        "!tip", and reading its "sy" as an amount is how a chat line
        nobody meant for ZShare reached the tip code.
    */
    if ( zs_word_starts( msg, 0, token ) )
        return zs_trim( getsubstr( msg, token.size ) );

    if ( msg.size > 1 && zs_word_starts( msg, 1, token ) )
        return zs_trim( getsubstr( msg, 1 + token.size ) );

    return undefined;
}

zs_word_starts( msg, at, token )
{
    end = at + token.size;

    if ( msg.size < end )
        return 0;

    if ( getsubstr( msg, at, end ) != token )
        return 0;

    // The whole message, or a space after it.
    return msg.size == end || getsubstr( msg, end, end + 1 ) == " ";
}

zs_trim( s )
{
    while ( s.size > 0 && s[0] == " " )
        s = getsubstr( s, 1 );

    while ( s.size > 0 && s[s.size - 1] == " " )
        s = getsubstr( s, 0, s.size - 1 );

    return s;
}

zs_chat_thank( player )
{
    zs_load_config();

    if ( !isdefined( player ) || !level.zs.thank )
        return;

    to = player zs_favour_who();

    if ( !isdefined( to ) )
    {
        player zs_say( "Nobody has done you a good turn just now" );
        return;
    }

    player zs_thank( to );
}

zs_chat_tip( player, rest )
{
    zs_load_config();

    if ( isdefined( player ) )
        player zs_tip( rest );
}

zs_word_is( msg, token )
{
    if ( msg == token )
        return 1;

    if ( msg.size > 1 && getsubstr( msg, 1 ) == token )
        return 1;

    return 0;
}

/*
    Share whatever of yours is waiting -- a box weapon, or an upgraded
    one at the Pack-a-Punch. It asks what the crouched press asks, less
    the crouch.
*/
zs_chat_share( player )
{
    zs_load_config();

    if ( !isdefined( player ) )
        return;

    if ( isdefined( level.chests ) )
    {
        for ( i = 0; i < level.chests.size; i++ )
        {
            chest = level.chests[i];

            if ( !zs_chest_shareable( chest, player ) )
                continue;

            chest zs_chest_share( player );
            return;
        }
    }

    paps = getentarray( "zombie_vending_upgrade", "targetname" );

    for ( i = 0; i < paps.size; i++ )
    {
        if ( !zs_pap_shareable( paps[i], player ) )
            continue;

        paps[i] zs_pap_share( player );
        return;
    }

    player zs_say( "Nothing of yours is waiting at the box or the Pack-a-Punch" );
}


/* ==================================================================
    PLAYERS
   ================================================================== */

zs_connect_watcher()
{
    level endon( "end_game" );

    players = get_players();
    for ( i = 0; i < players.size; i++ )
        players[i] thread zs_player_think();

    for (;;)
    {
        level waittill( "connected", player );
        player thread zs_player_think();
    }
}

zs_player_think()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    if ( is_true( self.zs_thinking ) )
        return;

    self.zs_thinking = 1;

    for (;;)
    {
        self waittill( "spawned_player" );

        // A respawn puts the player back into the world, and a prompt is
        // linked to the player it belongs to.
        zs_relink_prompts( self );

        if ( level.zs.show_hint && !is_true( self.zs_hinted ) )
        {
            self.zs_hinted = 1;
            self thread zs_hint();
        }
    }
}

zs_hint()
{
    self endon( "disconnect" );
    wait 8;

    if ( level.zs.trade && level.zs.points )
        self iprintln( "^3[ZShare]^7 look at a teammate and press ^3use^7 to trade weapons, or crouch first to give them " + level.zs.points_amount + " points" );
    else if ( level.zs.trade )
        self iprintln( "^3[ZShare]^7 look at a teammate and press ^3use^7 to trade weapons" );
    else if ( level.zs.points )
        self iprintln( "^3[ZShare]^7 crouch, look at a teammate and press ^3use^7 to give them " + level.zs.points_amount + " points" );

    if ( level.zs.box_share && level.zs.pap_share )
        self iprintln( "^3[ZShare]^7 crouch and press ^3use^7 at the box or the Pack-a-Punch to share your hit" );
    else if ( level.zs.box_share )
        self iprintln( "^3[ZShare]^7 crouch and press ^3use^7 at the box to share your hit" );
    else if ( level.zs.pap_share )
        self iprintln( "^3[ZShare]^7 crouch and press ^3use^7 at the Pack-a-Punch to share your upgrade" );

    places = zs_pay_places();

    if ( places != "" )
        self iprintln( "^3[ZShare]^7 crouch and press ^3use^7 at " + places + " to pay for a teammate" );
}

zs_pay_places()
{
    places = [];

    if ( level.zs.perk_pay )
        places[places.size] = "a perk machine";

    if ( level.zs.box_pay )
        places[places.size] = "the box";

    if ( level.zs.pap_pay )
        places[places.size] = "the Pack-a-Punch";

    if ( places.size == 0 )
        return "";

    if ( places.size == 1 )
        return places[0];

    if ( places.size == 2 )
        return places[0] + " or " + places[1];

    return places[0] + ", " + places[1] + " or " + places[2];
}

/*
    Whether a player can take part in anything right now: alive and on
    their feet, not spectating, not mid-drink, and not with the hacker
    out -- the same list the box checks before it takes your money.
*/
zs_player_ok( player )
{
    if ( !zs_player_valid( player ) )
        return 0;

    if ( zs_drinking( player ) )
        return 0;

    if ( zs_hacker_out( player ) )
        return 0;

    return 1;
}

/*
    Whether a player can pay at a machine, or take a payment back.
    Everything above, and not standing over a downed teammate: a crouch
    next to somebody on the floor is a revive, and the stock machines
    step aside for it the same way.
*/
zs_payer_ok( player )
{
    if ( !zs_player_ok( player ) )
        return 0;

    if ( zs_in_revive_trigger( player ) )
        return 0;

    if ( is_true( level.intermission ) )
        return 0;

    return 1;
}

/*
    Both of them. Black Ops has no teams to keep apart: every zombies
    mode is one squad.
*/
zs_pair_ok( a, b )
{
    if ( !zs_player_ok( a ) || !zs_player_ok( b ) )
        return 0;

    if ( a == b )
        return 0;

    if ( is_true( level.intermission ) )
        return 0;

    return 1;
}

// Paying needs somebody to pay for.
zs_pay_team_check()
{
    return get_players().size >= 2;
}

/*
    The stance itself rather than a button, so toggle-crouch and
    hold-crouch read the same. Prone counts: it is further down than
    crouched, and nobody goes prone to trade a gun.
*/
zs_crouched( player )
{
    if ( !isdefined( player ) )
        return 0;

    stance = player getstance();
    return stance == "crouch" || stance == "prone";
}


/* ==================================================================
    PROMPTS ON PLAYERS

    One use trigger per (teammate, viewer) pair, linked to the teammate
    and visible only to the viewer. Per pair rather than per teammate
    because the words depend on who is reading them: "accept the trade"
    is only true for the player the offer was made to, and "give 1000
    points" only for a viewer who is crouched.

    Every string on a prompt is one of a fixed handful. Hint strings are
    configstrings -- a finite pool that does not recycle -- so a weapon
    or player name never goes into one. Names go in the chat line.

    The use key is written [{+activate}], as Shangri-La's weapon locker
    writes it in a plain hint of its own.
   ================================================================== */

zs_prompt_make( target, viewer )
{
    /*
        The hacker's recipe from Moon -- a trigger_radius_use with its
        cursor and look-at settings -- linked to the player the way the
        ballistic knife's retrieval trigger links to what it lands in.

        Black Ops has no setinvisibletoall() for zombies: a new trigger is
        visible to everybody, and is hidden from each player in turn. A
        player who joins later is hidden from it when the player list
        changes; see zs_trigger_updater().

        Origin 36 up from the feet, where a player looks at another player.
    */
    t = spawn( "trigger_radius_use", target.origin + ( 0, 0, 36 ), 0, level.zs.range, level.zs.height );
    t setcursorhint( "HINT_NOICON" );
    t usetriggerrequirelookat();
    t sethintstring( "" );

    // Once only: stock notes that setting it again is an error.
    t enablelinkto();
    t linkto( target );

    t.zs_target = target;
    t.zs_viewer = viewer;
    t.zs_radius = level.zs.range;
    t.zs_hint = "";
    t.zs_shown = 0;

    zs_prompt_hide_all( t );

    t thread zs_prompt_think();

    level.zs_triggers[level.zs_triggers.size] = t;

    zs_debug( "prompt built: " + target.name + " for " + viewer.name );

    return t;
}

zs_prompt_hide_all( t )
{
    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) )
            continue;

        if ( isdefined( t.zs_viewer ) && players[i] == t.zs_viewer && t.zs_shown )
            continue;

        t setinvisibletoplayer( players[i], true );
    }
}

zs_prompt_find( target, viewer )
{
    for ( i = 0; i < level.zs_triggers.size; i++ )
    {
        t = level.zs_triggers[i];

        if ( !isdefined( t ) || !isdefined( t.zs_target ) || !isdefined( t.zs_viewer ) )
            continue;

        if ( t.zs_target == target && t.zs_viewer == viewer )
            return t;
    }

    return undefined;
}

/*
    Every ordered pair of players has a prompt. Run on a tick rather than
    on connect, so a late joiner, a rebuilt prompt and a changed range all
    heal the same way.
*/
zs_prompts_ensure()
{
    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        for ( j = 0; j < players.size; j++ )
        {
            if ( i == j )
                continue;

            if ( !isdefined( players[i] ) || !isdefined( players[j] ) )
                continue;

            if ( !isdefined( zs_prompt_find( players[i], players[j] ) ) )
                zs_prompt_make( players[i], players[j] );
        }
    }
}

/*
    The player list as one string. When it changes, somebody joined, and
    every prompt is hidden from them before they can read one meant for
    somebody else.
*/
zs_player_signature()
{
    sig = "";
    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) )
            sig = sig + players[i] getentitynumber() + ",";
    }

    return sig;
}

zs_relink_prompts( target )
{
    for ( i = 0; i < level.zs_triggers.size; i++ )
    {
        t = level.zs_triggers[i];

        if ( !isdefined( t ) || !isdefined( t.zs_target ) || t.zs_target != target )
            continue;

        t unlink();
        t.origin = target.origin + ( 0, 0, 36 );
        t linkto( target );
    }
}

zs_prompt_free( t )
{
    if ( !isdefined( t ) )
        return;

    t notify( "zs_kill" );
    t unlink();
    t delete();
}

/*
    The one loop behind every prompt on a player: who can see it, and
    what it says. Ten times a second, and the hint string is only written
    when it changes.
*/
zs_trigger_updater()
{
    level endon( "end_game" );

    tick = 0;

    for (;;)
    {
        wait 0.1;

        tick++;

        if ( tick % 10 == 0 )
        {
            zs_prompts_ensure();

            sig = zs_player_signature();

            if ( sig != level.zs_player_sig )
            {
                level.zs_player_sig = sig;

                for ( i = 0; i < level.zs_triggers.size; i++ )
                {
                    if ( isdefined( level.zs_triggers[i] ) )
                        zs_prompt_hide_all( level.zs_triggers[i] );
                }
            }
        }

        keep = [];

        for ( i = 0; i < level.zs_triggers.size; i++ )
        {
            t = level.zs_triggers[i];

            if ( !isdefined( t ) )
                continue;

            if ( !isdefined( t.zs_target ) || !isdefined( t.zs_viewer ) || t.zs_radius != level.zs.range )
            {
                zs_prompt_free( t );
                continue;
            }

            t zs_prompt_update();
            keep[keep.size] = t;
        }

        level.zs_triggers = keep;
    }
}

zs_prompt_update()
{
    target = self.zs_target;
    viewer = self.zs_viewer;

    want = zs_prompt_text( target, viewer );

    if ( want == "" )
    {
        if ( self.zs_shown )
        {
            self setinvisibletoplayer( viewer, true );
            self.zs_shown = 0;
        }

        return;
    }

    if ( want != self.zs_hint )
    {
        self sethintstring( want );
        self.zs_hint = want;
    }

    if ( !self.zs_shown )
    {
        self setinvisibletoplayer( viewer, false );
        self.zs_shown = 1;
    }
}

/*
    What the viewer reads on the target, or "" for no prompt at all.
*/
zs_prompt_text( target, viewer )
{
    if ( !zs_pair_ok( target, viewer ) )
        return "";

    if ( level.zs.points && zs_crouched( viewer ) )
    {
        /*
            A thank takes the crouched press while one is owed, because
            crouch already means "give them something" and a thank is a
            smaller one with a reason.
        */
        if ( viewer zs_owes_thanks( target ) )
            return "Hold ^3[{+activate}]^7 to thank them (" + level.zs.thank_amount + " points)";

        return "Hold ^3[{+activate}]^7 to give " + level.zs.points_amount + " points";
    }

    if ( !level.zs.trade )
        return "";

    if ( zs_offer_is( target, viewer ) )
        return "Hold ^3[{+activate}]^7 to accept the trade";

    if ( zs_offer_is( viewer, target ) )
        return "Hold ^3[{+activate}]^7 to cancel the trade";

    return "Hold ^3[{+activate}]^7 to trade weapons";
}

zs_prompt_think()
{
    self endon( "zs_kill" );
    level endon( "end_game" );

    for (;;)
    {
        self waittill( "trigger", user );

        if ( !isdefined( user ) || !isdefined( self.zs_target ) || !isdefined( self.zs_viewer ) )
            continue;

        // Hidden from everybody else, so this is belt and braces.
        if ( user != self.zs_viewer )
            continue;

        zs_load_config();
        user zs_use_on( self.zs_target );

        // One press, one action.
        wait 0.3;
    }
}

zs_use_on( target )
{
    if ( !zs_pair_ok( self, target ) )
        return;

    if ( level.zs.points && zs_crouched( self ) )
    {
        if ( self zs_owes_thanks( target ) )
            self zs_thank( target );
        else
            self zs_points_give( target );

        return;
    }

    if ( !level.zs.trade )
        return;

    // They offered to me: this press is the acceptance.
    if ( zs_offer_is( target, self ) )
    {
        zs_trade_do( target, self );
        return;
    }

    // I already offered to them: this press takes it back.
    if ( zs_offer_is( self, target ) )
    {
        self zs_offer_cancel( "withdrawn" );
        return;
    }

    self zs_offer_make( target );
}


/* ==================================================================
    TRADING

    An offer lives on the player who made it: who it is to, which weapon,
    and when it lapses. One at a time, spent the moment it is accepted,
    cancelled or times out, and numbered so a lapsed offer's watcher
    never touches a newer one.

    What is offered is the weapon in your hands when you press, and what
    comes back is the weapon in theirs when they accept.
   ================================================================== */

zs_offer_is( from, to )
{
    if ( !isdefined( from ) || !isdefined( to ) )
        return 0;

    return isdefined( from.zs_offer_to ) && from.zs_offer_to == to;
}

zs_offer_make( to )
{
    weapon = self zs_held_weapon();
    why = self zs_untradeable( weapon );

    if ( why != "" )
    {
        self zs_deny( why );
        return;
    }

    if ( isdefined( self.zs_offer_to ) )
        self zs_offer_cancel( "replaced" );

    if ( !isdefined( self.zs_offer_serial ) )
        self.zs_offer_serial = 0;

    self.zs_offer_serial++;
    self.zs_offer_to = to;
    self.zs_offer_weapon = weapon;
    self.zs_offer_until = gettime() + int( level.zs.trade_offer_time * 1000 );

    self thread zs_offer_watcher( self.zs_offer_serial );

    self zs_say( "Offered your weapon to ^3" + to.name + "^7 -- they have " + int( level.zs.trade_offer_time ) + " seconds to accept" );
    to zs_say( "^3" + self.name + "^7 wants to trade weapons -- look at them and press ^3use^7 to accept" );
    to zs_sound( level.zs.offer_sound );

    zs_debug( self.name + " offers " + weapon + " to " + to.name );
}

zs_offer_clear()
{
    self.zs_offer_to = undefined;
    self.zs_offer_weapon = undefined;
    self.zs_offer_until = undefined;

    if ( isdefined( self.zs_offer_serial ) )
        self.zs_offer_serial++;
}

zs_offer_cancel( why )
{
    to = self.zs_offer_to;

    self zs_offer_clear();

    if ( why == "withdrawn" )
    {
        self zs_say( "Trade cancelled" );

        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7 cancelled the trade" );
    }
    else if ( why == "expired" )
    {
        self zs_say( "Your trade offer lapsed" );

        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7's trade offer lapsed" );
    }
    else if ( why == "switched" || why == "lost" )
    {
        self zs_say( "Trade cancelled -- you put the weapon away" );

        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7 put the weapon away -- trade cancelled" );
    }
    else if ( why == "distance" )
    {
        self zs_say( "Trade cancelled -- too far apart" );

        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7's trade offer lapsed -- too far apart" );
    }
    else if ( why == "replaced" )
    {
        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7 withdrew the trade" );
    }

    zs_debug( "offer cancelled: " + why );
}

zs_offer_watcher( serial )
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for (;;)
    {
        wait 0.1;

        if ( !isdefined( self.zs_offer_serial ) || self.zs_offer_serial != serial )
            return;

        to = self.zs_offer_to;

        if ( !isdefined( to ) )
        {
            self zs_offer_clear();
            self zs_say( "Trade cancelled -- they left" );
            return;
        }

        if ( gettime() > self.zs_offer_until )
        {
            self zs_offer_cancel( "expired" );
            return;
        }

        if ( !self hasweapon( self.zs_offer_weapon ) )
        {
            self zs_offer_cancel( "lost" );
            return;
        }

        // Switching to another gun withdraws the offer: what is on offer
        // is what they can see in your hands.
        held = self zs_held_weapon();

        if ( held != self.zs_offer_weapon && zs_is_primary( self, held ) )
        {
            self zs_offer_cancel( "switched" );
            return;
        }

        if ( distance( self.origin, to.origin ) > level.zs.range * 2 )
        {
            self zs_offer_cancel( "distance" );
            return;
        }

        if ( !zs_pair_ok( self, to ) )
        {
            self zs_offer_cancel( "expired" );
            return;
        }
    }
}

/*
    The trade. a offered, b accepted; a's offered weapon goes to b, and
    whatever b is holding goes to a.
*/
zs_trade_do( a, b )
{
    wa = a.zs_offer_weapon;
    wb = b zs_held_weapon();

    if ( !isdefined( wa ) || !a hasweapon( wa ) )
    {
        a zs_offer_cancel( "lost" );
        return;
    }

    why = b zs_untradeable( wb );

    if ( why != "" )
    {
        b zs_deny( why );
        return;
    }

    if ( wa == wb )
    {
        b zs_deny( "You already have that weapon" );
        return;
    }

    /*
        Black Ops never sells a player a gun and its Pack-a-Punched
        version together -- the box and the wall both check -- so a trade
        that would leave somebody holding both is refused the same way.
    */
    if ( zs_carries_same_family( b, wa, wb ) )
    {
        b zs_deny( "You already carry that weapon" );
        return;
    }

    if ( zs_carries_same_family( a, wb, wa ) )
    {
        b zs_deny( "^3" + a.name + "^7 already carries that weapon" );
        return;
    }

    // Mid-switch or mid-throw, a beat to let it finish.
    if ( a isswitchingweapons() || b isswitchingweapons() || a isthrowinggrenade() || b isthrowinggrenade() )
    {
        wait 0.1;

        if ( a isswitchingweapons() || b isswitchingweapons() || a isthrowinggrenade() || b isthrowinggrenade() )
            return;
    }

    // Spent from here, whatever happens below.
    a zs_offer_clear();

    ra = zs_weapon_record( a, wa );
    rb = zs_weapon_record( b, wb );

    a zs_take( wa );
    b zs_take( wb );

    b zs_weapon_give( ra );
    a zs_weapon_give( rb );

    a zs_say( "Traded weapons with ^3" + b.name );
    b zs_say( "Traded weapons with ^3" + a.name );
    a zs_sound( level.zs.trade_sound );
    b zs_sound( level.zs.trade_sound );

    zs_debug( a.name + " " + wa + " <-> " + b.name + " " + wb );
}

/*
    Everything about one weapon a player holds, read the way last stand
    reads a pistol before it takes it: the clip, the left-hand clip of a
    dual wield, the reserve, and the underbarrel attachment's own ammo.
    The render options are what _utility.gsc's take_weapons() keeps, and
    they are the camo, lens and reticle the gun was rolled with.
*/
zs_weapon_record( player, weapon )
{
    r = [];
    r["name"] = weapon;
    r["clip"] = player getweaponammoclip( weapon );
    r["stock"] = player getweaponammostock( weapon );
    r["options"] = player getweaponrenderoptions( weapon );

    r["left"] = weapondualwieldweaponname( weapon );

    if ( !isdefined( r["left"] ) || r["left"] == "" )
        r["left"] = "none";

    r["left_clip"] = 0;

    if ( r["left"] != "none" )
        r["left_clip"] = player getweaponammoclip( r["left"] );

    r["alt"] = zs_attachment_of( player, weapon );
    r["alt_clip"] = 0;
    r["alt_stock"] = 0;

    if ( r["alt"] != "none" )
    {
        r["alt_clip"] = player getweaponammoclip( r["alt"] );
        r["alt_stock"] = player getweaponammostock( r["alt"] );
    }

    return r;
}

zs_weapon_give( r )
{
    weapon = r["name"];

    self giveweapon( weapon, 0, r["options"] );
    self setweaponammoclip( weapon, r["clip"] );
    self setweaponammostock( weapon, r["stock"] );

    if ( r["left"] != "none" )
        self setweaponammoclip( r["left"], r["left_clip"] );

    if ( r["alt"] != "none" && self hasweapon( r["alt"] ) )
    {
        self setweaponammoclip( r["alt"], r["alt_clip"] );
        self setweaponammostock( r["alt"], r["alt_stock"] );
    }

    if ( isdefined( level.zs_f_toggle_give ) )
        [[ level.zs_f_toggle_give ]]( weapon, self );

    self switchtoweapon( weapon );

    if ( isdefined( level.zs_f_weapon_vo ) )
        self [[ level.zs_f_weapon_vo ]]( weapon );
}

/*
    Take a weapon the way weapon_give() takes one it is buying over: the
    ballistic knife has a watcher that wants telling, and a weapon with a
    wall toggle has its toggle put back.
*/
zs_take( weapon )
{
    if ( issubstr( weapon, "knife_ballistic_" ) )
        self notify( "zmb_lost_knife" );

    self takeweapon( weapon );

    if ( isdefined( level.zs_f_toggle_take ) )
        [[ level.zs_f_toggle_take ]]( weapon );
}

/*
    An underbarrel attachment is a weapon of its own in Black Ops, named
    for its type and the gun it hangs from -- gl_, mk_ or ft_ in front --
    and it is carried alongside the gun. This finds the one hanging from
    this gun, or "none".
*/
zs_attachment_of( player, weapon )
{
    list = player getweaponslist();

    for ( i = 0; i < list.size; i++ )
    {
        w = list[i];

        if ( w == weapon || !is_weapon_attachment( w ) )
            continue;

        parts = strtok( w, "_" );

        if ( parts.size >= 2 && issubstr( weapon, parts[1] ) && issubstr( weapon, parts[0] ) )
            return w;
    }

    return "none";
}

/*
    What you are holding, as the primary it belongs to. Holding the
    grenade launcher under a gun is holding the gun, and the Zap Guns
    read as one weapon while the inventory carries the pair under a dw
    name -- the Pack-a-Punch maps it the same way.
*/
zs_held_weapon()
{
    weapon = self getcurrentweapon();

    if ( !isdefined( weapon ) || weapon == "none" || weapon == "" )
        return "none";

    if ( is_weapon_attachment( weapon ) )
    {
        parts = strtok( weapon, "_" );
        primaries = self getweaponslistprimaries();

        for ( i = 0; i < primaries.size; i++ )
        {
            if ( parts.size >= 2 && issubstr( primaries[i], parts[1] ) && issubstr( primaries[i], parts[0] ) )
                return primaries[i];
        }

        return weapon;
    }

    if ( !zs_is_primary( self, weapon ) )
    {
        dw = zs_dual_name( weapon );

        if ( dw != "" && zs_is_primary( self, dw ) )
            return dw;
    }

    return weapon;
}

/*
    microwavegun_zm -> microwavegundw_zm: the name with dw after its
    first word.
*/
zs_dual_name( weapon )
{
    parts = strtok( weapon, "_" );

    if ( parts.size < 2 )
        return "";

    return parts[0] + "dw" + getsubstr( weapon, parts[0].size );
}

zs_is_primary( player, weapon )
{
    if ( !isdefined( weapon ) || weapon == "none" )
        return 0;

    primaries = player getweaponslistprimaries();

    for ( i = 0; i < primaries.size; i++ )
    {
        if ( primaries[i] == weapon )
            return 1;
    }

    return 0;
}

/*
    Why a weapon cannot change hands, or "" when it can. Primaries only:
    grenades, mines, the knife and equipment all have their own slots and
    their own rules, and the box will not take your money for one either.
*/
zs_untradeable( weapon )
{
    if ( !isdefined( weapon ) || weapon == "none" || weapon == "" )
        return "Hold the weapon you want to trade";

    // Revives, drinks and flourishes hold a weapon of their own for a
    // moment.
    if ( weapon == "syrette_sp" || weapon == "zombie_knuckle_crack" || weapon == "zombie_bowie_flourish" || issubstr( weapon, "zombie_perk_bottle" ) )
        return "Hold the weapon you want to trade";

    // The Death Machine belongs to the powerup, not the player.
    if ( zs_has_powerup_weapon( self ) )
        return "That isn't a weapon you can trade";

    if ( zs_is_offhand( weapon ) )
        return "That isn't a weapon you can trade";

    if ( !zs_is_primary( self, weapon ) )
        return "Hold the weapon you want to trade";

    if ( !level.zs.trade_upgraded && zs_is_upgraded( weapon ) )
        return "Pack-a-Punched weapons can't be traded here";

    return "";
}

/*
    Whether the receiver already carries the incoming weapon, or its
    other half -- the plain gun or the Pack-a-Punched one. The weapon
    they are giving away does not count, since it leaves in the same
    trade. has_weapon_or_upgrade() wants the base name, and an upgraded
    name is found under the base whose upgrade_name it is.
*/
zs_carries_same_family( receiver, incoming, outgoing )
{
    base = zs_base_name( incoming );

    if ( base == zs_base_name( outgoing ) )
        return 0;

    if ( isdefined( level.zs_f_has_family ) )
        return receiver [[ level.zs_f_has_family ]]( base );

    return receiver hasweapon( incoming );
}

zs_base_name( weapon )
{
    if ( !isdefined( level.zombie_weapons ) || isdefined( level.zombie_weapons[weapon] ) )
        return weapon;

    keys = getarraykeys( level.zombie_weapons );

    for ( i = 0; i < keys.size; i++ )
    {
        upgrade = level.zombie_weapons[keys[i]].upgrade_name;

        if ( isdefined( upgrade ) && upgrade == weapon )
            return keys[i];
    }

    return weapon;
}


/* ==================================================================
    POINTS

    Through _zombiemode_score.gsc's own helpers, which draw the -N and +N
    popups every purchase does and nothing else. A gift is not points
    earned, so the receiver's score_total is left alone.
   ================================================================== */

/* ==================================================================
    THANKS

    Somebody paid for your perk, gave up the box hit they paid for, or
    handed you points. ZShare already knows -- it says so at the time --
    so it remembers who, and for a while the crouched prompt on them
    offers a small thank instead of the full gift.

    The points come out of the thanker, so nothing is minted and there
    is nothing to farm: a thank is a gift with a reason attached, and
    what it buys is that the prompt tells you a favour is owed and takes
    one press to answer.

    One thank per favour, so the prompt stays meaningful. To give more,
    tip.
   ================================================================== */

/*
    Remember that `from` did `self` a good turn. The most recent one is
    the one that is owed; an older unthanked favour is simply replaced,
    because thanking is about the moment rather than a ledger.
*/
zs_favour_note( from )
{
    if ( !isdefined( from ) || !isdefined( self ) || from == self )
        return;

    if ( !isplayer( from ) || !isplayer( self ) )
        return;

    self.zs_favour_from = from;
    self.zs_favour_at = gettime();
}

zs_owes_thanks( to )
{
    if ( !level.zs.thank || !isdefined( to ) )
        return 0;

    if ( !isdefined( self.zs_favour_from ) || self.zs_favour_from != to )
        return 0;

    if ( level.zs.thank_amount <= 0 || self.score < level.zs.thank_amount )
        return 0;

    return gettime() - self.zs_favour_at < int( level.zs.thank_time * 1000 );
}

// Whoever is owed a thank right now, for the chat word.
zs_favour_who()
{
    if ( !isdefined( self.zs_favour_from ) )
        return undefined;

    if ( !self zs_owes_thanks( self.zs_favour_from ) )
        return undefined;

    return self.zs_favour_from;
}

zs_thank( to )
{
    if ( !zs_pair_ok( self, to ) )
        return;

    amount = level.zs.thank_amount;

    if ( self.score < amount )
    {
        self zs_deny( "You need " + amount + " points to thank them" );
        return;
    }

    self.zs_favour_from = undefined;

    zs_score_minus( self, amount );
    zs_score_add( to, amount );

    self zs_say( "Thanked ^3" + to.name + "^7 -- " + amount + " points" );
    to zs_say( "^3" + self.name + "^7 thanked you -- " + amount + " points" );

    self zs_sound( level.zs.points_sound );
    to zs_sound( level.zs.points_sound );

    zs_debug( "thanks: " + self.name + " -> " + to.name );
}

/*
    Any amount, to anybody, with no favour needed. The name is optional
    and the amount is always the last word, so a name with spaces in it
    still parses.
*/
zs_tip( rest )
{
    if ( !level.zs.thank )
        return;

    parts = strtok( rest, " " );

    if ( parts.size == 0 )
    {
        self zs_say( "Say ^3!tip 500^7, or ^3!tip <name> 500^7" );
        return;
    }

    amount = int( parts[parts.size - 1] );

    if ( amount <= 0 )
    {
        self zs_say( "Say ^3!tip 500^7, or ^3!tip <name> 500^7" );
        return;
    }

    if ( parts.size > 1 )
    {
        name = "";

        for ( i = 0; i < parts.size - 1; i++ )
            if ( name == "" )
                name = parts[i];
            else
                name = name + " " + parts[i];

        to = zs_player_named( name, self );

        if ( !isdefined( to ) )
            return;
    }
    else
    {
        to = self zs_favour_who();

        if ( !isdefined( to ) )
        {
            self zs_say( "Nobody owed a thank -- say ^3!tip <name> " + amount + "^7 instead" );
            return;
        }
    }

    if ( !zs_pair_ok( self, to ) )
        return;

    if ( self.score < amount )
    {
        self zs_deny( "You only have " + self.score + " points" );
        return;
    }

    zs_score_minus( self, amount );
    zs_score_add( to, amount );

    self zs_say( "Tipped ^3" + to.name + "^7 " + amount + " points" );
    to zs_say( "^3" + self.name + "^7 tipped you " + amount + " points" );

    self zs_sound( level.zs.points_sound );
    to zs_sound( level.zs.points_sound );

    zs_debug( "tip: " + self.name + " -> " + to.name + " " + amount );
}

/*
    The player a typed name means. Case and colour codes are ignored and
    a prefix is enough, but a name that matches nobody -- or more than
    one -- is refused rather than guessed at: somebody typing a name
    means that player, and sending their points to another is worse than
    doing nothing.
*/
zs_player_named( name, asker )
{
    want = tolower( name );
    found = undefined;
    several = 0;

    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];

        if ( !isdefined( p ) || p == asker )
            continue;

        theirs = tolower( zs_plain_name( p.name ) );

        if ( theirs == want )
            return p;

        if ( getsubstr( theirs, 0, want.size ) != want )
            continue;

        if ( isdefined( found ) )
            several = 1;
        else
            found = p;
    }

    if ( several )
    {
        asker zs_say( "More than one player starts with ^3" + name + "^7" );
        return undefined;
    }

    if ( !isdefined( found ) )
        asker zs_say( "No player here called ^3" + name );

    return found;
}

// A name with the colour codes taken out, so typing it plainly matches.
zs_plain_name( name )
{
    out = "";

    for ( i = 0; i < name.size; i++ )
    {
        if ( name[i] == "^" && i + 1 < name.size )
        {
            i++;
            continue;
        }

        out = out + name[i];
    }

    return out;
}

zs_points_give( to )
{
    amount = level.zs.points_amount;

    if ( amount <= 0 || is_true( level.intermission ) )
        return;

    if ( isdefined( self.zs_points_last ) && gettime() - self.zs_points_last < level.zs.points_cooldown * 1000 )
        return;

    if ( self.score < amount )
    {
        self zs_deny( "You need " + amount + " points to give" );
        return;
    }

    self.zs_points_last = gettime();

    zs_score_minus( self, amount );
    zs_score_add( to, amount );

    to zs_favour_note( self );

    self zs_say( "Gave ^3" + to.name + "^7 " + amount + " points" );
    to zs_say( "^3" + self.name + "^7 gave you " + amount + " points" );
    self zs_sound( level.zs.points_sound );
    to zs_sound( level.zs.points_sound );

    zs_debug( self.name + " gave " + amount + " to " + to.name );
}


/* ==================================================================
    HOOKS

    What ZShare replaces in the stock scripts, in one place, and only
    from main(). Plutonium already replaces five T5 functions of its own
    -- vending_trigger_think, turn_revive_on, give_perk and
    team_score_init online, decide_hide_show_hint on a dedicated server
    -- and nothing here touches any of them: what a second replace on
    the same function would do is not known.
   ================================================================== */

zs_replace_stock()
{
    if ( is_true( level.zs_replaced ) )
        return;

    level.zs_replaced = 1;

    zs_functions();

    /*
        Each machine is only taken over when every stock piece its copy
        calls was found; otherwise it stays entirely stock. Looked up in
        this order because each list borrows from the one before.
    */
    box = zs_box_functions();
    pap = zs_pap_functions();
    perks = zs_perk_functions();

    if ( box )
        level.zs_chest_hooked = zs_replace( "maps/_zombiemode_weapons", "treasure_chest_think", ::zs_chest_think );

    if ( pap )
        level.zs_pap_hooked = zs_replace( "maps/_zombiemode_perks", "vending_weapon_upgrade", ::zs_pap_upgrade );

    if ( perks )
        level.zs_perk_hooked = zs_replace( "maps/_zombiemode_perks", "check_player_has_perk", ::zs_perk_visibility );
}

zs_replace( path, name, replacement )
{
    fn = getfunction( path, name );

    if ( !isdefined( fn ) )
    {
        println( "ZShare: " + path + "::" + name + " not found -- left as it is" );
        return 0;
    }

    replacefunc( fn, replacement, -1 );
    return 1;
}

zs_flag( name )
{
    if ( !isdefined( level.flag ) || !isdefined( level.flag[name] ) )
        return 0;

    return level.flag[name];
}

zs_fire_sale_on()
{
    if ( !isdefined( level.zombie_vars ) )
        return 0;

    return is_true( level.zombie_vars["zombie_powerup_fire_sale_on"] );
}


/* ==================================================================
    THE BOX

    Black Ops' box is one map trigger per location, with one hint for
    every player, and the grab is written inline in its think loop -- so
    that loop is replaced with a copy of itself. The copy differs in
    three places: ZShare's watcher decides who sees the chest, a spin
    opened by a payment is marked used as it opens, and a teddy bear on
    a paid spin refunds whoever paid.

    Sharing is box_rerespun, the state Moon's hacker leaves a box in,
    which the grab loop already reads as "anyone can take it". Paying is
    auto_open and no_charge, the state the hacker's summon leaves it in.

    The words a crouched player needs -- share, pay, take back -- are a
    second trigger on each chest, and the chest's own trigger is hidden
    from exactly the players who see it. Both are decided for each
    player in the same pass.
   ================================================================== */

/*
    Every stock piece the copy of the box's loop calls. Returns whether
    all of them were found.
*/
zs_box_functions()
{
    level.zs_f_set_hint     = getfunction( "maps/_zombiemode_utility", "set_hint_string" );
    level.zs_f_mine         = getfunction( "maps/_zombiemode_utility", "is_placeable_mine" );
    level.zs_f_equipment    = getfunction( "maps/_zombiemode_utility", "is_equipment" );
    level.zs_f_disable      = getfunction( "maps/_zombiemode_utility", "disable_trigger" );
    level.zs_f_enable       = getfunction( "maps/_zombiemode_utility", "enable_trigger" );
    level.zs_f_dialog       = getfunction( "maps/_zombiemode_audio", "create_and_play_dialog" );
    level.zs_f_lid_open     = getfunction( "maps/_zombiemode_weapons", "treasure_chest_lid_open" );
    level.zs_f_lid_close    = getfunction( "maps/_zombiemode_weapons", "treasure_chest_lid_close" );
    level.zs_f_weapon_spawn = getfunction( "maps/_zombiemode_weapons", "treasure_chest_weapon_spawn" );
    level.zs_f_glowfx       = getfunction( "maps/_zombiemode_weapons", "treasure_chest_glowfx" );
    level.zs_f_chest_move   = getfunction( "maps/_zombiemode_weapons", "treasure_chest_move" );
    level.zs_f_timeout      = getfunction( "maps/_zombiemode_weapons", "treasure_chest_timeout" );
    level.zs_f_give_weapon  = getfunction( "maps/_zombiemode_weapons", "treasure_chest_give_weapon" );
    level.zs_f_can_buy      = getfunction( "maps/_zombiemode_weapons", "can_buy_weapon" );

    need = [];
    need[need.size] = level.zs_f_set_hint;
    need[need.size] = level.zs_f_mine;
    need[need.size] = level.zs_f_equipment;
    need[need.size] = level.zs_f_disable;
    need[need.size] = level.zs_f_enable;
    need[need.size] = level.zs_f_dialog;
    need[need.size] = level.zs_f_lid_open;
    need[need.size] = level.zs_f_lid_close;
    need[need.size] = level.zs_f_weapon_spawn;
    need[need.size] = level.zs_f_glowfx;
    need[need.size] = level.zs_f_chest_move;
    need[need.size] = level.zs_f_timeout;
    need[need.size] = level.zs_f_give_weapon;
    need[need.size] = level.zs_f_can_buy;
    need[need.size] = level.zs_f_valid;
    need[need.size] = level.zs_f_revive_trigger;
    need[need.size] = level.zs_f_drinking;
    need[need.size] = level.zs_f_toggle_take;
    need[need.size] = level.zs_f_score_add;
    need[need.size] = level.zs_f_score_minus;

    /*
        An undefined entry is not stored, so a lookup that found nothing
        leaves the array one short.
    */
    if ( need.size != 20 )
    {
        println( "ZShare: a box function was not found -- the box stays stock" );
        return 0;
    }

    return 1;
}

/*
    treasure_chest_think() from _zombiemode_weapons.gsc. Every call into
    the zombiemode tree goes through its pointer, the telemetry lines are
    left out, and the changes are marked ZShare.
*/
zs_chest_think()
{
    self endon( "kill_chest_think" );

    // ZShare: the watcher runs for the life of the chest.
    if ( !is_true( self.zs_watching ) )
    {
        self.zs_watching = 1;
        self thread zs_chest_watch();
    }

    if ( zs_fire_sale_on() && self [[ level._zombiemode_check_firesale_loc_valid_func ]]() )
        self [[ level.zs_f_set_hint ]]( self, "powerup_fire_sale_cost" );
    else
        self [[ level.zs_f_set_hint ]]( self, "default_treasure_chest_" + self.zombie_cost );

    self setcursorhint( "HINT_NOICON" );

    // ZShare: the stock words are up.
    self.zs_hint = "";

    user = undefined;
    user_cost = undefined;
    self.box_rerespun = undefined;
    self.weapon_out = undefined;

    for (;;)
    {
        if ( !isdefined( self.forced_user ) )
            self waittill( "trigger", user );
        else
            user = self.forced_user;

        if ( user [[ level.zs_f_revive_trigger ]]() )
        {
            wait 0.1;
            continue;
        }

        if ( user [[ level.zs_f_drinking ]]() )
        {
            wait 0.1;
            continue;
        }

        if ( is_true( self.disabled ) )
        {
            wait 0.1;
            continue;
        }

        if ( user getcurrentweapon() == "none" )
        {
            wait 0.1;
            continue;
        }

        if ( isdefined( self.auto_open ) && [[ level.zs_f_valid ]]( user ) )
        {
            if ( !isdefined( self.no_charge ) )
            {
                user [[ level.zs_f_score_minus ]]( self.zombie_cost );
                user_cost = self.zombie_cost;
            }
            else
            {
                user_cost = 0;
            }

            self.chest_user = user;
            break;
        }
        else if ( [[ level.zs_f_valid ]]( user ) && user.score >= self.zombie_cost )
        {
            user [[ level.zs_f_score_minus ]]( self.zombie_cost );
            user_cost = self.zombie_cost;
            self.chest_user = user;
            break;
        }
        else if ( user.score < self.zombie_cost )
        {
            user [[ level.zs_f_dialog ]]( "general", "no_money", undefined, 2 );
            continue;
        }

        wait 0.05;
    }

    flag_set( "chest_has_been_used" );

    // ZShare: a spin opened with the free fields on is the payment used.
    paid = undefined;

    if ( is_true( self.zs_free ) )
        paid = self zs_chest_paid_used( user );

    self._box_open = true;
    self._box_opened_by_fire_sale = false;

    if ( zs_fire_sale_on() && !isdefined( self.auto_open ) && self [[ level._zombiemode_check_firesale_loc_valid_func ]]() )
        self._box_opened_by_fire_sale = true;

    self.chest_lid thread [[ level.zs_f_lid_open ]]();

    self.timedout = false;

    self.weapon_out = true;
    self.chest_origin thread [[ level.zs_f_weapon_spawn ]]( self, user );
    self.chest_origin thread [[ level.zs_f_glowfx ]]();

    self [[ level.zs_f_disable ]]();

    self.chest_origin waittill( "randomization_done" );

    if ( flag( "moving_chest_now" ) && !self._box_opened_by_fire_sale && isdefined( user_cost ) )
        user [[ level.zs_f_score_add ]]( user_cost, false );

    // ZShare: that refund is 0 on a paid spin, so whoever paid gets theirs.
    if ( flag( "moving_chest_now" ) && isdefined( paid ) )
        zs_chest_teddy_refund( paid );

    if ( flag( "moving_chest_now" ) && !level.zombie_vars["zombie_powerup_fire_sale_on"] )
    {
        self thread [[ level.zs_f_chest_move ]]( self.chest_user );
    }
    else
    {
        self.grab_weapon_hint = true;
        self.chest_user = user;
        self sethintstring( &"ZOMBIE_TRADE_WEAPONS" );
        self setcursorhint( "HINT_NOICON" );

        // ZShare: no decide_hide_show_hint() -- the watcher owns visibility.

        self [[ level.zs_f_enable ]]();
        self thread [[ level.zs_f_timeout ]]();

        for (;;)
        {
            self waittill( "trigger", grabber );
            self.weapon_out = undefined;

            if ( isdefined( grabber.is_drinking ) && grabber [[ level.zs_f_drinking ]]() )
            {
                wait 0.1;
                continue;
            }

            if ( grabber == user && user getcurrentweapon() == "none" )
            {
                wait 0.1;
                continue;
            }

            if ( grabber != level && is_true( self.box_rerespun ) )
                user = grabber;

            if ( grabber == user || grabber == level )
            {
                self.box_rerespun = undefined;
                current_weapon = "none";

                if ( [[ level.zs_f_valid ]]( user ) )
                    current_weapon = user getcurrentweapon();

                if ( grabber == user && [[ level.zs_f_valid ]]( user ) && !user [[ level.zs_f_drinking ]]() && ![[ level.zs_f_mine ]]( current_weapon ) && ![[ level.zs_f_equipment ]]( current_weapon ) && "syrette_sp" != current_weapon )
                {
                    self notify( "user_grabbed_weapon" );
                    user thread [[ level.zs_f_give_weapon ]]( self.chest_origin.weapon_string );
                    break;
                }
                else if ( grabber == level )
                {
                    [[ level.zs_f_toggle_take ]]( self.chest_origin.weapon_string );
                    self.timedout = true;
                    break;
                }
            }

            wait 0.05;
        }

        self.grab_weapon_hint = false;
        self.chest_origin notify( "weapon_grabbed" );

        if ( !is_true( self._box_opened_by_fire_sale ) )
            level.chest_accessed += 1;

        if ( level.chest_moves > 0 && isdefined( level.pulls_since_last_ray_gun ) )
            level.pulls_since_last_ray_gun += 1;

        if ( isdefined( level.pulls_since_last_tesla_gun ) )
            level.pulls_since_last_tesla_gun += 1;

        self [[ level.zs_f_disable ]]();

        self.chest_lid thread [[ level.zs_f_lid_close ]]( self.timedout );

        wait 3;

        if ( ( zs_fire_sale_on() && self [[ level._zombiemode_check_firesale_loc_valid_func ]]() ) || self == level.chests[level.chest_index] )
        {
            self [[ level.zs_f_enable ]]();
            self setvisibletoall();
        }
    }

    self._box_open = false;
    self._box_opened_by_fire_sale = false;
    self.chest_user = undefined;

    self notify( "chest_accessed" );

    self thread zs_chest_think();
}

/*
    One per chest, for the life of the game, ten times a second: the
    payment's free fields on the live chest and off everywhere else, who
    sees which of the two triggers, and the words on both.
*/
zs_chest_watch()
{
    level endon( "end_game" );

    self zs_chest_trigger_ensure();

    tick = 0;

    for (;;)
    {
        wait 0.1;

        tick++;

        if ( !is_true( self.grab_weapon_hint ) && is_true( self.zs_shared ) )
        {
            self.zs_shared = 0;
            self.zs_shared_by = undefined;
        }

        if ( is_true( level.zs_box_paid ) && zs_chest_can_be_free( self ) )
            self zs_chest_free_apply();
        else
            self zs_chest_free_remove();

        self zs_chest_visibility();
        self zs_chest_hints( tick % 10 == 0 );
    }
}

/*
    ZShare's trigger on the chest, where the model is, with the reach of
    a player standing at the box. It never moves: a chest that is hidden
    or away never offers it to anybody.
*/
zs_chest_trigger_ensure()
{
    if ( isdefined( self.zs_trig ) )
        return;

    origin = self.origin;

    if ( isdefined( self.chest_origin ) )
        origin = self.chest_origin.origin;

    t = spawn( "trigger_radius_use", origin, 0, 80, 72 );
    t setcursorhint( "HINT_NOICON" );
    t usetriggerrequirelookat();
    t sethintstring( "" );

    t.zs_chest = self;
    t.zs_hint = "";

    players = get_players();

    for ( i = 0; i < players.size; i++ )
        t setinvisibletoplayer( players[i], true );

    self.zs_trig = t;

    t thread zs_chest_trigger_think();
}

zs_chest_trigger_think()
{
    level endon( "end_game" );

    for (;;)
    {
        self waittill( "trigger", player );

        chest = self.zs_chest;

        if ( !isdefined( chest ) || !isdefined( player ) || !isplayer( player ) )
            continue;

        zs_load_config();

        mode = chest zs_chest_mode( player );

        if ( mode == "share" )
            chest zs_chest_share( player );
        else if ( mode == "pay" )
            chest zs_chest_pay( player );
        else if ( mode == "take_back" )
            zs_chest_take_back( player );

        wait 0.3;
    }
}

/*
    What a press on ZShare's trigger at this chest means for this player
    right now, or "" when the chest's own trigger is the one they should
    be reading:

        share      the weapon up is yours, and you are crouched
        take_back  you paid for the next spin, and you are crouched
        pay        the box is idle and live, and you are crouched
*/
zs_chest_mode( p )
{
    if ( !isdefined( p ) || !zs_crouched( p ) )
        return "";

    if ( is_true( self.grab_weapon_hint ) )
    {
        if ( !zs_player_ok( p ) || !zs_chest_shareable( self, p ) )
            return "";

        return "share";
    }

    if ( is_true( self.disabled ) || is_true( self._box_open ) || is_true( self.hidden ) )
        return "";

    if ( is_true( level.zs_box_paid ) )
    {
        if ( isdefined( level.zs_box_paid_by ) && level.zs_box_paid_by == p && zs_payer_ok( p ) )
            return "take_back";

        return "";
    }

    if ( self zs_chest_pay_allowed( p ) )
        return "pay";

    return "";
}

/*
    Whether player's box weapon is up in this chest and can still be
    shared. The crouched press and the chat word both ask.
*/
zs_chest_shareable( chest, player )
{
    if ( !isdefined( chest ) || !isdefined( player ) )
        return 0;

    if ( !level.zs.box_share || !is_true( chest.grab_weapon_hint ) )
        return 0;

    if ( is_true( chest.zs_shared ) || isdefined( chest.box_rerespun ) )
        return 0;

    if ( !isdefined( chest.chest_user ) || chest.chest_user != player )
        return 0;

    return 1;
}

zs_chest_pay_allowed( p )
{
    if ( !level.zs.box_pay || !zs_pay_team_check() )
        return 0;

    if ( zs_fire_sale_on() || zs_flag( "moving_chest_now" ) )
        return 0;

    if ( !zs_chest_is_live( self ) )
        return 0;

    // The hacker's summon borrows the same free-spin fields.
    if ( isdefined( self.forced_user ) || ( isdefined( self.auto_open ) && !is_true( self.zs_free ) ) )
        return 0;

    if ( !isdefined( self.zombie_cost ) )
        return 0;

    if ( !p [[ level.zs_f_can_buy ]]() )
        return 0;

    return zs_payer_ok( p );
}

zs_chest_is_live( chest )
{
    if ( !isdefined( level.chests ) || !isdefined( level.chest_index ) )
        return 0;

    if ( !isdefined( level.chests[level.chest_index] ) )
        return 0;

    return level.chests[level.chest_index] == chest;
}

/*
    Who sees the chest's own trigger follows decide_hide_show_hint() as
    stock wrote it: while somebody's weapon is up, only that player
    unless the box has been re-spun for anyone; otherwise everybody who
    could buy from it. A player reading ZShare's trigger is left out of
    both. Only players near the chest are touched -- the flags keep, and
    are brought up to date as a player walks up.
*/
zs_chest_visibility()
{
    t = self.zs_trig;

    // A hidden chest's trigger is 10000 units underground.
    if ( is_true( self.disabled ) && !is_true( self.grab_weapon_hint ) )
    {
        if ( isdefined( t ) && !is_true( t.zs_all_hidden ) )
        {
            players = get_players();

            for ( i = 0; i < players.size; i++ )
                t setinvisibletoplayer( players[i], true );

            t.zs_all_hidden = 1;
        }

        return;
    }

    if ( isdefined( t ) )
        t.zs_all_hidden = 0;

    near = self.origin;

    if ( isdefined( self.chest_origin ) )
        near = self.chest_origin.origin;

    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];

        if ( !isdefined( p ) || distancesquared( p.origin, near ) > 65536 )
            continue;

        mode = self zs_chest_mode( p );

        if ( mode != "" )
        {
            self setinvisibletoplayer( p, true );

            if ( isdefined( t ) )
                t setinvisibletoplayer( p, false );

            continue;
        }

        if ( isdefined( t ) )
            t setinvisibletoplayer( p, true );

        self setinvisibletoplayer( p, !self zs_chest_stock_visible( p ) );
    }
}

zs_chest_stock_visible( p )
{
    if ( isdefined( self.chest_user ) && !isdefined( self.box_rerespun ) )
    {
        if ( p != self.chest_user )
            return 0;

        weapon = p getcurrentweapon();

        return !( [[ level.zs_f_mine ]]( weapon ) || zs_hacker_out( p ) );
    }

    return p [[ level.zs_f_can_buy ]]();
}

/*
    The words. ZShare's trigger carries whichever of its three can be
    true of this chest right now -- only one player can ever be reading
    it at a time. The chest's own trigger reads the stock line, except
    for a spin somebody paid for and a weapon somebody shared. The fire
    sale and the box move write the chest's hint themselves, so a ZShare
    line goes back up once a second while it applies, and the stock line
    comes back when it stops applying.
*/
zs_chest_hints( force )
{
    t = self.zs_trig;

    if ( isdefined( t ) )
    {
        want = "";

        if ( is_true( self.grab_weapon_hint ) )
            want = "Hold ^3[{+activate}]^7 to share this weapon";
        else if ( is_true( level.zs_box_paid ) )
            want = "Hold ^3[{+activate}]^7 to take back your payment";
        else if ( isdefined( self.zombie_cost ) )
            want = "Hold ^3[{+activate}]^7 to buy a spin for a teammate [Cost: " + self.zombie_cost + "]";

        if ( want != t.zs_hint )
        {
            t sethintstring( want );
            t.zs_hint = want;
        }
    }

    if ( !isdefined( self.zs_hint ) )
        self.zs_hint = "";

    want = "";

    if ( is_true( self.grab_weapon_hint ) && is_true( self.zs_shared ) )
        want = "shared";
    else if ( !is_true( self.grab_weapon_hint ) && !is_true( self._box_open ) && is_true( self.zs_free ) )
        want = "free";

    if ( want != "" )
    {
        if ( want != self.zs_hint || force )
        {
            if ( want == "shared" )
                self sethintstring( "Hold ^3[{+activate}]^7 to take the shared weapon" );
            else
                self sethintstring( "Hold ^3[{+activate}]^7 for a Random Weapon [Cost: 0]" );
        }
    }
    else if ( self.zs_hint != "" )
    {
        self zs_chest_stock_hint();
    }

    self.zs_hint = want;
}

zs_chest_stock_hint()
{
    if ( is_true( self.grab_weapon_hint ) )
    {
        self sethintstring( &"ZOMBIE_TRADE_WEAPONS" );
        return;
    }

    if ( zs_fire_sale_on() && self [[ level._zombiemode_check_firesale_loc_valid_func ]]() )
    {
        self [[ level.zs_f_set_hint ]]( self, "powerup_fire_sale_cost" );
        return;
    }

    self [[ level.zs_f_set_hint ]]( self, "default_treasure_chest_" + self.zombie_cost );
}

zs_chest_share( player )
{
    self.box_rerespun = 1;
    self.zs_shared = 1;
    self.zs_shared_by = player;

    zs_say_all( "^3" + player.name + "^7 shared their box weapon -- anyone can take it" );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "box shared by " + player.name );
}

zs_chest_pay( player )
{
    cost = self.zombie_cost;

    if ( player.score < cost )
    {
        player [[ level.zs_f_dialog ]]( "general", "no_money", undefined, 2 );
        player zs_deny( "You need " + cost + " points" );
        return;
    }

    before = player.score;
    zs_score_minus( player, cost );

    level.zs_box_paid = 1;
    level.zs_box_paid_by = player;
    level.zs_box_paid_name = player.name;
    level.zs_box_paid_amount = before - player.score;

    self zs_chest_free_apply();

    player zs_say( "Paid for the next box spin -- the next teammate to use the box spins free" );
    zs_say_others( player, "^3" + player.name + "^7 paid for the next box spin -- use the box to spin free" );
    player zs_sound( level.zs.points_sound );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "box paid by " + player.name + ": " + level.zs_box_paid_amount );
}

zs_chest_take_back( player )
{
    amount = level.zs_box_paid_amount;

    zs_chest_paid_reset();

    if ( isdefined( amount ) && amount > 0 )
        zs_score_add( player, amount );

    player zs_say( "Took back your payment for the box" );
    zs_say_others( player, "^3" + player.name + "^7 took back their payment for the box" );
    player zs_sound( level.zs.points_sound );

    zs_debug( "box payment taken back" );
}

zs_chest_paid_reset()
{
    level.zs_box_paid = 0;
    level.zs_box_paid_by = undefined;
    level.zs_box_paid_name = undefined;
    level.zs_box_paid_amount = undefined;

    if ( !isdefined( level.chests ) )
        return;

    for ( i = 0; i < level.chests.size; i++ )
    {
        if ( isdefined( level.chests[i] ) )
            level.chests[i] zs_chest_free_remove();
    }
}

/*
    A paid spin has just opened. The payment is spent; what it was comes
    back for the teddy bear check once the weapon settles.
*/
zs_chest_paid_used( user )
{
    paid = [];
    paid["by"] = level.zs_box_paid_by;
    paid["name"] = level.zs_box_paid_name;
    paid["amount"] = level.zs_box_paid_amount;

    level.zs_box_paid = 0;
    level.zs_box_paid_by = undefined;
    level.zs_box_paid_name = undefined;
    level.zs_box_paid_amount = undefined;

    self zs_chest_free_remove();

    if ( isdefined( user ) && isdefined( paid["by"] ) && user != paid["by"] )
    {
        user zs_say( "^3" + paid["name"] + "^7 paid for this spin" );
        user zs_favour_note( paid["by"] );
        paid["by"] zs_say( "^3" + user.name + "^7 used the spin you paid for" );
    }

    zs_debug( "paid box spin used" );
    return paid;
}

zs_chest_teddy_refund( paid )
{
    if ( !isdefined( paid["by"] ) || !isdefined( paid["amount"] ) || paid["amount"] <= 0 )
        return;

    zs_score_add( paid["by"], paid["amount"] );
    paid["by"] zs_say( "The box moved -- your " + paid["amount"] + " points came back" );
    paid["by"] zs_sound( level.zs.points_sound );
}

/*
    Only ever sets fields nobody else is using, and only ever clears the
    ones it set: Moon's hacker leaves its own there while it runs.
*/
zs_chest_free_apply()
{
    if ( is_true( self.zs_free ) )
        return;

    if ( isdefined( self.auto_open ) || isdefined( self.no_charge ) || isdefined( self.forced_user ) )
        return;

    self.auto_open = 1;
    self.no_charge = 1;
    self.zs_free = 1;
}

zs_chest_free_remove()
{
    if ( !is_true( self.zs_free ) )
        return;

    self.auto_open = undefined;
    self.no_charge = undefined;
    self.zs_free = 0;
}

/*
    A payment sits on the live chest while it is idle, and comes off for
    a fire sale -- a spin costs 10 then, and a free one would also skip
    the fire sale's own bookkeeping -- and while the box moves.
*/
zs_chest_can_be_free( chest )
{
    if ( zs_fire_sale_on() || zs_flag( "moving_chest_now" ) )
        return 0;

    if ( is_true( chest.hidden ) || is_true( chest._box_open ) )
        return 0;

    return zs_chest_is_live( chest );
}


/* ==================================================================
    MACHINE PROMPTS

    A perk machine and the Pack-a-Punch show one hint to every player, so
    the words a payer needs are a second trigger on the same spot --
    radius 40, height 70, the reach of the stock trigger -- and a perk
    machine has a third, for a teammate drinking a paid drink or a player
    ZShare's perk limit decides for. Each follows the stock trigger
    wherever it goes: Shi No Numa moves its machines, Five and Call of the
    Dead move the Pack-a-Punch, and a disabled trigger is parked ten
    thousand units down.
   ================================================================== */

zs_machine_trigger( kind )
{
    t = spawn( "trigger_radius_use", self.origin, 0, 40, 70 );
    t setcursorhint( "HINT_NOICON" );
    t usetriggerrequirelookat();
    t sethintstring( "" );

    t.zs_machine = self;
    t.zs_kind = kind;
    t.zs_hint = "";

    players = get_players();

    for ( i = 0; i < players.size; i++ )
        t setinvisibletoplayer( players[i], true );

    t thread zs_machine_trigger_think();
    return t;
}

zs_machine_trigger_sync( t )
{
    if ( isdefined( t ) && t.origin != self.origin )
        t.origin = self.origin;
}

zs_trigger_show( t, player, on )
{
    if ( isdefined( t ) )
        t setinvisibletoplayer( player, !on );
}

zs_machine_trigger_think()
{
    level endon( "end_game" );

    for (;;)
    {
        self waittill( "trigger", player );

        machine = self.zs_machine;

        if ( !isdefined( machine ) || !isdefined( player ) || !isplayer( player ) )
            continue;

        zs_load_config();

        if ( self.zs_kind == "pap" )
            machine zs_pap_pay_press( player );
        else if ( self.zs_kind == "buy" )
            machine zs_perk_buy_press( player );
        else
            machine zs_perk_pay_press( player );

        wait 0.3;
    }
}

zs_set_hint( t, want )
{
    if ( !isdefined( t ) || want == t.zs_hint )
        return;

    t sethintstring( want );
    t.zs_hint = want;
}

zs_bonfire_on()
{
    if ( !isdefined( level.zombie_vars ) )
        return 0;

    return is_true( level.zombie_vars["zombie_powerup_bonfire_sale_on"] );
}


/* ==================================================================
    THE PACK-A-PUNCH

    vending_weapon_upgrade() runs two visibility loops side by side on
    the machine's trigger -- vending_machine_trigger_think() and
    decide_hide_show_hint() -- and neither would ever let a payer's
    prompt stand, so the loop is replaced with a copy that runs ZShare's
    watcher instead. The take loop it starts is ZShare's too, with the
    share branch in it. The price is read off the trigger on every
    press, so a paid pack is that price held at zero.

    vending_machine_trigger_think() itself is left alone: Moon runs it
    on its power switch as well.
   ================================================================== */

zs_pap_functions()
{
    level.zs_f_laststand     = getfunction( "maps/_laststand", "player_is_in_laststand" );
    level.zs_f_jingle        = getfunction( "maps/_zombiemode_audio", "play_jingle_or_stinger" );
    level.zs_f_knuckle       = getfunction( "maps/_zombiemode_perks", "do_knuckle_crack" );
    level.zs_f_third_person  = getfunction( "maps/_zombiemode_perks", "third_person_weapon_upgrade" );
    level.zs_f_pap_cost      = getfunction( "maps/_zombiemode_perks", "vending_weapon_upgrade_cost" );
    level.zs_f_pap_timeout   = getfunction( "maps/_zombiemode_perks", "wait_for_timeout" );
    level.zs_f_weapon_give   = getfunction( "maps/_zombiemode_weapons", "weapon_give" );
    level.zs_f_pap_options   = getfunction( "maps/_zombiemode_weapons", "get_pack_a_punch_weapon_options" );

    need = [];
    need[need.size] = level.zs_f_laststand;
    need[need.size] = level.zs_f_jingle;
    need[need.size] = level.zs_f_knuckle;
    need[need.size] = level.zs_f_third_person;
    need[need.size] = level.zs_f_pap_cost;
    need[need.size] = level.zs_f_pap_timeout;
    need[need.size] = level.zs_f_weapon_give;
    need[need.size] = level.zs_f_pap_options;
    need[need.size] = level.zs_f_can_buy;
    need[need.size] = level.zs_f_dialog;
    need[need.size] = level.zs_f_disable;
    need[need.size] = level.zs_f_enable;
    need[need.size] = level.zs_f_mine;
    need[need.size] = level.zs_f_equipment;
    need[need.size] = level.zs_f_valid;
    need[need.size] = level.zs_f_drinking;
    need[need.size] = level.zs_f_weapon_vo;
    need[need.size] = level.zs_f_score_minus;

    if ( need.size != 18 )
    {
        println( "ZShare: a Pack-a-Punch function was not found -- the machine stays stock" );
        return 0;
    }

    return 1;
}

/*
    vending_weapon_upgrade() from _zombiemode_perks.gsc. Every call into
    the zombiemode tree goes through its pointer, and the changes are
    marked ZShare.
*/
zs_pap_upgrade()
{
    perk_machine = getent( self.target, "targetname" );
    packa_rollers = spawn( "script_origin", self.origin );
    packa_timer = spawn( "script_origin", self.origin );
    packa_rollers linkto( self );
    packa_timer linkto( self );

    if ( isdefined( perk_machine.target ) )
        perk_machine.wait_flag = getent( perk_machine.target, "targetname" );

    self usetriggerrequirelookat();
    self sethintstring( &"ZOMBIE_NEED_POWER" );
    self setcursorhint( "HINT_NOICON" );

    level waittill( "Pack_A_Punch_on" );

    // ZShare: one watcher, in place of the two stock visibility loops.
    self thread zs_pap_watch();

    perk_machine playloopsound( "zmb_perks_packa_loop" );

    self thread [[ level.zs_f_pap_cost ]]();

    for ( ;; )
    {
        self waittill( "trigger", player );

        current_weapon = player getcurrentweapon();

        if ( "microwavegun_zm" == current_weapon )
            current_weapon = "microwavegundw_zm";

        if ( !player [[ level.zs_f_can_buy ]]() || player [[ level.zs_f_laststand ]]() || is_true( player.intermission ) || player isthrowinggrenade() || zs_is_upgraded( current_weapon ) )
        {
            wait 0.1;
            continue;
        }

        // Not while the machine is being lowered or raised.
        if ( is_true( level.pap_moving ) )
            continue;

        if ( player isswitchingweapons() )
        {
            wait 0.1;
            continue;
        }

        if ( !isdefined( level.zombie_include_weapons[current_weapon] ) )
            continue;

        if ( player.score < self.cost )
        {
            self playsound( "deny" );
            player [[ level.zs_f_dialog ]]( "general", "perk_deny", undefined, 0 );
            continue;
        }

        /*
            ZShare: a pack bought at the price a payment is holding at
            zero is the payment used, and the price goes back afterwards
            -- marking it used puts the price back there and then, and
            charging self.cost after that charged this player the full
            price for the pack they were told was free.
        */
        cost = self.cost;
        paid_pack = is_true( self.zs_zeroed ) && cost == 0;

        flag_set( "pack_machine_in_use" );

        player [[ level.zs_f_score_minus ]]( cost );

        if ( paid_pack )
            self zs_pap_paid_used( player );
        playsoundatposition( "evt_bottle_dispense", self.origin );

        self thread [[ level.zs_f_jingle ]]( "mus_perks_packa_sting" );
        player [[ level.zs_f_dialog ]]( "weapon_pickup", "upgrade_wait" );

        origin = self.origin;
        angles = self.angles;

        if ( isdefined( perk_machine ) )
        {
            origin = perk_machine.origin + ( 0, 0, 35 );
            angles = perk_machine.angles + ( 0, 90, 0 );
        }

        self [[ level.zs_f_disable ]]();

        player thread [[ level.zs_f_knuckle ]]();

        self.current_weapon = current_weapon;

        weaponmodel = player [[ level.zs_f_third_person ]]( current_weapon, origin, angles, packa_rollers, perk_machine );

        self [[ level.zs_f_enable ]]();
        self sethintstring( &"ZOMBIE_GET_UPGRADED" );
        self setvisibletoplayer( player );

        // ZShare: whose weapon is waiting, for the watcher and the share.
        self.zs_pap_owner = player;
        self.zs_pap_shared = 0;
        self.zs_pap_window = 1;
        self.zs_hint = "";
        self thread zs_pap_window_end();

        self thread zs_pap_take( player, current_weapon, packa_timer );
        self thread [[ level.zs_f_pap_timeout ]]( current_weapon, packa_timer );

        self waittill_either( "pap_timeout", "pap_taken" );

        self.current_weapon = "";

        if ( isdefined( weaponmodel.worldgundw ) )
            weaponmodel.worldgundw delete();

        weaponmodel delete();
        self sethintstring( &"ZOMBIE_PERK_PACKAPUNCH", self.cost );
        self.zs_hint = "";
        self setvisibletoall();
        flag_clear( "pack_machine_in_use" );
    }
}

/*
    Ends the window whichever way it closes. waittill_any_return(), not
    waittill_any(): waittill_any() ends its thread on every notify but
    the first, so nothing after it would run on a take.
*/
zs_pap_window_end()
{
    self notify( "zs_pap_window_end" );
    self endon( "zs_pap_window_end" );

    self waittill_any_return( "pap_timeout", "pap_taken", "death" );

    self.zs_pap_window = 0;
    self.zs_pap_shared = 0;
    self.zs_pap_owner = undefined;
}

/*
    wait_for_player_to_take() from _zombiemode_perks.gsc, with the share
    branch: the owner's crouched press shares the weapon, and once it is
    shared, whoever presses is the taker.
*/
zs_pap_take( player, weapon, packa_timer )
{
    upgrade_weapon = level.zombie_weapons[weapon].upgrade_name;

    self endon( "pap_timeout" );

    for ( ;; )
    {
        packa_timer playloopsound( "zmb_perks_packa_ticktock" );
        self waittill( "trigger", trigger_player );
        packa_timer stoploopsound( 0.05 );

        // ZShare: crouched, and it is yours -- share it.
        if ( self zs_pap_share_press( trigger_player, player ) )
        {
            wait 0.05;
            continue;
        }

        // ZShare: once shared, whoever pressed is the taker.
        if ( is_true( self.zs_pap_shared ) && isplayer( trigger_player ) )
            player = trigger_player;

        if ( trigger_player == player )
        {
            current_weapon = player getcurrentweapon();

            if ( [[ level.zs_f_valid ]]( player ) && !player [[ level.zs_f_drinking ]]() && ![[ level.zs_f_mine ]]( current_weapon ) && ![[ level.zs_f_equipment ]]( current_weapon ) && "syrette_sp" != current_weapon && "none" != current_weapon && !zs_hacker_out( player ) )
            {
                self notify( "pap_taken" );
                player notify( "pap_taken" );
                player.pap_used = true;

                weapon_limit = 2;

                if ( player hasperk( "specialty_additionalprimaryweapon" ) )
                    weapon_limit = 3;

                primaries = player getweaponslistprimaries();

                if ( isdefined( primaries ) && primaries.size >= weapon_limit )
                {
                    player [[ level.zs_f_weapon_give ]]( upgrade_weapon );
                }
                else
                {
                    player giveweapon( upgrade_weapon, 0, player [[ level.zs_f_pap_options ]]( upgrade_weapon ) );
                    player givestartammo( upgrade_weapon );
                }

                player switchtoweapon( upgrade_weapon );
                player [[ level.zs_f_weapon_vo ]]( upgrade_weapon );
                return;
            }
        }

        wait 0.05;
    }
}

zs_pap_share_press( trigger_player, player )
{
    zs_load_config();

    if ( !isdefined( trigger_player ) || !isdefined( player ) || trigger_player != player )
        return 0;

    if ( !zs_pap_shareable( self, player ) || !zs_crouched( trigger_player ) )
        return 0;

    self zs_pap_share( player );
    return 1;
}

/*
    Whether player's upgraded weapon is waiting in this machine and can
    still be shared. The crouched press and the chat word both ask.
*/
zs_pap_shareable( trig, player )
{
    if ( !isdefined( trig ) || !isdefined( player ) )
        return 0;

    if ( !level.zs.pap_share || is_true( trig.zs_pap_shared ) || !is_true( trig.zs_pap_window ) )
        return 0;

    if ( !isdefined( trig.zs_pap_owner ) || trig.zs_pap_owner != player )
        return 0;

    return 1;
}

zs_pap_share( player )
{
    self.zs_pap_shared = 1;
    self.zs_shared_by = player;

    zs_say_all( "^3" + player.name + "^7 shared their Pack-a-Punched weapon -- anyone can take it" );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "pap shared by " + player.name );
}

/*
    From power-on for the life of the game: the payment's price, who sees
    which trigger, and the words on both.
*/
zs_pap_watch()
{
    level endon( "end_game" );
    self endon( "death" );

    if ( !isdefined( self.zs_pay_trig ) )
        self.zs_pay_trig = self zs_machine_trigger( "pap" );

    tick = 0;

    for (;;)
    {
        wait 0.1;

        tick++;

        self zs_machine_trigger_sync( self.zs_pay_trig );
        self zs_pap_price_maintain();
        self zs_pap_visibility();
        self zs_pap_hints( tick % 10 == 0 );
    }
}

/*
    While a weapon waits, the machine shows it to its owner alone until
    it is shared, then to anyone who could take it -- the take prompt is
    nobody else's business before that. Otherwise the stock rules: any
    player who could buy, except one with the hacker out, and except a
    player reading the pay prompt.
*/
zs_pap_visibility()
{
    t = self.zs_pay_trig;
    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];

        if ( !isdefined( p ) )
            continue;

        if ( is_true( self.zs_pap_window ) )
        {
            zs_trigger_show( t, p, 0 );

            if ( is_true( self.zs_pap_shared ) )
                show = zs_player_ok( p );
            else
                show = isdefined( self.zs_pap_owner ) && p == self.zs_pap_owner;

            self setinvisibletoplayer( p, !show );
            continue;
        }

        pay = self zs_pap_pay_ok( p );
        zs_trigger_show( t, p, pay );

        if ( pay || zs_hacker_out( p ) || !p [[ level.zs_f_can_buy ]]() )
            self setinvisibletoplayer( p, true );
        else
            self setinvisibletoplayer( p, false );
    }
}

zs_pap_pay_ok( p )
{
    if ( !isdefined( p ) || !zs_crouched( p ) )
        return 0;

    if ( is_true( self.zs_pap_window ) || is_true( self.disabled ) || is_true( self.trigger_off ) || is_true( level.pap_moving ) || zs_flag( "pack_machine_in_use" ) )
        return 0;

    if ( is_true( self.zs_paid ) )
        return isdefined( self.zs_paid_by ) && self.zs_paid_by == p && zs_payer_ok( p );

    if ( !level.zs.pap_pay || !zs_pay_team_check() || zs_bonfire_on() )
        return 0;

    if ( !isdefined( self.cost ) || self.cost <= 0 )
        return 0;

    return zs_payer_ok( p ) && p [[ level.zs_f_can_buy ]]();
}

zs_pap_hints( force )
{
    t = self.zs_pay_trig;

    if ( is_true( self.zs_paid ) )
        zs_set_hint( t, "Hold ^3[{+activate}]^7 to take back your payment" );
    else if ( isdefined( self.cost ) )
        zs_set_hint( t, "Hold ^3[{+activate}]^7 to buy a Pack-a-Punch for a teammate [Cost: " + self.cost + "]" );

    if ( !isdefined( self.zs_hint ) )
        self.zs_hint = "";

    if ( is_true( self.zs_pap_window ) )
    {
        if ( is_true( self.zs_pap_shared ) )
            want = "shared";
        else if ( level.zs.pap_share && isdefined( self.zs_pap_owner ) && zs_crouched( self.zs_pap_owner ) )
            want = "share";
        else
            want = "stock";

        if ( want == self.zs_hint )
            return;

        self.zs_hint = want;

        if ( want == "shared" )
            self sethintstring( "Hold ^3[{+activate}]^7 to take the shared weapon" );
        else if ( want == "share" )
            self sethintstring( "Hold ^3[{+activate}]^7 to share this weapon" );
        else
            self sethintstring( &"ZOMBIE_GET_UPGRADED" );

        return;
    }

    // The bonfire sale's thread writes the price line on its own, so a
    // held price goes back up once a second.
    if ( force && is_true( self.zs_zeroed ) && !is_true( self.disabled ) )
        self sethintstring( &"ZOMBIE_PERK_PACKAPUNCH", 0 );
}

zs_pap_pay_press( player )
{
    if ( !self zs_pap_pay_ok( player ) )
        return;

    if ( is_true( self.zs_paid ) )
    {
        self zs_pap_take_back( player );
        return;
    }

    cost = self.cost;

    if ( player.score < cost )
    {
        self playsound( "deny" );
        player [[ level.zs_f_dialog ]]( "general", "perk_deny", undefined, 0 );
        player zs_say( "You need " + cost + " points" );
        return;
    }

    before = player.score;
    zs_score_minus( player, cost );

    self.zs_paid = 1;
    self.zs_paid_by = player;
    self.zs_paid_name = player.name;
    self.zs_paid_amount = before - player.score;

    self zs_pap_price_maintain();
    self thread [[ level.zs_f_jingle ]]( "mus_perks_packa_sting" );

    player zs_say( "Paid for the next Pack-a-Punch -- the next teammate to use the machine packs free" );
    zs_say_others( player, "^3" + player.name + "^7 paid for the next Pack-a-Punch -- use the machine to pack free" );
    player zs_sound( level.zs.points_sound );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "pap paid by " + player.name + ": " + self.zs_paid_amount );
}

zs_pap_take_back( player )
{
    amount = self.zs_paid_amount;

    self zs_pap_paid_clear();

    if ( isdefined( amount ) && amount > 0 )
        zs_score_add( player, amount );

    player zs_say( "Took back your payment for the Pack-a-Punch" );
    zs_say_others( player, "^3" + player.name + "^7 took back their payment for the Pack-a-Punch" );
    player zs_sound( level.zs.points_sound );
}

zs_pap_paid_clear()
{
    self.zs_paid = 0;
    self.zs_paid_by = undefined;
    self.zs_paid_name = undefined;
    self.zs_paid_amount = undefined;

    self zs_pap_price_restore();
}

zs_pap_paid_used( taker )
{
    payer = self.zs_paid_by;
    name = self.zs_paid_name;

    self zs_pap_paid_clear();

    if ( isdefined( taker ) && isdefined( payer ) && taker != payer )
    {
        taker zs_say( "^3" + name + "^7 paid for this Pack-a-Punch" );
        taker zs_favour_note( payer );
        payer zs_say( "^3" + taker.name + "^7 used the Pack-a-Punch you paid for" );
    }

    zs_debug( "paid pack used" );
}

/*
    Zero while a pack is paid for, the machine is idle, and no bonfire
    sale is on; whatever the stock code set the rest of the time. The
    bonfire sale writes its own price when it starts and ends, so a paid
    pack waits the sale out and comes back afterwards.
*/
zs_pap_price_maintain()
{
    if ( !is_true( self.zs_paid ) || is_true( self.zs_pap_window ) || zs_bonfire_on() || !isdefined( self.cost ) )
    {
        self zs_pap_price_restore();
        return;
    }

    if ( is_true( self.zs_zeroed ) && self.cost == 0 )
        return;

    if ( self.cost != 0 )
        self.zs_cost_saved = self.cost;

    self.cost = 0;
    self.zs_zeroed = 1;

    if ( !is_true( self.disabled ) )
        self sethintstring( &"ZOMBIE_PERK_PACKAPUNCH", 0 );
}

zs_pap_price_restore()
{
    if ( !is_true( self.zs_zeroed ) )
        return;

    self.zs_zeroed = 0;

    // A bonfire sale that started meanwhile has already written its own
    // price, and that one stands.
    if ( isdefined( self.cost ) && self.cost == 0 && isdefined( self.zs_cost_saved ) )
        self.cost = self.zs_cost_saved;

    if ( !is_true( self.zs_pap_window ) && !is_true( self.disabled ) )
        self sethintstring( &"ZOMBIE_PERK_PACKAPUNCH", self.cost );
}


/* ==================================================================
    PERK MACHINES

    The purchase loop and give_perk() are Plutonium's own detours on T5,
    and the price is a local inside the loop, so nothing ZShare does
    goes through them. What ZShare replaces is the visibility loop,
    check_player_has_perk(): its copy decides, for each player near the
    machine, which of three prompts they read --

        stock  the machine's own, bought the stock way
        pay    ZShare's pay prompt, for a crouched payer
        buy    ZShare's drink prompt: a drink somebody paid for, or a
               player whose perk limit ZShare keeps rather than the four
               written into the loop

    -- and the drink prompt pours through the same stock pieces the loop
    does: the bottle, the animation, level.perk_bought_func, give_perk().
   ================================================================== */

zs_perk_functions()
{
    level.zs_f_bottle_begin = getfunction( "maps/_zombiemode_perks", "perk_give_bottle_begin" );
    level.zs_f_bottle_end   = getfunction( "maps/_zombiemode_perks", "perk_give_bottle_end" );
    level.zs_f_give_perk    = getfunction( "maps/_zombiemode_perks", "give_perk" );

    need = [];
    need[need.size] = level.zs_f_bottle_begin;
    need[need.size] = level.zs_f_bottle_end;
    need[need.size] = level.zs_f_give_perk;
    need[need.size] = level.zs_f_laststand;
    need[need.size] = level.zs_f_jingle;
    need[need.size] = level.zs_f_dialog;
    need[need.size] = level.zs_f_drinking;
    need[need.size] = level.zs_f_score_minus;

    if ( need.size != 8 )
    {
        println( "ZShare: a perk function was not found -- the machines stay stock" );
        return 0;
    }

    return 1;
}

/*
    check_player_has_perk() from _zombiemode_perks.gsc, run from power-on:
    stock hides the machine from anyone within 128 units who owns the
    perk, is standing in a revive, or has the hacker out, and that is all
    still here. Plutonium's Quick Revive copy starts it through the same
    name, so this is every machine's.
*/
zs_perk_visibility( perk )
{
    self endon( "death" );

    if ( !isdefined( self.zs_pay_trig ) )
        self.zs_pay_trig = self zs_machine_trigger( "pay" );

    if ( !isdefined( self.zs_buy_trig ) )
        self.zs_buy_trig = self zs_machine_trigger( "buy" );

    dist = 128 * 128;

    for (;;)
    {
        self zs_machine_trigger_sync( self.zs_pay_trig );
        self zs_machine_trigger_sync( self.zs_buy_trig );
        self zs_perk_hints();

        players = get_players();

        for ( i = 0; i < players.size; i++ )
        {
            p = players[i];

            if ( !isdefined( p ) || distancesquared( p.origin, self.origin ) >= dist )
                continue;

            route = self zs_perk_route( p, perk );

            zs_trigger_show( self.zs_pay_trig, p, route == "pay" );
            zs_trigger_show( self.zs_buy_trig, p, route == "buy" );
            self setinvisibletoplayer( p, route != "stock" );
        }

        wait 0.1;
    }
}

zs_perk_route( p, perk )
{
    if ( self zs_perk_pay_ok( p ) )
        return "pay";

    if ( p hasperk( perk ) || zs_in_revive_trigger( p ) || zs_hacker_out( p ) )
        return "none";

    if ( is_true( self.zs_paid ) )
        return "buy";

    if ( level.zs.perk_limit != 0 && isdefined( p.num_perks ) )
    {
        // At ZShare's limit: refused on the drink prompt, the way the
        // stock loop refuses at four.
        if ( p.num_perks >= zs_perk_limit_for( p ) )
            return "buy";

        // Allowed past the stock four, which the loop would refuse.
        if ( p.num_perks >= 4 )
            return "buy";
    }

    return "stock";
}

/*
    0 is the stock four, -1 is no limit, anything else is the limit.
*/
zs_perk_limit_for( p )
{
    if ( level.zs.perk_limit == 0 )
        return 4;

    if ( level.zs.perk_limit < 0 )
        return 99;

    return level.zs.perk_limit;
}

zs_perk_pay_ok( p )
{
    if ( !isdefined( p ) || !zs_crouched( p ) )
        return 0;

    if ( is_true( self.disabled ) || is_true( self.trigger_off ) )
        return 0;

    if ( is_true( self.zs_paid ) )
        return isdefined( self.zs_paid_by ) && self.zs_paid_by == p && zs_payer_ok( p );

    if ( !level.zs.perk_pay || !zs_pay_team_check() )
        return 0;

    if ( !isdefined( self.cost ) || !isdefined( self.script_noteworthy ) )
        return 0;

    return zs_payer_ok( p );
}

/*
    The pay prompt reads the same for everybody who can see it. The drink
    prompt is the machine's own localized line, at 0 while a drink is
    paid for and at its price otherwise.
*/
zs_perk_hints()
{
    if ( is_true( self.zs_paid ) )
        zs_set_hint( self.zs_pay_trig, "Hold ^3[{+activate}]^7 to take back your payment" );
    else if ( isdefined( self.cost ) )
        zs_set_hint( self.zs_pay_trig, "Hold ^3[{+activate}]^7 to buy this perk for a teammate [Cost: " + self.cost + "]" );

    t = self.zs_buy_trig;

    if ( !isdefined( t ) || !isdefined( self.script_noteworthy ) || !isdefined( self.cost ) )
        return;

    cost = self.cost;

    if ( is_true( self.zs_paid ) )
        cost = 0;

    key = self.script_noteworthy + ":" + cost;

    if ( key == t.zs_hint )
        return;

    t.zs_hint = key;

    ref = zs_perk_hint_ref( self.script_noteworthy );

    if ( isdefined( ref ) )
        t sethintstring( ref, cost );
    else
        t sethintstring( self.script_noteworthy + " Cost: " + cost );
}

zs_perk_hint_ref( perk )
{
    switch ( perk )
    {
        case "specialty_armorvest_upgrade":
        case "specialty_armorvest":
            return &"ZOMBIE_PERK_JUGGERNAUT";

        case "specialty_quickrevive_upgrade":
        case "specialty_quickrevive":
            if ( zs_flag( "solo_game" ) )
                return &"ZOMBIE_PERK_QUICKREVIVE_SOLO";

            return &"ZOMBIE_PERK_QUICKREVIVE";

        case "specialty_fastreload_upgrade":
        case "specialty_fastreload":
            return &"ZOMBIE_PERK_FASTRELOAD";

        case "specialty_rof_upgrade":
        case "specialty_rof":
            return &"ZOMBIE_PERK_DOUBLETAP";

        case "specialty_longersprint_upgrade":
        case "specialty_longersprint":
            return &"ZOMBIE_PERK_MARATHON";

        case "specialty_flakjacket_upgrade":
        case "specialty_flakjacket":
            return &"ZOMBIE_PERK_DIVETONUKE";

        case "specialty_deadshot_upgrade":
        case "specialty_deadshot":
            return &"ZOMBIE_PERK_DEADSHOT";

        case "specialty_additionalprimaryweapon_upgrade":
        case "specialty_additionalprimaryweapon":
            return &"ZOMBIE_PERK_ADDITIONALPRIMARYWEAPON";
    }

    return undefined;
}

zs_perk_pay_press( player )
{
    if ( !self zs_perk_pay_ok( player ) )
        return;

    if ( is_true( self.zs_paid ) )
    {
        self zs_perk_take_back( player );
        return;
    }

    perk = self.script_noteworthy;
    cost = self.cost;

    if ( player.score < cost )
    {
        self playsound( "evt_perk_deny" );
        player [[ level.zs_f_dialog ]]( "general", "perk_deny", undefined, 0 );
        player zs_say( "You need " + cost + " points" );
        return;
    }

    before = player.score;
    zs_score_minus( player, cost );

    self.zs_paid = 1;
    self.zs_paid_by = player;
    self.zs_paid_name = player.name;
    self.zs_paid_amount = before - player.score;

    self thread [[ level.zs_f_jingle ]]( self.script_label );

    what = zs_perk_name( perk );
    player zs_say( "Paid for " + what + " -- the next teammate to use the machine drinks it free" );
    zs_say_others( player, "^3" + player.name + "^7 paid for " + what + " -- use the machine to drink it free" );
    player zs_sound( level.zs.points_sound );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( perk + " paid by " + player.name + ": " + self.zs_paid_amount );
}

zs_perk_take_back( player )
{
    amount = self.zs_paid_amount;
    what = zs_perk_name( self.script_noteworthy );

    self zs_perk_paid_clear();

    if ( isdefined( amount ) && amount > 0 )
        zs_score_add( player, amount );

    player zs_say( "Took back your payment for " + what );
    zs_say_others( player, "^3" + player.name + "^7 took back their payment for " + what );
    player zs_sound( level.zs.points_sound );
}

zs_perk_paid_clear()
{
    self.zs_paid = 0;
    self.zs_paid_by = undefined;
    self.zs_paid_name = undefined;
    self.zs_paid_amount = undefined;
}

/*
    A press on the drink prompt: the stock loop's own checks, in its
    order, then a paid drink or a bought one.
*/
zs_perk_buy_press( player )
{
    perk = self.script_noteworthy;

    if ( !isdefined( perk ) || self zs_perk_route( player, perk ) != "buy" )
        return;

    if ( player [[ level.zs_f_laststand ]]() || is_true( player.intermission ) )
        return;

    if ( player isthrowinggrenade() || player isswitchingweapons() || player [[ level.zs_f_drinking ]]() )
        return;

    if ( isdefined( player.num_perks ) && player.num_perks >= zs_perk_limit_for( player ) )
    {
        self playsound( "evt_perk_deny" );
        player [[ level.zs_f_dialog ]]( "general", "sigh" );
        return;
    }

    if ( is_true( self.zs_paid ) )
    {
        payer = self.zs_paid_by;
        name = self.zs_paid_name;

        self zs_perk_paid_clear();

        if ( isdefined( payer ) && payer != player )
        {
            player zs_say( "^3" + name + "^7 paid for this one" );
            player zs_favour_note( payer );
            payer zs_say( "^3" + player.name + "^7 drank the " + zs_perk_short( perk ) + " you paid for" );
        }

        zs_debug( perk + " drunk free by " + player.name );
    }
    else
    {
        if ( player.score < self.cost )
        {
            self playsound( "evt_perk_deny" );
            player [[ level.zs_f_dialog ]]( "general", "perk_deny", undefined, 0 );
            return;
        }

        zs_score_minus( player, self.cost );
    }

    self thread zs_perk_pour( player, perk );
}

/*
    The stock purchase tail, from the bottle to give_perk(). Its own
    thread, so a player who disconnects mid-drink takes nothing else down
    with them.
*/
zs_perk_pour( player, perk )
{
    player endon( "disconnect" );

    playsoundatposition( "evt_bottle_dispense", self.origin );
    player.perk_purchased = perk;

    self thread [[ level.zs_f_jingle ]]( self.script_label );

    gun = player [[ level.zs_f_bottle_begin ]]( perk );
    player waittill_any_return( "fake_death", "death", "player_downed", "weapon_change_complete" );
    player [[ level.zs_f_bottle_end ]]( gun, perk );

    if ( player [[ level.zs_f_laststand ]]() || is_true( player.intermission ) )
        return;

    if ( isdefined( level.perk_bought_func ) )
        player [[ level.perk_bought_func ]]( perk );

    player.perk_purchased = undefined;
    player [[ level.zs_f_give_perk ]]( perk, true );
}

/*
    Chat lines only. A name never goes on a prompt, so this table is free
    to be English.
*/
zs_perk_name( perk )
{
    short = zs_perk_short( perk );

    if ( short == "perk" )
        return "a perk";

    return short;
}

zs_perk_short( perk )
{
    if ( !isdefined( perk ) )
        return "perk";

    switch ( perk )
    {
        case "specialty_armorvest_upgrade":
        case "specialty_armorvest":
            return "Juggernog";

        case "specialty_quickrevive_upgrade":
        case "specialty_quickrevive":
            return "Quick Revive";

        case "specialty_fastreload_upgrade":
        case "specialty_fastreload":
            return "Speed Cola";

        case "specialty_rof_upgrade":
        case "specialty_rof":
            return "Double Tap";

        case "specialty_longersprint_upgrade":
        case "specialty_longersprint":
            return "Stamin-Up";

        case "specialty_flakjacket_upgrade":
        case "specialty_flakjacket":
            return "PhD Flopper";

        case "specialty_deadshot_upgrade":
        case "specialty_deadshot":
            return "Deadshot Daiquiri";

        case "specialty_additionalprimaryweapon_upgrade":
        case "specialty_additionalprimaryweapon":
            return "Mule Kick";
    }

    return "perk";
}


/* ==================================================================
    PRESENTATION
   ================================================================== */

zs_say( txt )
{
    if ( !level.zs.messages || !isdefined( self ) )
        return;

    self iprintln( txt );
}

zs_say_all( txt )
{
    if ( !level.zs.messages )
        return;

    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) )
            players[i] iprintln( txt );
    }
}

zs_say_others( except, txt )
{
    if ( !level.zs.messages )
        return;

    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) )
            continue;

        if ( isdefined( except ) && players[i] == except )
            continue;

        players[i] iprintln( txt );
    }
}

zs_sound( alias )
{
    if ( !isdefined( alias ) || alias == "" || !isdefined( self ) )
        return;

    self playlocalsound( alias );
}

zs_sound_others( except, alias )
{
    if ( !isdefined( alias ) || alias == "" )
        return;

    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) )
            continue;

        if ( isdefined( except ) && players[i] == except )
            continue;

        players[i] playlocalsound( alias );
    }
}

zs_deny( why )
{
    self zs_say( why );
    self zs_sound( level.zs.deny_sound );
}

zs_debug( txt )
{
    if ( !isdefined( level.zs ) || !is_true( level.zs.debug ) )
        return;

    println( "ZShare: " + txt );

    players = get_players();

    if ( players.size > 0 && isdefined( players[0] ) )
        players[0] iprintln( "^5[zs]^7 " + txt );
}

zs_game_ready()
{
    if ( is_true( level.intermission ) )
        return 0;

    return isdefined( level.round_number );
}


/* ==================================================================
    THE SHARED MOD API

    Xep's mods find each other on level.zmods: an array keyed by mod id,
    each key a struct saying what that mod is and handing over the few
    things another mod may ask it to do. ZShare's goes up as the script
    finishes loading, and again -- saying enabled 0 -- when zs_enabled is
    off, since "not installed" and "installed and switched off" are
    different answers.

    api_version 1 is this. The descriptor is the contract: level.zs is
    ZShare's own struct and may move.
   ================================================================== */

/*
    The version on its own -- no build time, no origin -- because that is
    what the descriptor carries for another mod to read. Written by
    tools/build.py between the markers; never edit it by hand.
*/
zs_version()
{
    // ZS_VERSION_BEGIN
    return "1.3";
    // ZS_VERSION_END
}

/*
    The descriptor. Written into whatever registry is already there --
    another mod may have made it first, and replacing the array would be
    that mod's entry gone.
*/
zs_api_register( benabled )
{
    if ( !isdefined( level.zmods ) )
        level.zmods = [];

    if ( !isdefined( level.zmods[ "zshare" ] ) )
        level.zmods[ "zshare" ] = spawnstruct();

    mod = level.zmods[ "zshare" ];

    mod.id = "zshare";
    mod.display_name = "ZShare";
    mod.version = zs_version();
    mod.api_version = 1;
    mod.settings_manifest_version = 1;
    mod.enabled = benabled;

    mod.reload_config = ::zs_api_reload_config;
    mod.get_stock_perk_limit = ::zs_api_stock_perk_limit;
    mod.get_effective_perk_limit = ::zs_api_effective_perk_limit;
}

/*
    Read the settings again -- for a mod that has just written one of
    ZShare's dvars and wants it to count now rather than at the next
    press. 1 when there was something to read.
*/
zs_api_reload_config()
{
    if ( !is_true( level.zs_loaded ) || !isdefined( level.zs ) || !level.zs.enabled )
        return 0;

    zs_load_config();
    return 1;
}

/*
    The limit the map would give this player if ZShare were not here.
    Black Ops exposes no callback to keep -- every map with perks has four
    machines and no map hands out a fifth slot -- so the stock limit is
    that four, which is what zs_perk_limit_for() falls back to.
*/
zs_api_stock_perk_limit( player )
{
    return 4;
}

/*
    And the limit ZShare is actually holding the map to. Where its gate is
    not installed, which is zs_enabled 0, the honest answer is the map's own.
*/
zs_api_effective_perk_limit( player )
{
    if ( !is_true( level.zs_loaded ) || !isdefined( level.zs ) || !level.zs.enabled )
        return zs_api_stock_perk_limit( player );

    return zs_perk_limit_for( player );
}


/* ==================================================================
    BUILD STAMP

    A development build says so on screen: its version and the time it
    was built, top right, one line under ZPause's. Release builds carry
    an empty stamp and draw nothing.
   ================================================================== */

/*
    Written by tools/build.py. The line between the markers is generated --
    a version and a build time on a development build, an empty string on
    a release. Do not edit it by hand; the next build will overwrite it.
*/
zs_build()
{
    // ZS_BUILD_BEGIN
    return "";
    // ZS_BUILD_END
}

/*
    Hands the value straight back, so it can wrap a return. Silent unless
    zs_config_printer() has the echo on.
*/
zs_cfg_echo( dvar, value, def )
{
    if ( !is_true( level.zs_cfg_echo ) )
        return value;

    println( "  " + dvar + "  " + value );

    if ( isdefined( level.zs_cfg_host ) && value != ( "" + def ) )
        level.zs_cfg_host iprintln( "^3" + dvar + "^7  " + value );

    return value;
}

zs_config_watcher()
{
    level endon( "end_game" );

    for (;;)
    {
        wait 5;
        zs_load_config();
    }
}

/*
    "set zs_config_print 1" in the console prints every setting and the
    value it is currently holding, then puts the switch back.
*/
zs_config_printer()
{
    level endon( "end_game" );

    if ( getdvar( "zs_config_print" ) == "" )
        setdvar( "zs_config_print", "0" );

    for ( ;; )
    {
        wait 1;

        if ( getdvar( "zs_config_print" ) != "1" )
            continue;

        setdvar( "zs_config_print", "0" );

        println( "---- ZShare settings ----" );

        level.zs_cfg_host = undefined;
        zs_cfg_players = get_players();

        if ( zs_cfg_players.size > 0 )
            level.zs_cfg_host = zs_cfg_players[0];

        if ( isdefined( level.zs_cfg_host ) )
            level.zs_cfg_host iprintln( "^3[ZShare]^7 settings changed from default:" );

        level.zs_cfg_echo = 1;
        zs_load_config();
        level.zs_cfg_echo = 0;

        if ( isdefined( level.zs_cfg_host ) )
            level.zs_cfg_host iprintln( "^3[ZShare]^7 end of settings" );

        level.zs_cfg_host = undefined;
        println( "---- end ----" );
    }
}

/*
    A plain newhudelem(), because Black Ops' createServerFontString() lives
    in a script a zombies script cannot include. The stock element tally
    is kept honest, as ZPause's T5 port keeps it.

    Scale 1.1: a font scale below 1 draws larger on this engine, not
    smaller.
*/
zs_build_watermark()
{
    level endon( "end_game" );

    stamp = zs_build();

    if ( stamp == "" )
        return;

    while ( !zs_game_ready() )
        wait 0.5;

    if ( isdefined( level.zs_build_hud ) )
        return;

    e = newhudelem();

    if ( isdefined( level.hudelem_count ) )
        level.hudelem_count++;

    e.horzalign = "right";
    e.vertalign = "top";
    e.alignx = "right";
    e.aligny = "top";
    e.x = 0;
    e.y = 26;
    e.fontscale = 1.1;
    e.color = ( 0.55, 0.85, 1 );
    e.sort = 1000;
    e.foreground = 1;
    e.alpha = 0.7;
    e settext( stamp );

    level.zs_build_hud = e;
}
