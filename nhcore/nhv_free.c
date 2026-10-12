/* nhv_free.c - free (continuous) movement support.
 *
 * The host owns where monsters and the hero physically are. Each server
 * step it tells us which monsters can reach the hero in melee (and what
 * a pet wants to fight); NetHack's own turn logic then uses that instead
 * of grid adjacency. See include/nhvhooks.h in the NetHack tree.
 */
#include "hack.h"
#include "nhv_internal.h"

boolean nhv_freemove = FALSE;

#define MAXSTATES 512
static nhv_monstate states[MAXSTATES];
static int nstates;

/* arguments of the #nhv* extended command being run */
int nhv_cmd_args[4];

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
    /* walking never fights; it may swap places with a pet */
    svc.context.nopick = !(mtmp && mtmp->mtame && canspotmon(mtmp));
    svc.context.forcefight = 0;
    domove();
    svc.context.nopick = 0;
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
        if (n < max)
            buf[n] = f;
        n++;
    }
    return n;
}

/* runs on the game thread (see nhv_call) */
int
nhv_exec_mon_step(unsigned id, int x, int y)
{
    struct monst *mtmp = mon_by_id(id);
    int r;

    if (!mtmp)
        return -1;
    r = nhv_mon_step(mtmp, (coordxy) x, (coordxy) y);
    if (r == MMOVE_MOVED) {
        if (gv.vision_full_recalc)
            vision_recalc(0);
        return 1;
    }
    return (r == MMOVE_DIED) ? -1 : 0;
}

/*nhv_free.c*/
