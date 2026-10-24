/* nhv_free.c - free (continuous) movement support.
 *
 * The host owns where monsters and the hero physically are. Each server
 * step it tells us which monsters can reach the hero in melee (and what
 * a pet wants to fight); NetHack's own turn logic then uses that instead
 * of grid adjacency. See include/nhvhooks.h in the NetHack tree.
 */
#include "hack.h"
#include "nhv_internal.h"

extern glyph_map glyphmap[MAX_GLYPH];

boolean nhv_freemove = FALSE;
boolean nhv_walking = FALSE; /* (see nhvhooks.h) */

#define MAXSTATES 512
static nhv_monstate states[MAXSTATES];
static int nstates;

/* arguments of the #nhv* extended command being run */
char nhv_cmd_text[256];
int nhv_cmd_args[NHV_MAXARGS];

static const nhv_monstate *
state_of(struct monst *mtmp)
{
    int i;

    for (i = 0; i < nstates; i++)
        if (states[i].id == mtmp->m_id)
            return &states[i];
    return (const nhv_monstate *) 0;
}

int
nhv_mon_in_reach(struct monst *mtmp)
{
    const nhv_monstate *s = state_of(mtmp);

    return s ? s->in_reach : -1;
}

struct monst *
nhv_mon_melee_target(struct monst *mtmp)
{
    const nhv_monstate *s = state_of(mtmp);
    struct monst *m;

    if (!s || !s->melee_target)
        return (struct monst *) 0;
    for (m = fmon; m; m = m->nmon)
        if (m->m_id == s->melee_target && !DEADMONSTER(m))
            return m;
    return (struct monst *) 0;
}

boolean
nhv_grid_mover(struct monst *mtmp)
{
    return (mtmp->isshk || mtmp->isgd || mtmp->ispriest || mtmp->wormno
            || mtmp == u.ustuck
#ifdef MAIL_STRUCTURES
            || mtmp->data == &mons[PM_MAIL_DAEMON]
#endif
            );
}

static struct monst *
mon_by_id(unsigned id)
{
    struct monst *m;

    for (m = fmon; m; m = m->nmon)
        if (m->m_id == id && !DEADMONSTER(m) && m->mx > 0)
            return m;
    return (struct monst *) 0;
}

/* ---------------------------------------------------------------- commands */

/* What the host's commands (which take no time: the clock is the host's)
   return. Unless they've left you helpless - a sleeping gas trap, a sleep
   ray, a floating eye's gaze: then they took your turn, as in NetHack (a
   command taking no time has helplessness undone afterwards, by rhack()). */
static int
nhv_ok(void)
{
    return (gm.multi < 0) ? ECMD_TIME : ECMD_OK;
}

/* Punished: the ball and chain are kept under the hero (in 3D the ball
   trails right behind you, drawn by the host), so walking never drags
   them a square behind nor is held back by them. */
static void
nhv_bc_follow(void)
{
    if (!Punished || !uball || !uchain || u.uswallow || carried(uball)
        || uball->where != OBJ_FLOOR || uchain->where != OBJ_FLOOR)
        return;
    if (u_at(uball->ox, uball->oy) && u_at(uchain->ox, uchain->oy))
        return;
    unplacebc();
    placebc();
}

/* #nhvmove x y [share]: the hero's body entered square <x,y>; move there
   without using time (time passes separately through ticks).

   Someone there you can see: in 3D you walk in among them - the hero and
   a monster share the square (as a monster may come into yours) - rather
   than NetHack refusing the step. Not a pet (you swap places with it, as
   in NetHack) unless share is given (it wouldn't swap), and not a
   shopkeeper: it stands in its shop's door to bar the way out.
   Someone you can't see is bumped into as NetHack does (a hider is found,
   a mimic sticks to you). */
int
donhvmove(void)
{
    int x = nhv_cmd_args[0], y = nhv_cmd_args[1];
    int dx = x - u.ux, dy = y - u.uy;
    struct monst *mtmp;

    if (!isok(x, y) || (!dx && !dy) || abs(dx) > 1 || abs(dy) > 1)
        return nhv_ok();
    mtmp = m_at(x, y);
    /* someone there: the body walks in among them (squares are shared). One
       you can't see (invisible, you're blind...) too: NetHack would stop
       you there ("Wait!  There's something there you can't see!") and the
       host would put your body back on your square, again and again, with
       it in the way - you'd be held next to it. You're told, as in
       NetHack, and go on. (A mimic in disguise still stops you.) */
    if (mtmp && !M_AP_TYPE(mtmp)
        && (!canspotmon(mtmp) || !mtmp->mtame || nhv_cmd_args[2])
        && !mtmp->isshk
        && !u.ustuck && !u.utrap && !u.uswallow && !u.usteed
        && test_move(u.ux, u.uy, dx, dy, TEST_MOVE)) {
        if (!canspotmon(mtmp) && !glyph_is_invisible(levl[x][y].glyph)) {
            Norep("Wait!  There's something there you can't see!");
            map_invisible(x, y);
        }
        nhv_walking = TRUE;
        teleds(x, y, TELEDS_ALLOW_DRAG);
        nhv_walking = FALSE;
        nhv_bc_follow();
        return nhv_ok();
    }
    u.dx = dx, u.dy = dy, u.dz = 0;
    /* walking never fights (the no-fighting flag, as NetHack's 'm' prefix,
       when someone is there); it may swap places with a pet. With nobody
       there it's an ordinary step: autopickup picks things up, a boulder
       is pushed */
    svc.context.nopick = mtmp
                         && !(mtmp->mtame && canspotmon(mtmp)
                              /* (confused or stunned, NetHack would attack
                                 the pet instead of swapping: just bump) */
                              && !Stunned && !Confusion);
    svc.context.forcefight = 0;
    nhv_walking = TRUE;
    domove();
    nhv_walking = FALSE;
    svc.context.nopick = 0;
    nhv_bc_follow();
    return nhv_ok();
}

