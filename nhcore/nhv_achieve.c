/* nhv_achieve.c - achievements: what the hero does and reaches, reported
 * to the host as NHV_EV_ACHIEVE events. The host keeps the player's
 * achievements from game to game (the nhv mod's achievements.lua decides
 * which event unlocks which). Nothing is reported in debug (wizard) or
 * explore mode.
 *
 * Event text (fields separated by spaces; a name, last, may have spaces):
 *   nh <n>                 NetHack's own achievement n (ACH_*, you.h)
 *   kill <flags> <times> <monster>   you killed it (NHV_KILL_*; times:
 *                          how many of its kind have died, this one too)
 *   eat <monster>          you ate its corpse (or a tin of it)
 *   poly <flags>           you changed form (NHV_POLY_*)
 *   artifact <oname flags> an artifact was made for you (ONAME_*)
 *   end <how> <turns> <conducts> <role> <race> <alignment> <gender>
 *                          the game ended (how: DIED... ASCENDED; conducts:
 *                          NHV_CONDUCT_* kept)
 *   place <where>          you're there: quest_home, ludios, castle, valley,
 *                          wizard_tower
 *   depth <n> / ac <n>    (when they change)
 *   and, as they happen: snickersnee, wield_trice, quest_accepted,
 *   quest_artifact, castle_wand, wish, crowned, altar_converted, expert,
 *   sink_ring, creamed, shk_paid, stat_max, resist_all, dragon_pet
 */
#include "hack.h"
#include "nhv_internal.h"

/* hmon's kind of hit (HMON_*) while it's hitting, else -1 (uhitm.c) */
int nhv_hmon_kind = -1;
/* a boulder you dropped is killing (read.c) */
boolean nhv_boulder_kill = FALSE;

#define NHV_KILL_SHOPKEEPER 0x1
#define NHV_KILL_OWN_PRIEST 0x2  /* a priest of your own god */
#define NHV_KILL_BLIND      0x4  /* you were blind */
#define NHV_KILL_MELEE      0x20
#define NHV_KILL_POLEARM    0x40 /* a polearm's hit, from a distance */
#define NHV_KILL_FAR        0x80 /* something thrown or fired, 8+ squares */
#define NHV_KILL_BOULDER    0x100
#define NHV_KILL_NEMESIS    0x200 /* your quest's nemesis */

#define NHV_POLY_CONTROLLED 0x1
#define NHV_POLY_DRAGON     0x2 /* a grown dragon */
#define NHV_POLY_UNDEAD     0x4

#define NHV_CONDUCT_ATHEIST      0x1
#define NHV_CONDUCT_FOODLESS     0x2
#define NHV_CONDUCT_VEGAN        0x4
#define NHV_CONDUCT_VEGETARIAN   0x8
#define NHV_CONDUCT_WEAPONLESS   0x10
#define NHV_CONDUCT_PACIFIST     0x20
#define NHV_CONDUCT_ILLITERATE   0x40
#define NHV_CONDUCT_POLYPILELESS 0x80
#define NHV_CONDUCT_POLYSELFLESS 0x100
#define NHV_CONDUCT_WISHLESS     0x200
#define NHV_CONDUCT_ARTIWISHLESS 0x400
#define NHV_CONDUCT_GENOCIDELESS 0x800
#define NHV_CONDUCT_BLIND        0x1000
#define NHV_CONDUCT_NUDIST       0x2000
#define NHV_CONDUCT_SOKOBAN      0x4000 /* Sokoban done, by its rules */

void
nhv_achieve(const char *fmt, ...)
{
    char buf[256];
    va_list ap;

    if (wizard || discover)
        return;
    va_start(ap, fmt);
    (void) vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    nhv_push_event(NHV_EV_ACHIEVE, 0, buf);
}

static boolean
is_grown_dragon(int mndx)
{
    return (mndx >= PM_GRAY_DRAGON && mndx <= PM_YELLOW_DRAGON);
}

/* mon.c's xkilled: you killed mtmp (still where it was) */
void
nhv_achieve_kill(struct monst *mtmp)
{
    int flags = 0, mndx = monsndx(mtmp->data);

    if (mtmp->isshk)
        flags |= NHV_KILL_SHOPKEEPER;
    if (mtmp->ispriest && p_coaligned(mtmp))
        flags |= NHV_KILL_OWN_PRIEST;
    if (Blind)
        flags |= NHV_KILL_BLIND;
    if (nhv_hmon_kind == HMON_MELEE)
        flags |= NHV_KILL_MELEE;
    if (nhv_hmon_kind == HMON_APPLIED && uwep && is_pole(uwep))
        flags |= NHV_KILL_POLEARM;
    if (gt.thrownobj && distmin(u.ux, u.uy, mtmp->mx, mtmp->my) >= 8)
        flags |= NHV_KILL_FAR;
    if (nhv_boulder_kill)
        flags |= NHV_KILL_BOULDER;
    if (mtmp->data->msound == MS_NEMESIS)
        flags |= NHV_KILL_NEMESIS;
    nhv_achieve("kill %d %d %s", flags, svm.mvitals[mndx].died + 1,
                mtmp->data->pmnames[NEUTRAL]);
}

