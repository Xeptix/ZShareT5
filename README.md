# ZShare T5

**Weapon sharing for Black Ops Zombies (Plutonium T5)**

by Xep

[**Download the latest release**](https://github.com/Xeptix/ZShareT5/releases/latest)

Trade guns with a teammate, hand them points, give away a box hit or a Pack-a-Punch you
don't want, and pay for a teammate's perk, spin or pack. All of it from the use button,
with prompts that read like the game's own.

- Look at a teammate and press **use** to trade weapons. Ammo, the attachment and the
  Pack-a-Punch camo go with the gun.
- **Crouch** first and the same press gives them 1000 points instead.
- Crouch and press use at the **box** while the weapon you paid for is up, and anyone can
  take it. The same at the **Pack-a-Punch**.
- Crouch and press use at a **perk machine**, or at the box or the Pack-a-Punch while
  nobody is using it, and the next teammate to use it pays nothing.

This is the Black Ops port of [ZShare](https://github.com/Xeptix/ZShare). Every port has the
same settings, with the same names, defaults and meanings.

---

## Requirements

Plutonium T5 (Black Ops), zombies. No other mods or dependencies.

**Only the host needs this file.** Every part of ZShare runs on the host and reaches
everyone else as ordinary server-to-client traffic — the prompts, the swap, the box, the
machines, the points, the sounds. Players joining your game install nothing.

---

## Install

Copy the **`Plutonium`** folder from the download into:

```
%localappdata%
```

It mirrors your existing `%localappdata%\Plutonium` exactly, so Windows will ask whether
to merge — say yes. The only thing it replaces is an older `zshare.gsc`.

That puts the file here:

```
%localappdata%\Plutonium\storage\t5\raw\scripts\sp\zshare.gsc
```

Black Ops zombies runs on the singleplayer script tree, which is why the folder is `sp`.
There is no mod packaging for this game — Plutonium's Mods menu is Black Ops II only — so
the script is the whole install.

### Or run the installer

The download has an **`installer`** folder, one for each system:

```
installer\windows\install.bat
installer/linux/install.sh
```

Each one finds Plutonium's folder, shows you what it is about to copy, and asks once. On
Linux, `install.sh` looks where Plutonium ends up under Wine or Proton — Steam's
`compatdata` including a Steam Deck's, Heroic, Lutris, Bottles, plain `~/.wine`, and the
Flatpak version of each. `install.bat -Yes` and `install.sh --yes` copy without asking, `-Uninstall` / `--uninstall`
removes what an install put there, and `-Find` / `--find` only shows what it detects. When it
can't find your game, `-To <folder>` / `--to <folder>` points it there.

On a Steam Deck, switch to Desktop Mode and double-click
**`installer/linux/Install ZShare.desktop`**. KDE will not run a desktop entry until you
allow it once: right-click it, **Properties** → **Permissions** → tick **Is executable**.

It's optional. Dragging the `Plutonium` folder across yourself is identical.

You don't need to restart the game to load a script — just end the current game and start
a new one.

---

## Usage

Every action is a prompt on screen, the same kind the game shows at a door or a wall buy.
What a prompt says is what a press of **use** will do.

| Prompt | When you see it | What the press does |
|---|---|---|
| `Hold [use] to trade weapons` | Looking at a teammate | Offers them the weapon in your hands |
| `Hold [use] to accept the trade` | Looking at a teammate who offered you a trade | Swaps their offered weapon for the one you're holding |
| `Hold [use] to cancel the trade` | Looking at the teammate you offered a trade to | Withdraws the offer |
| `Hold [use] to give 1000 points` | **Crouched**, looking at a teammate | Gives them 1000 points |
| `Hold [use] to thank them (100 points)` | **Crouched**, looking at someone who just did you a good turn | Sends them 100 of your points |
| `Hold [use] to share this weapon` | **Crouched** at the box or the Pack-a-Punch, with the weapon you paid for waiting | Lets anyone take it |
| `Hold [use] to take the shared weapon` | Looking at a box or Pack-a-Punch somebody shared | Takes it |
| `Hold [use] to buy this perk for a teammate [Cost: 2500]` | **Crouched** at a perk machine | Pays for the next drink from it |
| `Hold [use] to buy a spin for a teammate [Cost: 950]` | **Crouched** at the box while nobody is using it | Pays for the next spin |
| `Hold [use] to buy a Pack-a-Punch for a teammate [Cost: 5000]` | **Crouched** at the Pack-a-Punch while nobody is using it | Pays for the next pack |
| `Hold [use] to take back your payment` | **Crouched** at a machine you paid for | Gives you your points back |
| `Hold [use] for a Random Weapon [Cost: 0]` | At a box a teammate paid for | Spins it for free |
| The machine's own prompt, at `[Cost: 0]` | At a perk machine or Pack-a-Punch a teammate paid for | Uses it for free |

Crouching is the whole modifier. Stand up and every prompt goes back to what it always was;
crouch and it turns into giving. Nothing else changes about how you play.

A few chat words, for when you've already walked away:

| Action | Input |
|---|---|
| Share the box hit or Pack-a-Punch you paid for | type `!share` |
| Thank whoever just did you a good turn | **Crouch**, look at them, press **use** — or type `!thank` |
| Send any amount of points | type `!tip 500`, or `!tip <name> 500` |

---

## Trading

What you offer is **the weapon in your hands** when you press. Your teammate can see it
there; nothing needs naming. What you get back is **whatever they're holding** when they
accept — so they switch to the gun they want to give before pressing.

An offer stays open for 10 seconds. It lapses on its own if you switch to your other
weapon, if the two of you move more than twice the prompt range apart, or if either of
you goes down. Pressing use on them again withdraws it. Offering to somebody else replaces
it, and both of you are told either way.

If they've offered you a trade at the same time, either one of you pressing use completes
it.

**What travels with a gun:** the clip, the reserve ammo, the grenade launcher,
flamethrower or masterkey underneath and its ammo, the left-hand gun of a dual wield, the
Pack-a-Punch upgrade, and the exact camo it was rolled with. It arrives as the same weapon
that left.

**What can't be traded:** grenades, the knife, placeable mines, equipment such as the
hacker, the Death Machine while you have it, and the revive syrette — each has its own slot
and its own rules, and the box won't take your money for one either.

**Same gun twice.** Black Ops never lets you carry a gun and its Pack-a-Punched version
together — the box and the wall both check. A trade that would leave someone holding both
is refused the same way.

---

## Sharing a box hit

You pay, the weapon rises, and for twelve seconds it's yours to take. **Crouch and press
use** at the box and it's everyone's: the box prompt changes for the whole room, and
whoever presses use takes it — you included, if nobody's quicker. The weapon stays up for
the same twelve seconds it always did.

This is the state the game already puts a box in after Moon's hacker re-spins it, so the
box is doing nothing it doesn't do on its own.

## Sharing at the Pack-a-Punch

The same at the machine. Crouch and press use while your upgraded weapon is waiting, and
anyone can take it. Whoever does gets it exactly as the machine would have handed it to
you, and their current weapon is replaced as if they'd bought it themselves.

## Giving points

Crouch, look at a teammate, press use: 1000 points move from you to them, with the game's
own points sound and score popup on both sides. Each press is one gift, a second apart, so
three presses is 3000. You need the points to give them.

---

## Paying for a teammate

Crouch at a perk machine, or at the box or the Pack-a-Punch while nobody is using it, and
the prompt turns into an offer to pay for a teammate. Press use and you pay the machine's
price. From then on the machine's prompt reads **`[Cost: 0]`**, and the next teammate to
use it pays nothing — a drink from a perk machine, a spin from the box, a pack from the
Pack-a-Punch. Everybody hears about it, and whoever paid is told who used it.

One payment waits at a machine at a time. While yours is waiting, crouch at the machine
again and the prompt offers your points back. If you don't own that perk yourself, you can
stand up and drink it too.

Paying at the box and at the Pack-a-Punch is the other half of sharing there. Before
anybody uses the machine, a crouched press pays for the next use; while your weapon is
waiting in it, the same press gives the weapon away. The two never overlap, because the
machine can't be used while it spins or upgrades.

| When | What happens |
|---|---|
| A paid spin turns up the teddy bear | The spin cost nothing, so the game's own refund is nothing — whoever paid gets their points back instead |
| The box moves | The paid spin moves with it |
| A fire sale or a bonfire sale is on | Nobody can pay at the machine it discounts, and a payment already waiting holds until the sale ends |
| The teammate already holds as many perks as they're allowed | They're refused the way the machine refuses a purchase, and the drink stays paid for |
| You're playing solo | There's nobody to pay for, so the prompt never appears |

Stand up and every machine works exactly as it always has.

## The perk limit

`zs_perk_limit` sets how many perks a player can hold. `0`, the default, is the game's own
limit of four. Any other number replaces it, and `-1` removes the limit.

It's one limit whether a perk is bought or paid for by a teammate. A player allowed past
four buys from the same machine, at the same price, with the machine's own prompt.

---

## Configuration

Every setting is at the top of the file under `zs_load_config()`, and each one is also a
dvar of the same name. The script creates each dvar with its default on load, so you can
set them straight from the console:

```bash
zs_points_amount 500
```

The config is re-read every five seconds while the game runs, and again on every press,
so a change takes effect **almost straight away** — no map restart needed. Anything
already set in your config before the map loads is left alone.

`set zs_config_print 1` in the console prints every setting below with the value it is
currently holding, then puts the switch back so it can be used again.

| Dvar | Default | What it does |
|---|---|---|
| `zs_debug` | `0` | Print what the script decides and why, to the console and to the first player. |
| `zs_trade` | `1` | Trade weapons with a teammate. |
| `zs_trade_offer_time` | `10` | Seconds an offer stays open. |
| `zs_trade_upgraded` | `1` | Pack-a-Punched weapons can be traded. Off, and the prompt says so when you try. |
| `zs_range` | `64` | How close you have to be for the prompt to appear, in units. An offer lapses at twice this. |
| `zs_points` | `1` | Crouch and press use on a teammate to give them points. |
| `zs_points_amount` | `1000` | How many points one press gives. |
| `zs_points_cooldown` | `1` | Seconds between gifts from one player. |
| `zs_thank` | `1` | Thank whoever did you a good turn, and the `!tip` word. |
| `zs_thank_amount` | `100` | What one thank sends. Comes out of your own points. |
| `zs_thank_time` | `30` | How long a good turn stays thankable, in seconds. |
| `zs_box_share` | `1` | Crouch and press use at the box to share the weapon you paid for. |
| `zs_pap_share` | `1` | The same at the Pack-a-Punch. |
| `zs_perk_pay` | `1` | Crouch and press use at a perk machine to pay for a teammate's drink. Off stops new payments; one already waiting still works and can still be taken back. |
| `zs_box_pay` | `1` | The same at the box, for the next spin. |
| `zs_pap_pay` | `1` | The same at the Pack-a-Punch, for the next pack. |
| `zs_perk_limit` | `0` | How many perks a player can hold. `0` is the game's own limit, a number replaces it, `-1` is no limit. See [The perk limit](#the-perk-limit). |
| `zs_show_hint` | `1` | Tell players what the prompts do, once, shortly after they spawn. |
| `zs_messages` | `1` | The one-line messages — who traded with whom, who shared or paid for what, who gave points. Off leaves the prompts and the sounds. |
| `zs_offer_sound` | `zmb_perks_packa_ready` | Played to the player an offer is made to. `none` = silent. |
| `zs_trade_sound` | `zmb_whoosh` | Played to both players when a trade goes through. `none` = silent. |
| `zs_share_sound` | `zmb_perks_packa_ready` | Played to everyone else when a weapon is shared or a machine is paid for. `none` = silent. |
| `zs_points_sound` | `zmb_cha_ching` | Played when points are given, paid or handed back. `none` = silent. |
| `zs_deny_sound` | `zmb_no_cha_ching` | Played when a press can't do what the prompt said — not enough points, a weapon that can't be traded. `none` = silent. |

### Sounds

All five are stock aliases, so the script stays a single drop-in file. A custom sound
would have to be installed by **every player** rather than just the host, so ZShare uses
the game's own audio instead.

The defaults are what the game itself uses them for: `zmb_perks_packa_ready` is the chime
the Pack-a-Punch plays when your weapon is ready, `zmb_cha_ching` is the points sound
behind every purchase, and `zmb_no_cha_ching` is its refusal. Other aliases worth trying,
all played by the common zombies scripts and so present on every map:

| Alias | What it is |
|---|---|
| `zmb_box_poof` | The magic box vanishing. |
| `zmb_perks_power_on` | Power switch coming on. |
| `evt_perk_deny` | A perk machine's buzzer. |
| `deny` | The Pack-a-Punch's refusal. |

Swap one in from the console, or silence one with `none`:

```bash
zs_trade_sound zmb_box_poof
```

---

## How this port differs

The same features with the same settings as every other port, allowing for what Black Ops
gives a script:

- **No mod packaging.** Plutonium's Mods menu is Black Ops II only, so this port has no mod
  copy and none of the two settings that choose between the copies.
- **The free box prompt is ZShare's own words.** The box's own line has no price in it to
  set to 0, so a paid spin reads `Hold [use] for a Random Weapon [Cost: 0]`.
- **A paid drink is poured from ZShare's prompt on the machine**, with the machine's own
  words at `[Cost: 0]`. So is a drink past four when `zs_perk_limit` allows one.
- **No re-packs and no Grief.** Black Ops has neither, so neither has a rule here.
- **`none` silences a sound.** An empty dvar can't be set from in game on this engine.

---

## How it works

**The prompts on players are the game's own use triggers.** Every player carries one per
teammate, linked to them the way the ballistic knife's retrieval trigger links to what it
lands in, so it follows them and only lights up when that teammate looks at them. Because
they're real triggers, the engine decides which prompt wins when two overlap, exactly as it
does for a door beside a wall buy.

**A weapon changes hands piece by piece.** Black Ops has no helper that reads a weapon
whole, so ZShare reads what the game's own last stand reads — the clip, the left-hand clip,
the reserve — plus the attachment's ammo and the render options that hold the Pack-a-Punch
camo, and gives the gun back with all of it.

**The box already knows how to be shared, and how to be free.** After Moon's hacker
re-spins a box, the stock code marks it `box_rerespun` and hands the weapon to whoever
presses use; sharing sets that flag. After the hacker summons a box, the stock code marks it
`auto_open` and `no_charge` and opens it for the next player without charging; a paid spin
sets those two. Black Ops writes the box's grab into its think loop, so that loop is
replaced — through Plutonium's `replaceFunc` — with a copy of itself that decides who sees
the box and notices a paid spin opening.

**The Pack-a-Punch reads its price off its trigger on every press.** A paid pack holds that
price at zero until somebody uses it. The machine's loop is replaced with a copy that runs
ZShare's own decisions about who sees it, and its take loop carries the share branch.

**A paid drink goes through the game's own drinking code.** Black Ops keeps a perk's price
inside the machine's loop, so a teammate drinking a paid perk uses a second prompt on the
machine, with the machine's own words, and drinks it through the stock bottle, animation and
perk code. The machine's visibility loop is replaced so its own prompt steps aside for
exactly that player.

**Points go through the game's own score helpers**, which draw the popups. A gift doesn't
count as points you earned.

**Every prompt is one of a fixed handful of strings.** Hint strings are configstrings, a
pool that doesn't recycle, so a weapon name or a player name never goes on a prompt. Names
go in the chat line, which isn't one.

---

## Notes

- **Prompts and other prompts.** A teammate standing in front of a door or a perk machine
  shares the space with it; the engine shows whichever prompt you're looking at most
  directly, the way it always has. Step around them if you get the door.
- **Crouching over a downed teammate** revives them. The pay prompt steps aside for a
  revive, the same way the machine's own prompt does.
- **Trading mid-reload or mid-throw.** A trade waits a beat for a weapon switch or a
  grenade throw to finish, and then goes through.
- **Downed players** have no prompt and can't accept one. Going down lapses an open offer
  in either direction.
- **Moon's hacker.** A box the hacker has re-spun is already anyone's; sharing it again
  does nothing new. A box the hacker has summoned is already free, so it can't be paid for.
- **Moving machines.** Shi No Numa's perk machines, and the Pack-a-Punch on Five, Call of
  the Dead and Shangri-La, carry the pay prompt with them.
- **Dead Ops Arcade** is left alone.
- **Custom maps** get all of it: the prompts, the box and the machines read nothing but the
  stock script structures every Black Ops zombies map is built on.

---

## Testing

Black Ops has no GSC compiler, so ZShare T5 is checked against the stock T5 script tree
instead: every function it calls is a real call a zombies script can reach, and every
entity field, notify, flag, sound alias and localized string it borrows exists there.

---

## Ports

| Game | Repo |
|---|---|
| Black Ops 4 (T8) | [ZShareT8](https://github.com/Xeptix/ZShareT8) |
| Black Ops III (T7) | [ZShareT7](https://github.com/Xeptix/ZShareT7) |
| Black Ops II (T6) | [ZShare](https://github.com/Xeptix/ZShare) |
| Black Ops (T5) | ZShareT5 — you are here |
| World at War (T4) | [ZShareT4](https://github.com/Xeptix/ZShareT4) |

Versions are kept in step: the same version number means the same feature set, allowing
for what each engine can actually do.

**All five in one download.** The [Treyarch
Bundle](https://github.com/Xeptix/ZShare/releases/latest) carries every game ZShare runs
on, laid out as each drops in — the `Plutonium` tree for this game and the other two, Black
Ops III's folders, Black Ops 4's mod folder — with one installer that asks which of them to
install.

---

## Changelog

### v1.2

- No changes to this port. The version moves with the other four.

### v1.1

- No changes to this port. The version moves with the other four.

### v1.0

- Initial release.
- **Trade weapons** with a teammate from the use prompt. Ammo, the attachment and the
  Pack-a-Punch camo travel with the gun.
- **Give points** with a crouched press of the same prompt. `zs_points_amount` sets how
  many.
- **Share a box hit** or a **Pack-a-Punch** with a crouched press at the machine, or with
  `!share` from chat.
- **Pay for a teammate** at a perk machine, the box or the Pack-a-Punch with a crouched
  press, and take the payment back the same way. `zs_perk_pay`, `zs_box_pay` and
  `zs_pap_pay` switch each one.
- **Thank a teammate** who paid for you, shared a hit or gave you points: for a while the
  crouched prompt on them offers a small thank, or type `!thank`. The points come out of
  your own. `zs_thank_amount` and `zs_thank_time` set how much and how long.
- **Tip any amount** with `!tip 500`, or `!tip <name> 500`.
- **`zs_perk_limit`** — how many perks a player can hold, or `-1` for no limit.
- Every setting is a dvar, re-read while the game runs, and `set zs_config_print 1` lists
  them all.

---

## Credits

- **Xep** — author
- **Treyarch** — `_zombiemode_weapons.gsc`, `_zombiemode_perks.gsc`, `_zombiemode_score.gsc`: everything this stands on
- **[plutoniummod/t5-scripts](https://github.com/plutoniummod/t5-scripts)** — stock T5 script reference

---

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it in a server pack. Keep the
copyright notice and the header block at the top of `zshare.gsc`.

That covers ZShare's own code. Treyarch's stock scripts are referenced here, not
included, and are not mine to license.