/* #nhvtrap x y: the hero's body touched the trap on its square <x,y> (its
   hitbox, in the middle of the square): it goes off as stepping on it
   does. No time passes (the walk's time is the clock's). */
int
donhvtrap(void)
{
    int x = nhv_cmd_args[0], y = nhv_cmd_args[1];
    struct trap *trap;

    if (!isok(x, y) || !u_at(x, y) || u.uswallow
        || !(trap = t_at(x, y)))
        return nhv_ok();
    dotrap(trap, 0);
    return nhv_ok();
}

/* #nhvpass x y: the hero's body walked past a monster (in NetHack two
   can't share a square, but in 3D you walk by them): move two squares at
   once, over the occupied one, when each of the two steps is a move NetHack
   would allow but for whoever is in the way (walls, doors, squeezing past
   corners all still count). Takes no time, like #nhvmove; traps, autopickup
   and the like happen where you arrive. */
int
donhvpass(void)
{
    int x = nhv_cmd_args[0], y = nhv_cmd_args[1];
    int dx = x - u.ux, dy = y - u.uy;
    coordxy mx, my;

    /* #nhvpass x1 y1 x2 y2 ... xn yn: the whole way, one square at a time,
       past a line of monsters (a crowded corridor): every square but the
       last has someone in it, the last is free, and each step is a move
       NetHack would allow but for who's there */
    if (nhv_cmd_args[2] && !u.ustuck && !u.utrap && !u.uswallow) {
        int k, n = 0;
        coordxy px = u.ux, py = u.uy;

        while (n < NHV_MAXARGS / 2 && nhv_cmd_args[2 * n])
            n++;
        for (k = 0; k < n; k++) {
            coordxy sx = nhv_cmd_args[2 * k], sy = nhv_cmd_args[2 * k + 1];
            boolean last = (k == n - 1);

            if (!isok(sx, sy) || abs(sx - px) > 1 || abs(sy - py) > 1
                || (sx == px && sy == py)
                || (last ? m_at(sx, sy) != 0 : m_at(sx, sy) == 0)
                || !test_move(px, py, sx - px, sy - py, TEST_MOVE))
                return nhv_ok();
            px = sx, py = sy;
        }
        if (n >= 2) {
            nhv_walking = TRUE;
            teleds(px, py, TELEDS_ALLOW_DRAG);
            nhv_walking = FALSE;
            nhv_bc_follow();
        }
        return nhv_ok();
    }
    if (!isok(x, y) || max(abs(dx), abs(dy)) != 2 || m_at(x, y) || u.ustuck
        || u.utrap || u.uswallow)
        return nhv_ok();
    for (mx = u.ux - 1; mx <= u.ux + 1; mx++)
        for (my = u.uy - 1; my <= u.uy + 1; my++) {
            if (!isok(mx, my) || u_at(mx, my) || abs(x - mx) > 1
                || abs(y - my) > 1 || !m_at(mx, my))
                continue; /* (only to get past someone) */
            if (test_move(u.ux, u.uy, mx - u.ux, my - u.uy, TEST_MOVE)
                && test_move(mx, my, x - mx, y - my, TEST_MOVE)) {
                nhv_walking = TRUE;
                teleds(x, y, TELEDS_ALLOW_DRAG);
                nhv_walking = FALSE;
                nhv_bc_follow();
                return nhv_ok();
            }
        }
    return nhv_ok();
}

/* #nhvpit 1|0: the hero's body is down in the pit on its square, or came
   back up. Down there the bottom can be reached (picking things up...)
   without being trapped; climbing out is the host's. No time passes. */
boolean nhv_in_pit = FALSE;

/* #nhvgod 0|1: wizard mode's invulnerability, on while the host's noclip
   is: monsters don't attack, hit points aren't lost, and death is turned
   away (as answering no to wizard mode's "Die?") */
boolean nhv_godmode = FALSE;

int
donhvgod(void)
{
    nhv_godmode = wizard && nhv_cmd_args[0] != 0;
    return nhv_ok();
}

int
donhvpit(void)
{
    nhv_in_pit = nhv_cmd_args[0] != 0;
    return nhv_ok();
}

/* #nhvgoto dnum dlevel: straight to that level (debug mode only; the
   level atlas visits every level this way). No time passes. */
int
donhvgoto(void)
{
    d_level lev;

    if (!wizard)
        return nhv_ok();
    lev.dnum = (xint16) nhv_cmd_args[0];
    lev.dlevel = (xint16) nhv_cmd_args[1];
    if (lev.dnum < 0 || lev.dnum >= svn.n_dgns || lev.dlevel < 1
        || lev.dlevel > svd.dungeons[lev.dnum].num_dunlevs)
        return nhv_ok();
    schedule_goto(&lev, UTOTYPE_NONE, (char *) 0, (char *) 0);
    deferred_goto();
    return nhv_ok();
}

