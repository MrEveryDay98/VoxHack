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

/* #nhvmove x y: the hero's body entered square <x,y>; move there without
   using time (time passes separately through ticks). */
int
donhvmove(void)
{
    int x = nhv_cmd_args[0], y = nhv_cmd_args[1];
    int dx = x - u.ux, dy = y - u.uy;
    struct monst *mtmp;

    if (!isok(x, y) || (!dx && !dy) || abs(dx) > 1 || abs(dy) > 1)
        return ECMD_OK;
    mtmp = m_at(x, y);
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
    domove();
    svc.context.nopick = 0;
    return ECMD_OK;
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

    if (!isok(x, y) || max(abs(dx), abs(dy)) != 2 || m_at(x, y) || u.ustuck
        || u.utrap || u.uswallow)
        return ECMD_OK;
    for (mx = u.ux - 1; mx <= u.ux + 1; mx++)
        for (my = u.uy - 1; my <= u.uy + 1; my++) {
            if (!isok(mx, my) || u_at(mx, my) || abs(x - mx) > 1
                || abs(y - my) > 1 || !m_at(mx, my))
                continue; /* (only to get past someone) */
            if (test_move(u.ux, u.uy, mx - u.ux, my - u.uy, TEST_MOVE)
                && test_move(mx, my, x - mx, y - my, TEST_MOVE)) {
                teleds(x, y, TELEDS_ALLOW_DRAG);
                return ECMD_OK;
            }
        }
    return ECMD_OK;
}

/* #nhvtick: one hero action's worth of time passes. */
int
donhvtick(void)
{
    return ECMD_TIME;
}

/* #nhvattack id: melee a monster the host says is within reach. */
int
donhvattack(void)
{
    struct monst *mtmp = mon_by_id((unsigned) nhv_cmd_args[0]);
    int dx, dy;

    if (!mtmp)
        return ECMD_OK;
    dx = sgn(mtmp->mx - u.ux), dy = sgn(mtmp->my - u.uy);
    if (!dx && !dy)
        dx = 1;
    u.dx = dx, u.dy = dy, u.dz = 0;
    svc.context.forcefight = 1;
    (void) do_attack(mtmp);
    svc.context.forcefight = 0;
    return ECMD_TIME;
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

        if (DEADMONSTER(m) || m->mx <= 0)
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

/* #nhvmhit pid: the missile reached the hero's body */
int
donhvmhit(void)
{
    struct nhv_flying *f = missile_by_pid((unsigned) nhv_cmd_args[0]);
    int r;

    if (!f)
        return ECMD_OK;
    r = nhv_missile_hits_hero(mon_by_id(f->mon_id), f->obj, f->lx, f->ly);
    if (r == 0) {
        missile_event("miss", f->pid); /* dodged: it flies on */
    } else {
        missile_event(r == 1 ? "hit" : "stop", f->pid);
        f->obj = 0;
    }
    return ECMD_OK;
}

/* #nhvmhitm pid m_id: the missile reached a monster's body */
int
donhvmhitm(void)
{
    struct nhv_flying *f = missile_by_pid((unsigned) nhv_cmd_args[0]);
    struct monst *m = mon_by_id((unsigned) nhv_cmd_args[1]);

    if (!f)
        return ECMD_OK;
    if (m && nhv_missile_hits_mon(m, f->obj, f->range)) {
        missile_event("stop", f->pid);
        f->obj = 0;
    } else {
        missile_event("pass", f->pid);
    }
    return ECMD_OK;
}

/* #nhvmland pid x y: the missile came down on square <x,y> */
int
donhvmland(void)
{
    struct nhv_flying *f = missile_by_pid((unsigned) nhv_cmd_args[0]);
    coordxy x = (coordxy) nhv_cmd_args[1], y = (coordxy) nhv_cmd_args[2];

    if (!f)
        return ECMD_OK;
    if (!isok(x, y))
        x = f->lx, y = f->ly;
    nhv_missile_lands(f->obj, x, y);
    f->obj = 0;
    missile_event("land", f->pid);
    return ECMD_OK;
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
        return ECMD_OK;
    if (mid == 0) {
        res = nhv_ray_hits_hero(r->type, r->nd, r->dx, r->dy, r->forcemiss);
    } else {
        struct monst *m = mon_by_id(mid);

        res = m ? nhv_ray_hits_mon(r->type, r->nd, m, r->forcemiss,
                                   r->sayhit, r->saymiss)
                : 0;
    }
    ray_event(res == 2 ? "reflect" : res == 3 ? "stop" : res == 1 ? "hit"
                                                                  : "miss",
              r->rid);
    return ECMD_OK;
}

/* #nhvraysq rid x y [x y ...]: the ray crossed these squares */
int
donhvraysq(void)
{
    struct nhv_rayrec *r = ray_by_rid((unsigned) nhv_cmd_args[0]);
    int k;

    if (!r)
        return ECMD_OK;
    for (k = 1; k + 1 < NHV_MAXARGS; k += 2) {
        if (!nhv_cmd_args[k] && !nhv_cmd_args[k + 1])
            break;
        nhv_ray_square(r->type, (coordxy) nhv_cmd_args[k],
                       (coordxy) nhv_cmd_args[k + 1], &r->shopdamage);
    }
    return ECMD_OK;
}

/* #nhvrayend rid x y: the ray is spent at <x,y> */
int
donhvrayend(void)
{
    struct nhv_rayrec *r = ray_by_rid((unsigned) nhv_cmd_args[0]);

    if (!r)
        return ECMD_OK;
    nhv_ray_end(r->type, (coordxy) nhv_cmd_args[1], (coordxy) nhv_cmd_args[2],
                r->shopdamage);
    r->used = FALSE;
    return ECMD_OK;
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
    return ECMD_OK;
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
    return ECMD_OK;
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
        return ECMD_OK;
    }
    if (dmg <= 0)
        return ECMD_OK;
    You("step on %s!", why);
    losehp(Maybe_Half_Phys(dmg), why, KILLED_BY);
    if (!rn2(6))
        poisoned("spikes", A_STR, "stepping on poison spikes",
                 /* if the damage triggered life-saving, poison is
                    limited to attribute loss (as in a spiked pit) */
                 (u.umortality > oldumort) ? 0 : 8, FALSE);
    return ECMD_OK;
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
} splev;
static FILE *splev_out; /* #nhvsplevdump: templates go here */

void
nhv_splev_begin(const char *protofile)
{
    char *dot;

    splev.active = TRUE;
    splev.n = 0;
    Snprintf(splev.proto, sizeof splev.proto, "%s", protofile);
    if ((dot = strrchr(splev.proto, '.')) != 0)
        *dot = '\0'; /* ("minetn-3.lua" -> "minetn-3") */
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
                for (x = splev.r[i].x; x < splev.r[i].x + splev.r[i].w; x++)
                    fputc('0' + levl[x][y].typ, splev_out);
            fputc('\n', splev_out);
        } else {
            Snprintf(buf, sizeof buf, "%ld %d %s %d %d %d %d %d",
                     (long) ubirthday, (int) ledger_no(&u.uz), splev.proto,
                     i + 1, splev.r[i].x, splev.r[i].y, splev.r[i].w,
                     splev.r[i].h);
            nhv_push_event(NHV_EV_SPLEV, 0, buf);
        }
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
        return ECMD_OK;
    if (!(splev_out = fopen("splev_templates.txt", "w"))) {
        pline("Can't write splev_templates.txt.");
        return ECMD_OK;
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
    return ECMD_OK;
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
    return ECMD_OK;
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