/* polyself.c's polymon: you became mntmp */
void
nhv_achieve_poly(int mntmp)
{
    int flags = 0;

    if (Polymorph_control)
        flags |= NHV_POLY_CONTROLLED;
    if (is_grown_dragon(mntmp))
        flags |= NHV_POLY_DRAGON;
    if (is_undead(&mons[mntmp]))
        flags |= NHV_POLY_UNDEAD;
    nhv_achieve("poly %d", flags);
}

static boolean
has_achievement(int ach)
{
    int i;

    for (i = 0; u.uachieved[i]; ++i)
        if (abs(u.uachieved[i]) == ach)
            return TRUE;
    return FALSE;
}

/* end.c's really_done: the game is over */
void
nhv_achieve_end(int how)
{
    int c = 0;
    struct u_conduct *k = &u.uconduct;

    if (!k->gnostic)
        c |= NHV_CONDUCT_ATHEIST;
    if (!k->food)
        c |= NHV_CONDUCT_FOODLESS;
    if (!k->unvegan)
        c |= NHV_CONDUCT_VEGAN;
    if (!k->unvegetarian)
        c |= NHV_CONDUCT_VEGETARIAN;
    if (!k->weaphit)
        c |= NHV_CONDUCT_WEAPONLESS;
    if (!k->killer)
        c |= NHV_CONDUCT_PACIFIST;
    if (!k->literate)
        c |= NHV_CONDUCT_ILLITERATE;
    if (!k->polypiles)
        c |= NHV_CONDUCT_POLYPILELESS;
    if (!k->polyselfs)
        c |= NHV_CONDUCT_POLYSELFLESS;
    if (!k->wishes)
        c |= NHV_CONDUCT_WISHLESS;
    if (!k->wisharti)
        c |= NHV_CONDUCT_ARTIWISHLESS;
    if (!num_genocides())
        c |= NHV_CONDUCT_GENOCIDELESS;
    if (u.uroleplay.blind)
        c |= NHV_CONDUCT_BLIND;
    if (u.uroleplay.nudist)
        c |= NHV_CONDUCT_NUDIST;
    if (!k->sokocheat && has_achievement(ACH_SOKO_PRIZE))
        c |= NHV_CONDUCT_SOKOBAN;
    nhv_achieve("end %d %ld %d %s %s %s %s", how, svm.moves, c,
                gu.urole.name.m, gu.urace.noun,
                aligns[1 - u.ualign.type].adj,
                flags.female ? "female" : "male");
}

static boolean
resists_all(void)
{
    return (Fire_resistance && Cold_resistance && Shock_resistance
            && Sleep_resistance && Poison_resistance
            && Disint_resistance);
}

static boolean
max_stat(void)
{
    int i;

    for (i = 0; i < A_MAX; i++)
        if (ACURR(i) >= ATTRMAX(i))
            return TRUE;
    return FALSE;
}

static boolean
dragon_pet(void)
{
    struct monst *mtmp;

    for (mtmp = fmon; mtmp; mtmp = mtmp->nmon)
        if (!DEADMONSTER(mtmp) && mtmp->mtame
            && is_grown_dragon(monsndx(mtmp->data)))
            return TRUE;
    return FALSE;
}

/* before each command (nhv_win.c): what you are, have and where you are
   now; each told when it changes (and all of it again for a new game, or
   one restored: NetHack's own achievements so far too) */
void
nhv_achieve_check(void)
{
    static long game = 0;
    static int depth_was, ac_was;
    static d_level at;
    static boolean once[4];
    boolean now[4];
    static const char *const once_names[4] = {
        "stat_max", "resist_all", "dragon_pet", "wizard_tower"
    };
    int i;

    if (wizard || discover)
        return;
    if (game != (long) ubirthday) {
        game = (long) ubirthday;
        depth_was = 0;
        ac_was = 999;
        at.dnum = at.dlevel = -1;
        for (i = 0; i < 4; i++)
            once[i] = FALSE;
        for (i = 0; u.uachieved[i]; ++i)
            nhv_achieve("nh %d", abs(u.uachieved[i]));
    }
    if (!on_level(&at, &u.uz)) {
        assign_level(&at, &u.uz);
        if (Is_qstart(&u.uz))
            nhv_achieve("place quest_home");
        else if (Is_knox(&u.uz))
            nhv_achieve("place ludios");
        else if (Is_stronghold(&u.uz))
            nhv_achieve("place castle");
        else if (Is_valley(&u.uz))
            nhv_achieve("place valley");
    }
    if (depth(&u.uz) != depth_was) {
        depth_was = depth(&u.uz);
        nhv_achieve("depth %d", depth_was);
    }
    if (u.uac != ac_was) {
        ac_was = u.uac;
        nhv_achieve("ac %d", ac_was);
    }
    now[0] = max_stat();
    now[1] = resists_all();
    now[2] = dragon_pet();
    now[3] = In_W_tower(u.ux, u.uy, &u.uz);
    for (i = 0; i < 4; i++)
        if (now[i] && !once[i]) {
            once[i] = TRUE;
            nhv_achieve(i == 3 ? "place %s" : "%s", once_names[i]);
        }
}

/*nhv_achieve.c*/