/* #nhvtick: one hero action's worth of time passes. */
int
donhvtick(void)
{
    return ECMD_TIME;
}

/* #nhvpole id: hit a monster further away with the wielded polearm or
   lance, as applying it does (the host judged the reach; NetHack checks
   that you can see the spot, ...). Snickersnee's distance hit is free but
   once a turn: when it's been used this turn, the click swings instead,
   letting the turn pass (the next one hits again) - not "The blade doesn't
   reach there!" over and over with time standing still. */
coordxy nhv_pole_x, nhv_pole_y;
boolean nhv_pole_host = FALSE;

int
donhvpole(void)
{
    struct monst *mtmp = mon_by_id((unsigned) nhv_cmd_args[0]);

    if (!mtmp || !uwep || !is_pole(uwep))
        return nhv_ok();
    if (u_wield_art(ART_SNICKERSNEE)
        && svc.context.snickersnee_turn == svm.moves) {
        nhv_combat_event("uswing", 0, mtmp->m_id, 1);
        return ECMD_TIME;
    }
    nhv_pole_x = mtmp->mx, nhv_pole_y = mtmp->my;
    return use_pole(uwep, TRUE);
}

/* #nhvattack id: melee a monster the host says is within reach. */
int
donhvattack(void)
{
    struct monst *mtmp = mon_by_id((unsigned) nhv_cmd_args[0]);
    int dx, dy;

    if (!mtmp)
        return nhv_ok();
    dx = sgn(mtmp->mx - u.ux), dy = sgn(mtmp->my - u.uy);
    if (!dx && !dy)
        dx = 1;
    u.dx = dx, u.dy = dy, u.dz = 0;
    svc.context.forcefight = 1;
    (void) do_attack(mtmp);
    svc.context.forcefight = 0;
    return ECMD_TIME;
}

/* #nhvchat id: chat with that monster - the one the player points at - as
   #chat would, without asking for a direction: in free movement its square
   isn't always next to yours, though it's in front of you (the host only
   offers it within talking distance) */
struct monst *nhv_chat_mon = (struct monst *) 0;

int
donhvchat(void)
{
    struct monst *mtmp = mon_by_id((unsigned) nhv_cmd_args[0]);
    int res;

    if (!mtmp)
        return nhv_ok();
    nhv_chat_mon = mtmp;
    res = dotalk();
    nhv_chat_mon = (struct monst *) 0;
    return res;
}

/* #nhvjump x y: jump to that square (the one the player picked in 3D) -
   NetHack's #jump, with every check it makes, aimed there instead of
   asking where */
coordxy nhv_jump_x = -1, nhv_jump_y = -1;

int
donhvjump(void)
{
    int res;

    nhv_jump_x = (coordxy) nhv_cmd_args[0];
    nhv_jump_y = (coordxy) nhv_cmd_args[1];
    res = dojump();
    nhv_jump_x = nhv_jump_y = -1;
    return res;
}

/* ---------------------------------------------------------------- API */
NHV_API void
nhv_set_freemove(int on)
{
    nhv_freemove = on ? TRUE : FALSE;
}

NHV_API void
nhv_set_monstates(const nhv_monstate *s, int n)
{
    if (n > MAXSTATES)
        n = MAXSTATES;
    if (n < 0)
        n = 0;
    memcpy(states, s, sizeof *s * (size_t) n);
    nstates = n;
}

static int
mon_speed(struct monst *mtmp)
{
    int mmove = mtmp->data->mmove;

    if (mtmp->mspeed == MSLOW)
        mmove = (2 * mmove + 1) / 3;
    else if (mtmp->mspeed == MFAST)
        mmove = (4 * mmove + 2) / 3;
    return mmove;
}

NHV_API int
nhv_get_all_monsters(nhv_monfull *buf, int max)
{
    struct monst *m;
    int n = 0;

    if (!(nhv_state() == NHV_WAITING || nhv_state() == NHV_ENDED)
        || !program_state.in_moveloop)
        return 0;
    for (m = fmon; m; m = m->nmon) {
        nhv_monfull f;

        if (DEADMONSTER(m) || m->mx <= 0 || m == u.usteed)
            continue;
        memset(&f, 0, sizeof f);
        f.id = m->m_id;
        f.x = m->mx, f.y = m->my;
        f.mndx = monsndx(m->data);
        f.speed = mon_speed(m);
        f.size = m->data->msize;
        f.mux = m->mux, f.muy = m->muy;
        f.hp = m->mhp, f.hpmax = m->mhpmax;
        if (m->mtame)
            f.flags |= NHV_MF_TAME;
        if (m->mpeaceful)
            f.flags |= NHV_MF_PEACEFUL;
        if (m->mflee)
            f.flags |= NHV_MF_FLEE;
        if (m->mcanmove && !m->msleeping && !m->mtrapped && !m->meating
            && !(m->mstrategy & STRAT_WAITMASK))
            f.flags |= NHV_MF_CANMOVE;
        if (m_canseeu(m))
            f.flags |= NHV_MF_SEES_U;
        if (nhv_grid_mover(m))
            f.flags |= NHV_MF_GRID;
        if (canspotmon(m))
            f.flags |= NHV_MF_VISIBLE;
        if (m->mconf || m->mstun)
            f.flags |= NHV_MF_CONFUSED;
        if (is_hider(m->data) || hides_under(m->data))
            f.flags |= NHV_MF_HIDER;
        if (m->mundetected)
            f.flags |= NHV_MF_HIDDEN;
        if (!m->mpeaceful && nhv_mon_keeps_distance(m))
            f.flags |= NHV_MF_KEEPAWAY;
        if (m->msleeping)
            f.flags |= NHV_MF_ASLEEP;
        if (n < max)
            buf[n] = f;
        n++;
    }
    return n;
}

/* ---------------------------------------------------------------- missiles
 * Missiles monsters throw at the hero are kept here (as free objects)
 * while the host flies them through the world. */
#define MAXMISSILES 64
static struct nhv_flying {
    unsigned pid;
    struct obj *obj;
    unsigned mon_id;
    coordxy lx, ly;     /* launch square */
    int range;
    boolean fresh;      /* not yet reported to the host */
} missiles[MAXMISSILES];
static unsigned next_pid = 1;

void
nhv_missile_launch(
    struct monst *mon, struct obj *obj, coordxy x, coordxy y, int range)
{
    int i;

    for (i = 0; i < MAXMISSILES; i++)
        if (!missiles[i].obj) {
            missiles[i].pid = next_pid++;
            missiles[i].obj = obj;
            missiles[i].mon_id = mon ? mon->m_id : 0;
            missiles[i].lx = x, missiles[i].ly = y;
            missiles[i].range = range;
            missiles[i].fresh = TRUE;
            return;
        }
    /* no room: it just drops where it was thrown from */
    nhv_missile_lands(obj, x, y);
}

static struct nhv_flying *
missile_by_pid(unsigned pid)
{
    int i;

    for (i = 0; i < MAXMISSILES; i++)
        if (missiles[i].obj && missiles[i].pid == pid)
            return &missiles[i];
    return (struct nhv_flying *) 0;
}

static void
missile_event(const char *what, unsigned pid)
{
    char buf[64];

    Sprintf(buf, "%s %u", what, pid);
    nhv_push_event(NHV_EV_MISSILE, 0, buf);
}

/* A monster's missile or ray that flies in 3D lands later, in one of the
   commands below - which run as the hero's commands, so NetHack would
   take whatever it does for the hero's doing (svc.context.mon_moving off):
   a monster's arrow killing a watchman would be the hero's murder ("You
   murderer!", the watch angry), a potion it threw breaking in a shop
   charged to the hero. While one lands, a monster is acting, as when
   NetHack's monsters throw in their own turn. */
static boolean nhv_saved_mon_moving;

static void
monster_acting(boolean on)
{
    if (on) {
        nhv_saved_mon_moving = svc.context.mon_moving;
        svc.context.mon_moving = TRUE;
    } else {
        svc.context.mon_moving = nhv_saved_mon_moving;
    }
}

/* #nhvmhit pid: the missile reached the hero's body */
int
donhvmhit(void)
{
    struct nhv_flying *f = missile_by_pid((unsigned) nhv_cmd_args[0]);
    int r;

    if (!f)
        return nhv_ok();
    monster_acting(TRUE);
    r = nhv_missile_hits_hero(mon_by_id(f->mon_id), f->obj, f->lx, f->ly);
    monster_acting(FALSE);
    if (r == 0) {
        missile_event("miss", f->pid); /* dodged: it flies on */
    } else {
        missile_event(r == 1 ? "hit" : "stop", f->pid);
        f->obj = 0;
    }
    return nhv_ok();
}

/* #nhvmhitm pid m_id: the missile reached a monster's body */
int
donhvmhitm(void)
{
    struct nhv_flying *f = missile_by_pid((unsigned) nhv_cmd_args[0]);
    struct monst *m = mon_by_id((unsigned) nhv_cmd_args[1]);

    if (!f)
        return nhv_ok();
    monster_acting(TRUE);
    if (m && nhv_missile_hits_mon(m, f->obj, f->range)) {
        missile_event("stop", f->pid);
        f->obj = 0;
    } else {
        missile_event("pass", f->pid);
    }
    monster_acting(FALSE);
    return nhv_ok();
}

/* #nhvmland pid x y: the missile came down on square <x,y> */
int
donhvmland(void)
{
    struct nhv_flying *f = missile_by_pid((unsigned) nhv_cmd_args[0]);
    coordxy x = (coordxy) nhv_cmd_args[1], y = (coordxy) nhv_cmd_args[2];

    if (!f)
        return nhv_ok();
    if (!isok(x, y))
        x = f->lx, y = f->ly;
    monster_acting(TRUE);
    nhv_missile_lands(f->obj, x, y);
    monster_acting(FALSE);
    f->obj = 0;
    missile_event("land", f->pid);
    return nhv_ok();
}

NHV_API int
nhv_get_missiles(nhv_missile *buf, int max)
{
    int i, n = 0;

    if (nhv_state() != NHV_WAITING)
        return 0;
    for (i = 0; i < MAXMISSILES && n < max; i++) {
        struct nhv_flying *f = &missiles[i];

        if (!f->obj || !f->fresh)
            continue;
        f->fresh = FALSE;
        memset(&buf[n], 0, sizeof buf[n]);
        buf[n].pid = f->pid;
        buf[n].mon_id = f->mon_id;
        buf[n].x = f->lx, buf[n].y = f->ly;
        buf[n].range = f->range;
        buf[n].otyp = f->obj->otyp;
        buf[n].glyph = obj_to_glyph(f->obj, rn2_on_display_rng);
        buf[n].tile = glyphmap[buf[n].glyph].tileidx;
        n++;
    }
    return n;
}

NHV_API int
nhv_get_lights(nhv_light *buf, int max)
{
    light_source *ls;
    int n = 0;
    coordxy x, y;

    if (nhv_state() != NHV_WAITING)
        return 0;
    for (ls = gl.light_base; ls && n < max; ls = ls->next) {
        if (ls->range <= 0)
            continue; /* (a camera flash) */
        if (ls->type == LS_OBJECT) {
            if (!get_obj_location(ls->id.a_obj, &x, &y, 0))
                continue;
        } else if (ls->type == LS_MONSTER) {
            if (!get_mon_location(ls->id.a_monst, &x, &y, 0))
                continue;
        } else
            continue;
        buf[n].x = x, buf[n].y = y;
        buf[n].range = ls->range;
        buf[n].at_hero = u_at(x, y) ? 1 : 0;
        n++;
    }
    return n;
}

NHV_API int
nhv_get_ball(int *bx, int *by, int *cx, int *cy, int *tile,
             unsigned *ball_id, unsigned *chain_id)
{
    if (nhv_state() != NHV_WAITING || !Punished || !uball || !uchain)
        return 0;
    *ball_id = uball->o_id, *chain_id = uchain->o_id;
    *tile = glyphmap[obj_to_glyph(uball, rn2_on_display_rng)].tileidx;
    *cx = uchain->ox, *cy = uchain->oy;
    if (carried(uball)) {
        *bx = u.ux, *by = u.uy;
        return 2;
    }
    *bx = uball->ox, *by = uball->oy;
    return 1;
}

/* forget missiles still in flight (e.g. after a level change) */
NHV_API void
nhv_clear_missiles(void)
{
    int i;

    if (nhv_state() != NHV_WAITING)
        return;
    for (i = 0; i < MAXMISSILES; i++)
        if (missiles[i].obj) {
            obfree(missiles[i].obj, (struct obj *) 0);
            missiles[i].obj = 0;
        }
}

/* ---------------------------------------------------------------- rays
 * Rays (wands, spells, breath) handed over by dobuzz(); the host flies
 * and bounces them and reports what they reach. */
#define MAXRAYS 32
static struct nhv_rayrec {
    unsigned rid;
    int type, nd;
    coordxy sx, sy;
    int dx, dy, range;
    boolean sayhit, saymiss, forcemiss, shopdamage, fresh, used;
    unsigned caster;
} rays[MAXRAYS];
static unsigned next_rid = 1;

void
nhv_ray_launch(int type, int nd, coordxy sx, coordxy sy, int dx, int dy,
               int range, boolean sayhit, boolean saymiss, boolean forcemiss,
               unsigned caster)
{
    int i;

    for (i = 0; i < MAXRAYS; i++)
        if (!rays[i].used) {
            struct nhv_rayrec *r = &rays[i];

            memset(r, 0, sizeof *r);
            r->rid = next_rid++;
            r->type = type, r->nd = nd;
            r->sx = sx, r->sy = sy, r->dx = dx, r->dy = dy;
            r->range = range;
            r->sayhit = sayhit, r->saymiss = saymiss, r->forcemiss = forcemiss;
            r->caster = caster;
            r->fresh = r->used = TRUE;
            return;
        }
}

static struct nhv_rayrec *
ray_by_rid(unsigned rid)
{
    int i;

    for (i = 0; i < MAXRAYS; i++)
        if (rays[i].used && rays[i].rid == rid)
            return &rays[i];
    return (struct nhv_rayrec *) 0;
}

static void
ray_event(const char *what, unsigned rid)
{
    char buf[64];

    Sprintf(buf, "%s %u", what, rid);
    nhv_push_event(NHV_EV_RAY, 0, buf);
}

/* #nhvrayhit rid m_id: the ray reached a body (m_id 0 = the hero) */
int
donhvrayhit(void)
{
    struct nhv_rayrec *r = ray_by_rid((unsigned) nhv_cmd_args[0]);
    unsigned mid = (unsigned) nhv_cmd_args[1];
    int res;

    if (!r)
        return nhv_ok();
    if (r->type < 0)
        monster_acting(TRUE);
    if (mid == 0) {
        res = nhv_ray_hits_hero(r->type, r->nd, r->dx, r->dy, r->forcemiss);
    } else {
        struct monst *m = mon_by_id(mid);

        res = m ? nhv_ray_hits_mon(r->type, r->nd, m, r->forcemiss,
                                   r->sayhit, r->saymiss)
                : 0;
    }
    if (r->type < 0)
        monster_acting(FALSE);
    ray_event(res == 2 ? "reflect" : res == 3 ? "stop" : res == 1 ? "hit"
                                                                  : "miss",
              r->rid);
    return nhv_ok();
}

/* #nhvraysq rid x y [x y ...]: the ray crossed these squares */
int
donhvraysq(void)
{
    struct nhv_rayrec *r = ray_by_rid((unsigned) nhv_cmd_args[0]);
    int k;

    if (!r)
        return nhv_ok();
    if (r->type < 0)
        monster_acting(TRUE);
    for (k = 1; k + 1 < NHV_MAXARGS; k += 2) {
        if (!nhv_cmd_args[k] && !nhv_cmd_args[k + 1])
            break;
        nhv_ray_square(r->type, (coordxy) nhv_cmd_args[k],
                       (coordxy) nhv_cmd_args[k + 1], &r->shopdamage);
    }
    if (r->type < 0)
        monster_acting(FALSE);
    return nhv_ok();
}

/* #nhvrayend rid x y: the ray is spent at <x,y> */
int
donhvrayend(void)
{
    struct nhv_rayrec *r = ray_by_rid((unsigned) nhv_cmd_args[0]);

    if (!r)
        return nhv_ok();
    if (r->type < 0)
        monster_acting(TRUE);
    nhv_ray_end(r->type, (coordxy) nhv_cmd_args[1], (coordxy) nhv_cmd_args[2],
                r->shopdamage);
    if (r->type < 0)
        monster_acting(FALSE);
    r->used = FALSE;
    return nhv_ok();
}

NHV_API int
nhv_get_rays(nhv_ray *buf, int max)
{
    int i, n = 0;

    if (nhv_state() != NHV_WAITING)
        return 0;
    for (i = 0; i < MAXRAYS && n < max; i++) {
        struct nhv_rayrec *r = &rays[i];

        if (!r->used || !r->fresh)
            continue;
        r->fresh = FALSE;
        memset(&buf[n], 0, sizeof buf[n]);
        buf[n].rid = r->rid;
        buf[n].type = r->type;
        buf[n].kind = abs(r->type) % 10;
        buf[n].x = r->sx, buf[n].y = r->sy;
        buf[n].dx = r->dx, buf[n].dy = r->dy;
        buf[n].range = r->range;
        buf[n].from_hero = r->type >= 0 && r->type < 20; /* 20+: breath */
        buf[n].caster = r->caster;
        n++;
    }
    return n;
}

NHV_API void
nhv_clear_rays(void)
{
    int i;

    for (i = 0; i < MAXRAYS; i++)
        rays[i].used = FALSE;
}

/* #nhvhurt <hp> <cause>: a block hurt the hero (spikes, ...); the cause is
   what the death message says ("killed by <cause>") */
int
donhvhurt(void)
{
    static char why[128];
    int dmg = nhv_cmd_args[0];
    const char *p = strchr(nhv_cmd_text, ' ');

    Snprintf(why, sizeof why, "%s", (p && p[1]) ? p + 1 : "something sharp");
    if (dmg > 0) {
        You("are hurt by %s!", why);
        losehp(Maybe_Half_Phys(dmg), why, KILLED_BY);
    }
    return nhv_ok();
}

/* #nhvopt <option>: set a NetHack option, as a config file line or the
   'O' menu would ("fruit:apple", "!autopickup", "pickup_burden:burdened");
   the game's NetHack options page uses it. Takes no time. */
int
donhvopt(void)
{
    char buf[BUFSZ];

    Snprintf(buf, sizeof buf, "%s", nhv_cmd_text);
    /* (pickup_burden is only accepted the way the start-up options are) */
    if (*buf)
        (void) parseoptions(buf, !strncmpi(buf, "pickup_burden", 13), FALSE);
    return nhv_ok();
}

/* #nhvspike <damage> [cause]: you stepped into iron spikes (a spike
   block). Like a spiked pit's: iron boots protect you, and 1 time in 6
   they're poisoned. */
int
donhvspike(void)
{
    static char why[128];
    int dmg = nhv_cmd_args[0], oldumort = u.umortality;
    const char *p = strchr(nhv_cmd_text, ' ');

    Snprintf(why, sizeof why, "%s", (p && p[1]) ? p + 1 : "sharp iron spikes");
    if (wearing_iron_shoes(&gy.youmonst)) {
        pline("%s protects you from the sharp iron spikes.", Yname2(uarmf));
        return nhv_ok();
    }
    if (dmg <= 0)
        return nhv_ok();
    You("step on %s!", why);
    losehp(Maybe_Half_Phys(dmg), why, KILLED_BY);
    if (!rn2(6))
        poisoned("spikes", A_STR, "stepping on poison spikes",
                 /* if the damage triggered life-saving, poison is
                    limited to attribute loss (as in a spiked pit) */
                 (u.umortality > oldumort) ? 0 : 8, FALSE);
    return nhv_ok();
}

void
nhv_container_event(const char *kind, unsigned id)
{
    char buf[64];

    Sprintf(buf, "%s %u", kind, id);
    nhv_push_event(NHV_EV_CONTAINER, 0, buf);
}

coordxy nhv_beam_x, nhv_beam_y;

/* ---------------------------------------------------------------- special levels
 * While a special level's file builds it, its fixed regions (drawn maps,
 * rooms with a fixed place and size) are noted; when it's done they're
 * reported to the host (NHV_EV_SPLEV), or with #nhvsplevdump written out
 * with their terrain as templates for the area prefab editor. */
#define MAXSPREG 16
static struct {
    boolean active;
    char proto[32];
    int n;
    struct {
        int x, y, w, h;
    } r[MAXSPREG];
    int flip, minx, miny, maxx, maxy; /* flip_level's, once built */
} splev;
static FILE *splev_out; /* #nhvsplevdump: templates go here */

void
nhv_splev_begin(const char *protofile)
{
    char *dot;

    splev.active = TRUE;
    splev.n = 0;
    splev.flip = 0;
    Snprintf(splev.proto, sizeof splev.proto, "%s", protofile);
    if ((dot = strrchr(splev.proto, '.')) != 0)
        *dot = '\0'; /* ("minetn-3.lua" -> "minetn-3") */
}

/* the level was flipped (top/bottom: flp & 1, left/right: flp & 2) within
   minx..maxx, miny..maxy: the regions, as the level file placed them, are
   reported with it so the host can find them where they are now */
void
nhv_splev_flip(int flp, int minx, int miny, int maxx, int maxy)
{
    if (!splev.active)
        return;
    splev.flip = flp & 3;
    splev.minx = minx, splev.miny = miny;
    splev.maxx = maxx, splev.maxy = maxy;
}

void
nhv_splev_region(int x, int y, int w, int h)
{
    int i;

    if (!splev.active || splev.n >= MAXSPREG)
        return;
    if (x < 1)
        w -= 1 - x, x = 1;
    if (y < 0)
        h += y, y = 0;
    if (x + w > COLNO)
        w = COLNO - x;
    if (y + h > ROWNO)
        h = ROWNO - y;
    if (w <= 0 || h <= 0)
        return;
    for (i = 0; i < splev.n; i++) /* (the same one twice: once) */
        if (splev.r[i].x == x && splev.r[i].y == y && splev.r[i].w == w
            && splev.r[i].h == h)
            return;
    splev.r[splev.n].x = x, splev.r[splev.n].y = y;
    splev.r[splev.n].w = w, splev.r[splev.n].h = h;
    splev.n++;
}

void
nhv_splev_end(void)
{
    char buf[128];
    int i, x, y;

    if (!splev.active)
        return;
    splev.active = FALSE;
    for (i = 0; i < splev.n; i++) {
        if (splev_out) {
            /* "<proto> <n> <x> <y> <w> <h> <terrain>", the terrain types
               row by row as characters ('0' + type) */
            fprintf(splev_out, "%s %d %d %d %d %d ", splev.proto, i + 1,
                    splev.r[i].x, splev.r[i].y, splev.r[i].w, splev.r[i].h);
            for (y = splev.r[i].y; y < splev.r[i].y + splev.r[i].h; y++)
                for (x = splev.r[i].x; x < splev.r[i].x + splev.r[i].w; x++) {
                    /* (where that square went if the level was flipped) */
                    int fx = (splev.flip & 2) ? splev.maxx - x + splev.minx : x,
                        fy = (splev.flip & 1) ? splev.maxy - y + splev.miny : y;

                    fputc('0' + levl[fx][fy].typ, splev_out);
                }
            fputc('\n', splev_out);
        } else {
            /* "... <flip> <minx> <miny> <maxx> <maxy>": how it was flipped */
            Snprintf(buf, sizeof buf, "%ld %d %s %d %d %d %d %d %d %d %d %d %d",
                     (long) ubirthday, (int) ledger_no(&u.uz), splev.proto,
                     i + 1, splev.r[i].x, splev.r[i].y, splev.r[i].w,
                     splev.r[i].h, splev.flip, splev.minx, splev.miny,
                     splev.maxx, splev.maxy);
            nhv_push_event(NHV_EV_SPLEV, 0, buf);
        }
    }
    /* a special level with no fixed regions (a filler, the Planes of Air
       and Water...): still says which level it is, as region 0 */
    if (!splev.n && !splev_out) {
        Snprintf(buf, sizeof buf, "%ld %d %s 0 0 0 0 0", (long) ubirthday,
                 (int) ledger_no(&u.uz), splev.proto);
        nhv_push_event(NHV_EV_SPLEV, 0, buf);
    }
}

/* #nhvsplevdump (wizard mode; a throwaway game): build every variant of
   every special level in turn and write their fixed regions to
   splev_templates.txt (tools/make_splev_templates.py runs this) */
int
donhvsplevdump(void)
{
    static char envbuf[64];
    s_level *sp;
    d_level here = u.uz;
    int v, nv, count = 0;

    if (!wizard)
        return nhv_ok();
    if (!(splev_out = fopen("splev_templates.txt", "w"))) {
        pline("Can't write splev_templates.txt.");
        return nhv_ok();
    }
    for (sp = svs.sp_levchn; sp; sp = sp->next) {
        /* (the Planes of Air and Water move around: nothing fixed) */
        if (!strcmp(sp->proto, "air") || !strcmp(sp->proto, "water")
            || !strcmp(sp->proto, "dummy")) /* (a placeholder, no file) */
            continue;
        nv = sp->rndlevs ? sp->rndlevs : 1;
        for (v = 1; v <= nv; v++) {
            Snprintf(envbuf, sizeof envbuf, "SPLEVTYPE=%s-%d", sp->proto, v);
            putenv(envbuf);
            makemap_prepost(TRUE, FALSE);
            u.uz = sp->dlevel;
            mklev();
            makemap_prepost(FALSE, FALSE);
            count++;
        }
    }
    Strcpy(envbuf, "SPLEVTYPE=");
    putenv(envbuf);
    fclose(splev_out);
    splev_out = 0;
    /* back to a fresh copy of where we started */
    makemap_prepost(TRUE, FALSE);
    u.uz = here;
    mklev();
    makemap_prepost(FALSE, FALSE);
    pline("Wrote %d special levels to splev_templates.txt.", count);
    return nhv_ok();
}

/* ---------------------------------------------------------------- aim */
static struct {
    int dx, dy; /* thousandths of a square; 0,0 = none */
    int ttl;    /* commands left (rhack calls) */
} aim;

/* #nhvaim dx dy: the next command aims along this line */
int
donhvaim(void)
{
    aim.dx = nhv_cmd_args[0], aim.dy = nhv_cmd_args[1];
    aim.ttl = 2; /* (this command, then the one it's for) */
    return nhv_ok();
}

void
nhv_aim_tick(void)
{
    if (aim.ttl > 0 && --aim.ttl == 0)
        aim.dx = aim.dy = 0;
}

/* The squares along the aimed line from <x0,y0> (not included), up to max
   of them; 0 if there's no aim, or it doesn't go the way ddx,ddy does (a
   slipped throw, ...). */
int
nhv_aim_path(coordxy x0, coordxy y0, int ddx, int ddy, coordxy *px,
             coordxy *py, int maxn)
{
    long m = max(abs(aim.dx), abs(aim.dy));
    long x1, y1, ax, ay, sx, sy, err;
    coordxy x = x0, y = y0;
    int n = 0;

    if (!m || (long) ddx * aim.dx + (long) ddy * aim.dy <= 0)
        return 0;
    /* far along the line: maxn squares in its main direction */
    x1 = x0 + (aim.dx * maxn + (aim.dx >= 0 ? m / 2 : -m / 2)) / m;
    y1 = y0 + (aim.dy * maxn + (aim.dy >= 0 ? m / 2 : -m / 2)) / m;
    ax = labs(x1 - x0), ay = labs(y1 - y0);
    sx = x1 > x0 ? 1 : -1, sy = y1 > y0 ? 1 : -1;
    err = ax - ay;
    while (n < maxn && (x != x1 || y != y1)) { /* Bresenham */
        long e2 = 2 * err;

        if (e2 > -ay)
            err -= ay, x += (coordxy) sx;
        if (e2 < ax)
            err += ax, y += (coordxy) sy;
        px[n] = x, py[n] = y;
        n++;
    }
    return n;
}

/* "thrown <tile> <x0> <y0> <x1> <y1>": something the hero threw or fired
   flew from <x0,y0> to <x1,y1> (sent as a combat event) */
void
nhv_throw_event(int glyph, int x0, int y0, int x1, int y1)
{
    char buf[80];

    if (x0 == x1 && y0 == y1)
        return;
    Sprintf(buf, "thrown %d %d %d %d %d", (int) glyphmap[glyph].tileidx, x0,
            y0, x1, y1);
    nhv_push_event(NHV_EV_COMBAT, 0, buf);
}

/* "roll <tile> <x0> <y0> <x1> <y1> <gone>" (sent as a combat event): a
   boulder rolled from x0,y0 to x1,y1 (gone: it fell in somewhere there) */
void
nhv_roll_event(int glyph, int x0, int y0, int x1, int y1, int gone)
{
    char buf[80];

    Sprintf(buf, "roll %d %d %d %d %d %d", (int) glyphmap[glyph].tileidx,
            x0, y0, x1, y1, gone ? 1 : 0);
    nhv_push_event(NHV_EV_COMBAT, 0, buf);
}

/* "explode <x> <y> <expltype>" (sent as a combat event) */
void
nhv_explode_event(int x, int y, int expltype)
{
    char buf[64];

    Sprintf(buf, "explode %d %d %d", x, y, expltype);
    nhv_push_event(NHV_EV_COMBAT, 0, buf);
}

/* "beam <otyp> <x0> <y0> <x1> <y1>" (sent as a combat event) */
void
nhv_beam_event(int otyp, int x0, int y0, int x1, int y1)
{
    char buf[64];

    if (x0 == x1 && y0 == y1)
        return;
    Sprintf(buf, "beam %d %d %d %d %d", otyp, x0, y0, x1, y1);
    nhv_push_event(NHV_EV_COMBAT, 0, buf);
}

void
nhv_combat_event(const char *kind, unsigned a, unsigned b, int melee)
{
    char buf[64];

    Sprintf(buf, "%s %u %u %d", kind, a, b, melee);
    nhv_push_event(NHV_EV_COMBAT, 0, buf);
}

/* runs on the game thread (see nhv_call) */
int
nhv_exec_mon_step(unsigned id, int x, int y)
{
    struct monst *mtmp = mon_by_id(id);
    int r;

    if (!mtmp)
        return -1;
    if (isok(x, y) && (u_at(x, y) || m_at(x, y)))
        return -3; /* occupied for now */
    r = nhv_mon_step(mtmp, (coordxy) x, (coordxy) y);
    if (r == MMOVE_MOVED) {
        if (gv.vision_full_recalc)
            vision_recalc(0);
        return 1;
    }
    return (r == MMOVE_DIED) ? -1 : 0;
}

/*nhv_free.c*/
