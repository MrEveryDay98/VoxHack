/* nhv_api.c - exported API: game thread control, input queue, events,
 * and read-only snapshots of game state for the host. */
#include "win32api.h"
#include "hack.h"
#include <process.h>
#include "nhv_internal.h"

extern glyph_map glyphmap[MAX_GLYPH]; /* display.c / tile.c */
static void ensure_mons(void);

/* ------------------------------------------------------------ sync state */
static CRITICAL_SECTION cs;
static CONDITION_VARIABLE cv_input;  /* game thread waits for input */
static CONDITION_VARIABLE cv_state;  /* host waits for state change */
static volatile int game_state = NHV_NOT_STARTED;
static int game_exit_code;
static nhv_request cur_req;
static HANDLE game_thread;

#define QMAX 256
static nhv_qitem queue[QMAX];
static int q_head, q_count;

#define EVMAX 1024
static nhv_event events[EVMAX];
static int ev_head, ev_count;

static char start_rcfile[PATHLEN], start_name[PL_NSIZ];

static unsigned __stdcall
game_thread_proc(void *arg UNUSED)
{
    int code = nhv_game_thread_main(start_rcfile, start_name);

    EnterCriticalSection(&cs);
    game_exit_code = code;
    game_state = NHV_ENDED;
    cur_req.kind = NHV_REQ_NONE;
    WakeAllConditionVariable(&cv_state);
    LeaveCriticalSection(&cs);
    return 0;
}

NHV_API int
nhv_api_version(void)
{
    return NHV_API_VERSION;
}

NHV_API int
nhv_start(const char *datadir, const char *userdir, const char *options,
          const char *name)
{
    if (game_state != NHV_NOT_STARTED)
        return -1;
    InitializeCriticalSection(&cs);
    InitializeConditionVariable(&cv_input);
    InitializeConditionVariable(&cv_state);
    nhv_set_dirs(datadir, userdir);

    /* a seeded game: a file "nhv_seed" in the user dir with the seed in it
       (the level atlas) */
    {
        char seedfile[BUFSZ];
        FILE *sf;

        Snprintf(seedfile, sizeof seedfile, "%s%snhv_seed", userdir,
                 (userdir[strlen(userdir) - 1] == '\\'
                  || userdir[strlen(userdir) - 1] == '/') ? "" : "\\");
        nhv_fixed_seed = 0;
        if ((sf = fopen(seedfile, "r")) != 0) {
            unsigned long seed = 0;

            if (fscanf(sf, "%lu", &seed) == 1)
                nhv_fixed_seed = seed;
            fclose(sf);
        }
    }

    /* options go to a generated rc file in the user dir */
    start_rcfile[0] = '\0';
    if (options && *options) {
        FILE *fp;

        Snprintf(start_rcfile, sizeof start_rcfile, "%s%snhv.nethackrc",
                 userdir,
                 (userdir[strlen(userdir) - 1] == '\\'
                  || userdir[strlen(userdir) - 1] == '/') ? "" : "\\");
        if ((fp = fopen(start_rcfile, "w")) == 0)
            return -2;
        fputs(options, fp);
        fputc('\n', fp);
        fclose(fp);
    }
    Snprintf(start_name, sizeof start_name, "%s", name ? name : "");

    game_state = NHV_BUSY;
    /* NetHack recurses deeply in places (level generation, Lua); give it
     * a generous stack. */
    game_thread = (HANDLE) _beginthreadex(NULL, 16 * 1024 * 1024,
                                          game_thread_proc, NULL, 0, NULL);
    if (!game_thread) {
        game_state = NHV_NOT_STARTED;
        return -3;
    }
    return 0;
}

NHV_API int
nhv_state(void)
{
    return game_state;
}

NHV_API int
nhv_wait(int timeout_ms)
{
    int st;

    if (game_state == NHV_NOT_STARTED)
        return NHV_NOT_STARTED;
    EnterCriticalSection(&cs);
    while (game_state == NHV_BUSY) {
        if (!SleepConditionVariableCS(&cv_state, &cs,
                                      timeout_ms < 0 ? INFINITE
                                                     : (DWORD) timeout_ms))
            break; /* timed out */
    }
    st = game_state;
    LeaveCriticalSection(&cs);
    if (st == NHV_ENDED && game_thread) {
        WaitForSingleObject(game_thread, INFINITE);
        CloseHandle(game_thread);
        game_thread = 0;
    }
    return st;
}

NHV_API int
nhv_exit_code(void)
{
    return game_exit_code;
}

NHV_API void
nhv_get_request(nhv_request *out)
{
    EnterCriticalSection(&cs);
    if (game_state == NHV_WAITING)
        *out = cur_req;
    else
        memset(out, 0, sizeof *out);
    LeaveCriticalSection(&cs);
}

NHV_API int
nhv_get_menu_item(int index, nhv_menu_item *out)
{
    if (game_state != NHV_WAITING || cur_req.kind != NHV_REQ_MENU)
        return 0;
    return nhv_win_menu_item(index, out);
}

/* ------------------------------------------------------------ input */
static void
enqueue(const nhv_qitem *item)
{
    EnterCriticalSection(&cs);
    if (q_count < QMAX) {
        queue[(q_head + q_count) % QMAX] = *item;
        q_count++;
        if (game_state == NHV_WAITING)
            game_state = NHV_BUSY; /* it will wake and consume */
        WakeAllConditionVariable(&cv_input);
    }
    LeaveCriticalSection(&cs);
}

NHV_API void
nhv_send_key(int ch)
{
    nhv_qitem it = { NHV_Q_KEY, ch, "" };

    enqueue(&it);
}

NHV_API void
nhv_send_text(const char *text)
{
    nhv_qitem it = { NHV_Q_TEXT, 0, "" };

    Snprintf(it.str, sizeof it.str, "%s", text ? text : "");
    enqueue(&it);
}

NHV_API void
nhv_send_menu(const char *selectors)
{
    nhv_qitem it = { NHV_Q_MENU, 0, "" };

    Snprintf(it.str, sizeof it.str, "%s", selectors ? selectors : "");
    enqueue(&it);
}

NHV_API void
nhv_clear_input(void)
{
    EnterCriticalSection(&cs);
    q_head = q_count = 0;
    LeaveCriticalSection(&cs);
}

/* synchronous calls run on the game thread while it waits for input */
static volatile int call_done, call_result;

static int
exec_call(const nhv_qitem *it)
{
    switch (it->key) {
    case NHV_CALL_MON_STEP:
        return nhv_exec_mon_step((unsigned) it->args[0], it->args[1],
                                 it->args[2]);
    default:
        return 0;
    }
}

/* game thread side */
void
nhv_wait_input(const nhv_request *req, nhv_qitem *out)
{
    EnterCriticalSection(&cs);
    for (;;) {
        while (q_count == 0) {
            cur_req = *req;
            game_state = NHV_WAITING;
            WakeAllConditionVariable(&cv_state);
            SleepConditionVariableCS(&cv_input, &cs, INFINITE);
        }
        *out = queue[q_head];
        q_head = (q_head + 1) % QMAX;
        q_count--;
        if (out->type != NHV_Q_CALL)
            break;
        /* a call: run it and keep waiting for real input */
        LeaveCriticalSection(&cs);
        {
            int r = exec_call(out);

            EnterCriticalSection(&cs);
            call_result = r;
            call_done = 1;
            game_state = NHV_WAITING;
            WakeAllConditionVariable(&cv_state);
        }
    }
    game_state = NHV_BUSY;
    cur_req.kind = NHV_REQ_NONE;
    LeaveCriticalSection(&cs);
}

NHV_API int
nhv_move_monster(unsigned id, int x, int y)
{
    nhv_qitem it;
    int r;

    memset(&it, 0, sizeof it);
    it.type = NHV_Q_CALL;
    it.key = NHV_CALL_MON_STEP;
    it.args[0] = (int) id, it.args[1] = x, it.args[2] = y;
    EnterCriticalSection(&cs);
    if (game_state != NHV_WAITING || q_count != 0) {
        LeaveCriticalSection(&cs);
        return -2; /* (busy: not a refusal) */
    }
    call_done = 0;
    queue[(q_head + q_count) % QMAX] = it;
    q_count++;
    game_state = NHV_BUSY;
    WakeAllConditionVariable(&cv_input);
    while (!call_done)
        SleepConditionVariableCS(&cv_state, &cs, INFINITE);
    r = call_result;
    LeaveCriticalSection(&cs);
    return r;
}

/* ------------------------------------------------------------ events */
void
nhv_push_event(int kind, int attr, const char *text)
{
    nhv_event *ev;

    EnterCriticalSection(&cs);
    if (ev_count == EVMAX) { /* drop oldest */
        ev_head = (ev_head + 1) % EVMAX;
        ev_count--;
    }
    ev = &events[(ev_head + ev_count) % EVMAX];
    ev->kind = kind;
    ev->attr = attr;
    Snprintf(ev->text, sizeof ev->text, "%s", text ? text : "");
    ev_count++;
    LeaveCriticalSection(&cs);
}

NHV_API int
nhv_poll_event(nhv_event *out)
{
    int got = 0;

    if (game_state == NHV_NOT_STARTED)
        return 0;
    EnterCriticalSection(&cs);
    if (ev_count) {
        *out = events[ev_head];
        ev_head = (ev_head + 1) % EVMAX;
        ev_count--;
        got = 1;
    }
    LeaveCriticalSection(&cs);
    return got;
}

/* ------------------------------------------------------------ snapshot */
static int
safe_to_read(void)
{
    return (game_state == NHV_WAITING || game_state == NHV_ENDED)
           && program_state.in_moveloop;
}

static int
tile_of(int glyph)
{
    if (glyph < 0 || glyph >= MAX_GLYPH)
        return -1;
    return glyphmap[glyph].tileidx;
}

/* In 3D you make out what lies in view across a room, not just within a
   couple of squares as NetHack has it (see_nearby_objects()): objects you
   can see within NEAR_OBJ squares count as seen up close (their look - a
   red gem, a pink potion - not what they are), so they aren't drawn as
   the generic object of their class. */
#define NEAR_OBJ 8

static void
nhv_see_objects_in_view(void)
{
    int x, y;
    struct obj *otmp;
    boolean changed;

    if (Blind)
        return;
    for (x = u.ux - NEAR_OBJ; x <= u.ux + NEAR_OBJ; x++)
        for (y = u.uy - NEAR_OBJ; y <= u.uy + NEAR_OBJ; y++) {
            if (!isok(x, y) || !cansee(x, y))
                continue;
            changed = FALSE;
            for (otmp = svl.level.objects[x][y]; otmp; otmp = otmp->nexthere)
                if (!otmp->dknown) {
                    observe_object(otmp);
                    changed = TRUE;
                }
            /* (the remembered picture, if it was the generic one) */
            if (changed && glyph_is_generic_object(levl[x][y].glyph))
                newsym_force(x, y);
        }
}

NHV_API void
nhv_get_map(nhv_loc *buf)
{
    int x, y;

    memset(buf, 0, sizeof *buf * NHV_COLNO * NHV_ROWNO);
    if (!safe_to_read())
        return;
    nhv_see_objects_in_view();
    for (x = 0; x < COLNO && x < NHV_COLNO; x++)
        for (y = 0; y < ROWNO && y < NHV_ROWNO; y++) {
            nhv_loc *l = &buf[x * NHV_ROWNO + y];
            struct rm *lev = &levl[x][y];

            l->glyph = glyph_at(x, y);
            l->mem_glyph = lev->glyph;
            l->tile = (short) tile_of(l->glyph);
            l->mem_tile = (short) tile_of(l->mem_glyph);
            l->typ = (unsigned char) lev->typ;
            l->flags = (lev->seenv ? NHV_LOC_SEEN : 0)
                       | (cansee(x, y) ? NHV_LOC_CANSEE : 0)
                       | (lev->lit ? NHV_LOC_LIT : 0)
                       | (lev->waslit ? NHV_LOC_WASLIT : 0)
                       | (couldsee(x, y) ? NHV_LOC_COULDSEE : 0)
                       | (t_at(x, y) ? NHV_LOC_TRAP : 0);
            l->door = (IS_DOOR(lev->typ) || lev->typ == SDOOR)
                              ? (unsigned char) lev->doormask : 0;
            {
                int bg = back_to_glyph(x, y);

                l->back = glyph_is_cmap(bg) ? (unsigned char) glyph_to_cmap(bg)
                                            : 255;
                l->back_tile = glyph_is_cmap(bg) ? (short) tile_of(bg) : -1;
            }
            {
                struct trap *t = t_at(x, y);

                l->trap = (t && t->tseen)
                              ? (unsigned char) trap_to_defsym(t->ttyp)
                              : 255;
                /* Sokoban's pits and holes are open from the start (unlike
                   a pit trap, which opens as you step on it): one not
                   seen yet is still a hole in the ground the host draws
                   (128 + its symbol: not a known trap) */
                if (t && !t->tseen && Sokoban
                    && (is_pit(t->ttyp) || t->ttyp == HOLE))
                    l->trap = (unsigned char) (128 + trap_to_defsym(t->ttyp));
            }
        }
}

NHV_API int
nhv_get_monsters(nhv_mon *buf, int max)
{
    int x, y, n = 0;

    if (!safe_to_read())
        return 0;
    for (x = 1; x < COLNO; x++)
        for (y = 0; y < ROWNO; y++) {
            int g = glyph_at(x, y);
            nhv_mon m;
            struct monst *mtmp;

            if (u_at(x, y)) {
                /* someone sharing the hero's square (the map shows the
                   hero there): as it would look on its own */
                mtmp = m_at(x, y);
                if (!mtmp || mtmp == u.ustuck)
                    continue;
                if (!canspotmon(mtmp)) {
                    /* one you can't see, remembered there ('I': you
                       bumped into it, attacked it) - the marker the map
                       can't show under the hero */
                    if (!glyph_is_invisible(levl[x][y].glyph))
                        continue;
                    g = GLYPH_INVISIBLE;
                } else
                    g = mtmp->mtame ? pet_to_glyph(mtmp, rn2_on_display_rng)
                                    : mon_to_glyph(mtmp, rn2_on_display_rng);
            }
            if (!glyph_is_monster(g) && !glyph_is_invisible(g)
                && !glyph_is_warning(g))
                continue;
            memset(&m, 0, sizeof m);
            m.x = x, m.y = y;
            m.glyph = g;
            m.tile = tile_of(g);
            m.mndx = -1;
            if (glyph_is_invisible(g)) {
                m.flags |= NHV_MON_INVIS;
            } else if (glyph_is_warning(g)) {
                m.flags |= NHV_MON_WARNING;
            } else {
                m.mndx = glyph_to_mon(g);
                if (m.mndx >= LOW_PM && m.mndx < NUMMONS)
                    m.size = mons[m.mndx].msize;
                if (glyph_is_pet(g))
                    m.flags |= NHV_MON_PET;
                if (glyph_is_detected_monster(g))
                    m.flags |= NHV_MON_DETECTED;
                if ((mtmp = m_at(x, y)) != 0) {
                    m.id = mtmp->m_id;
                    if (mtmp->minvis && canseemon(mtmp))
                        m.flags |= NHV_MON_SEEINVIS;
                    if (sensemon(mtmp))
                        m.flags |= NHV_MON_SENSED
                                   | (canseemon(mtmp) ? 0 : NHV_MON_UNSEEN);
                    if (mtmp->mpeaceful && canspotmon(mtmp))
                        m.flags |= NHV_MON_PEACEFUL;
                    if (mtmp->isshk && inhishop(mtmp))
                        m.flags |= NHV_MON_SHOPKEEPER;
                    if (mtmp->mtrapped) {
                        struct trap *t = t_at(x, y);

                        if (t && is_pit(t->ttyp))
                            m.flags |= NHV_MON_IN_PIT;
                    }
                    if (mtmp == u.ustuck && !u.uswallow
                        && !sticks(gy.youmonst.data))
                        m.flags |= NHV_MON_HOLDING;
                }
            }
            if (n < max)
                buf[n] = m;
            n++;
        }
    /* what has swallowed the hero (it isn't on the map then: you only
       see its insides), so the host knows what you're in */
    if (u.uswallow && u.ustuck) {
        nhv_mon m;

        memset(&m, 0, sizeof m);
        m.x = u.ux, m.y = u.uy;
        m.mndx = monsndx(u.ustuck->data);
        m.glyph = mon_to_glyph(u.ustuck, rn2_on_display_rng);
        m.tile = tile_of(m.glyph);
        m.size = u.ustuck->data->msize;
        m.id = u.ustuck->m_id;
        m.flags = NHV_MON_ENGULFING;
        if (n < max)
            buf[n] = m;
        n++;
    }
    /* the hero, and what it's riding (for the host's third-person view;
       neither is drawn on the map like the others) */
    {
        nhv_mon m;

        memset(&m, 0, sizeof m);
        m.x = u.ux, m.y = u.uy;
        m.mndx = monsndx(gy.youmonst.data);
        m.glyph = hero_glyph;
        m.tile = tile_of(m.glyph);
        m.size = gy.youmonst.data->msize;
        m.flags = NHV_MON_SELF;
        if (Invis)
            m.flags |= See_invisible ? NHV_MON_SEEINVIS : NHV_MON_HIDDEN;
        if (n < max)
            buf[n] = m;
        n++;
    }
    if (u.usteed) {
        nhv_mon m;

        memset(&m, 0, sizeof m);
        m.x = u.ux, m.y = u.uy;
        m.mndx = monsndx(u.usteed->data);
        m.glyph = mon_to_glyph(u.usteed, rn2_on_display_rng);
        m.tile = tile_of(m.glyph);
        m.size = u.usteed->data->msize;
        m.id = u.usteed->m_id;
        m.flags = NHV_MON_STEED;
        if (n < max)
            buf[n] = m;
        n++;
    }
    return n;
}

NHV_API int
nhv_get_shops(nhv_shop *buf, int max)
{
    extern const struct shclass shtypes[]; /* shknam.c */
    static const int dirs[4][2] = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } };
    int i, k, n = 0;

    if (!(nhv_state() == NHV_WAITING || nhv_state() == NHV_ENDED)
        || !program_state.in_moveloop)
        return 0;
    /* (the level's rooms, then the rooms inside rooms: Minetown's shops) */
    for (i = 0; i < svn.nroom + gn.nsubroom && n < max; i++) {
        struct mkroom *r = i < svn.nroom ? &svr.rooms[i]
                                         : &gs.subrooms[i - svn.nroom];
        struct monst *shk = r->resident;
        nhv_shop *s;
        coord d;

        if (r->rtype < SHOPBASE || r->doorct < 1)
            continue;
        d = svd.doors[r->fdoor];
        s = &buf[n];
        memset(s, 0, sizeof *s);
        s->door_x = d.x, s->door_y = d.y;
        s->in_x = -1;
        for (k = 0; k < 4; k++) {
            int x = d.x + dirs[k][0], y = d.y + dirs[k][1];

            if (x >= r->lx && x <= r->hx && y >= r->ly && y <= r->hy) {
                s->in_x = x, s->in_y = y;
                break;
            }
        }
        if (s->in_x < 0)
            continue;
        Strcpy(s->type, shtypes[r->rtype - SHOPBASE].name);
        if (shk && !DEADMONSTER(shk) && shk->isshk && has_eshk(shk))
            Strcpy(s->keeper, shkname(shk));
        n++;
    }
    return n;
}

NHV_API int
nhv_get_dungeons(nhv_dungeon *buf, int max)
{
    int i, n = 0;

    if (!(nhv_state() == NHV_WAITING || nhv_state() == NHV_ENDED)
        || !program_state.in_moveloop)
        return 0;
    for (i = 0; i < svn.n_dgns && n < max; i++, n++) {
        memset(&buf[n], 0, sizeof buf[n]);
        Strcpy(buf[n].name, svd.dungeons[i].dname);
        buf[n].levels = svd.dungeons[i].num_dunlevs;
        buf[n].depth_start = svd.dungeons[i].depth_start;
        buf[n].entry = svd.dungeons[i].entry_lev;
    }
    return n;
}

NHV_API const char *
nhv_level_proto(int dnum, int dlevel)
{
    d_level lev;
    s_level *sp;

    if (!(nhv_state() == NHV_WAITING || nhv_state() == NHV_ENDED)
        || !program_state.in_moveloop || dnum < 0 || dnum >= svn.n_dgns)
        return "";
    lev.dnum = (xint16) dnum, lev.dlevel = (xint16) dlevel;
    sp = Is_special(&lev);
    return sp ? sp->proto : "";
}

NHV_API long
nhv_game_id(void)
{
    return (long) ubirthday;
}

NHV_API int
nhv_get_spells(nhv_spell *buf, int max)
{
    int i, n = 0;

    if (!(nhv_state() == NHV_WAITING || nhv_state() == NHV_ENDED)
        || !program_state.in_moveloop)
        return 0;
    for (i = 0; i < MAXSPELL && svs.spl_book[i].sp_id != NO_SPELL; i++) {
        int otyp = svs.spl_book[i].sp_id;

        if (n < max) {
            nhv_spell *s = &buf[n];

            memset(s, 0, sizeof *s);
            Strcpy(s->name, OBJ_NAME(objects[otyp]));
            s->tile = tile_of(objnum_to_glyph(otyp));
            s->directional = objects[otyp].oc_dir != NODIR;
        }
        n++;
    }
    return n;
}

/* What NetHack's #monster would do for the hero now (in domonability()'s
   order), or "" when it would only say there's nothing to do. */
static const char *
nhv_monability(void)
{
    struct permonst *uptr = gy.youmonst.data;
    boolean might_hide = (is_hider(uptr) || hides_under(uptr));

    if (might_hide && webmaker(uptr))
        return "Hide or spin a web";
    if (can_breathe(uptr))
        return "Breathe";
    if (attacktype(uptr, AT_SPIT))
        return "Spit";
    if (uptr->mlet == S_NYMPH)
        return Punished ? "Remove the chain" : "";
    if (attacktype(uptr, AT_GAZE))
        return "Gaze";
    if (is_were(uptr))
        return "Summon help";
    if (might_hide)
        return "Hide";
    if (webmaker(uptr))
        return "Spin a web";
    if (is_mind_flayer(uptr))
        return "Mind blast";
    if (u.umonnum == PM_GREMLIN)
        return (IS_FOUNTAIN(levl[u.ux][u.uy].typ) || is_pool(u.ux, u.uy))
                   ? "Multiply" : "";
    if (is_unicorn(uptr))
        return "Use your horn";
    if (uptr->msound == MS_SHRIEK)
        return "Shriek";
    if (is_vampire(uptr) || is_vampshifter(&gy.youmonst))
        return "Change form";
    if (u.usteed && can_breathe(u.usteed->data))
        return "Steed breathes";
    return "";
}
NHV_API void
nhv_get_hero(nhv_hero *out)
{
    unsigned f = 0;
    int g;

    memset(out, 0, sizeof *out);
    if (!safe_to_read())
        return;
    out->x = u.ux, out->y = u.uy;
    out->ux0 = u.ux0, out->uy0 = u.uy0;
    out->dnum = u.uz.dnum, out->dlevel = u.uz.dlevel;
    out->depth = depth(&u.uz);
    out->ledger = ledger_no(&u.uz);
    out->moves = svm.moves;
    out->hp = Upolyd ? u.mh : u.uhp;
    out->hpmax = Upolyd ? u.mhmax : u.uhpmax;
    out->pw = u.uen, out->pwmax = u.uenmax;
    out->ac = u.uac;
    out->xlvl = u.ulevel;
    out->xp = u.uexp;
    out->gold = money_cnt(gi.invent);
    out->str = ACURR(A_STR), out->dex = ACURR(A_DEX);
    out->con = ACURR(A_CON), out->intl = ACURR(A_INT);
    out->wis = ACURR(A_WIS), out->cha = ACURR(A_CHA);
    out->speed = gy.youmonst.data->mmove;
    out->hunger = u.uhs;
    out->encumbrance = near_capacity();
    g = hero_glyph;
    out->glyph = g;
    out->tile = tile_of(g);
    out->mndx = u.umonnum;
    out->dx = u.dx, out->dy = u.dy;
    if (Blind) f |= NHV_HERO_BLIND;
    if (Hallucination) f |= NHV_HERO_HALLU;
    if (Levitation) f |= NHV_HERO_LEVITATE;
    if (Flying) f |= NHV_HERO_FLYING;
    if (Invis) f |= NHV_HERO_INVIS;
    if (Stunned) f |= NHV_HERO_STUN;
    if (Confusion) f |= NHV_HERO_CONF;
    if (Underwater) f |= NHV_HERO_UNDERWATER;
    if (u.uswallow) f |= NHV_HERO_SWALLOWED;
    if (u.utrap) f |= NHV_HERO_TRAPPED;
    if (Upolyd) f |= NHV_HERO_POLY;
    if (u.usteed) f |= NHV_HERO_RIDING;
    if (Fast) f |= NHV_HERO_FAST;
    if (Very_fast) f |= NHV_HERO_VFAST;
    if (program_state.gameover) f |= NHV_HERO_DEAD;
    if (*u.ushops) {
        struct monst *shkp = shop_keeper(*u.ushops);

        f |= NHV_HERO_INSHOP;
        if (shkp && inhishop(shkp)
            && (ESHK(shkp)->billct || ESHK(shkp)->debit))
            f |= NHV_HERO_OWES;
    }
    if (cant_squeeze_thru(&gy.youmonst))
        f |= NHV_HERO_NOSQUEEZE;
    if (temple_occupied(u.urooms)) f |= NHV_HERO_INTEMPLE;
    /* (not when it's the hero, polymorphed, holding on to a monster) */
    if (u.ustuck && !u.uswallow && !sticks(gy.youmonst.data))
        f |= NHV_HERO_HELD;
    if (uwep && is_pole(uwep)) {
        int range = nhv_pole_range();

        f |= NHV_HERO_POLE;
        if (range >= 8)
            f |= NHV_HERO_POLE8;
        else if (range >= 5)
            f |= NHV_HERO_POLE5;
    }
    if (flags.female)
        f |= NHV_HERO_FEMALE;
    if (gm.multi < 0)
        f |= NHV_HERO_HELPLESS;
    if (unconscious()) /* (asleep, fainted, knocked out) */
        f |= NHV_HERO_ASLEEP;
    if (u.twoweap)
        f |= NHV_HERO_TWOWEAP;
    if (Role_if(PM_MONK) && !uwep && !uarms)
        f |= NHV_HERO_TWOFISTS;
    {
        int sk;

        for (sk = P_FIRST_WEAPON; sk < P_NUM_SKILLS; sk++)
            if (can_advance(sk, FALSE)) {
                f |= NHV_HERO_ENHANCE;
                break;
            }
    }
    out->flags = f;
    f = 0;
    if (Stoned) f |= NHV_COND_STONE;
    if (Slimed) f |= NHV_COND_SLIME;
    if (Strangled) f |= NHV_COND_STRANGLED;
    if (Sick && (u.usick_type & SICK_VOMITABLE)) f |= NHV_COND_FOODPOIS;
    if (Sick && (u.usick_type & SICK_NONVOMITABLE)) f |= NHV_COND_TERMILL;
    if (u.utrap && u.utraptype == TT_LAVA) f |= NHV_COND_LAVA;
    if (Deaf) f |= NHV_COND_DEAF;
    if (Glib) f |= NHV_COND_GLIB;
    if (Wounded_legs) f |= NHV_COND_LEGS;
    out->conds = f;
    Snprintf(out->name, sizeof out->name, "%s", svp.plname);
    Snprintf(out->rank, sizeof out->rank, "%s",
             rank_of(u.ulevel, Role_switch, flags.female));
    Snprintf(out->align, sizeof out->align, "%s",
             (u.ualign.type == A_CHAOTIC) ? "Chaotic"
             : (u.ualign.type == A_NEUTRAL) ? "Neutral" : "Lawful");
    Snprintf(out->dungeon_name, sizeof out->dungeon_name, "%s",
             svd.dungeons[u.uz.dnum].dname);
    (void) describe_level(out->level_desc, 0);
    Snprintf(out->ability, sizeof out->ability, "%s", nhv_monability());
}

static void
fill_obj(struct obj *otmp, nhv_obj *o)
{
    memset(o, 0, sizeof *o);
    o->id = otmp->o_id;
    o->invlet = otmp->invlet;
    o->oclass = otmp->oclass;
    o->otyp = otmp->otyp;
    o->quan = otmp->quan;
    o->weight = otmp->owt;
    if (otmp->owornmask & (W_ARMOR | W_ACCESSORY))
        o->flags |= NHV_OBJ_WORN;
    if (otmp->owornmask & W_WEP)
        o->flags |= NHV_OBJ_WIELDED;
    if (carried(otmp) && nhv_invokable(otmp))
        o->flags |= NHV_OBJ_INVOKE;
    if (otmp->owornmask & W_QUIVER)
        o->flags |= NHV_OBJ_QUIVERED;
    if (otmp->owornmask & W_SWAPWEP)
        o->flags |= NHV_OBJ_ALTWEP;
    if (otmp->bknown && otmp->cursed)
        o->flags |= NHV_OBJ_CURSED_KNOWN;
    if (otmp->bknown && otmp->blessed)
        o->flags |= NHV_OBJ_BLESSED_KNOWN;
    if (Is_container(otmp))
        o->flags |= NHV_OBJ_CONTAINER;
    if (otmp->lamplit)
        o->flags |= NHV_OBJ_LIT;
    o->worn = (unsigned) otmp->owornmask;
    o->armcat = (otmp->oclass == ARMOR_CLASS) ? objects[otmp->otyp].oc_armcat
                                              : -1;
    Snprintf(o->name, sizeof o->name, "%s", doname(otmp));
    /* (after its name: naming it is what marks it seen up close, which
       its picture depends on - else a gem looked at for the first time,
       in a box say, shows as the generic gem) */
    o->glyph = obj_to_glyph(otmp, rn2_on_display_rng);
    o->tile = tile_of(o->glyph);
}

NHV_API int
nhv_get_inventory(nhv_obj *buf, int max)
{
    struct obj *otmp;
    int n = 0;

    if (!safe_to_read())
        return 0;
    for (otmp = gi.invent; otmp; otmp = otmp->nobj, n++)
        if (n < max)
            fill_obj(otmp, &buf[n]);
    return n;
}

NHV_API int
nhv_jump_squares(int *xy, int max)
{
    coordxy xs[64], ys[64];
    int i, n;

    if (!safe_to_read())
        return -2;
    if (max > 64)
        max = 64;
    n = nhv_jump_targets(xs, ys, max);
    for (i = 0; i < n; i++)
        xy[2 * i] = xs[i], xy[2 * i + 1] = ys[i];
    return n;
}

NHV_API int
nhv_get_floor_objects(int x, int y, nhv_obj *buf, int max)
{
    struct obj *otmp;
    int n = 0;

    if (!safe_to_read() || !isok(x, y))
        return 0;
    for (otmp = svl.level.objects[x][y]; otmp; otmp = otmp->nexthere, n++)
        if (n < max)
            fill_obj(otmp, &buf[n]);
    return n;
}

NHV_API int
nhv_get_container(unsigned id, nhv_obj *buf, int max)
{
    struct obj *cobj, *otmp;
    int n = 0;

    if (!safe_to_read() || !(cobj = nhv_find_container(id)))
        return -1;
    for (otmp = cobj->cobj; otmp; otmp = otmp->nobj, n++)
        if (n < max)
            fill_obj(otmp, &buf[n]);
    return n;
}

/* ------------------------------------------------------------ glyph info */
NHV_API void
nhv_get_glyph_info(int glyph, nhv_glyph_info *out)
{
    memset(out, 0, sizeof *out);
    out->tile = -1;
    out->index = -1;
    if (glyph < 0 || glyph >= MAX_GLYPH)
        return;
    out->tile = glyphmap[glyph].tileidx;
    out->color = glyphmap[glyph].sym.color;
    out->sym = (glyphmap[glyph].sym.symidx >= 0
                && glyphmap[glyph].sym.symidx < SYM_MAX)
                   ? gs.showsyms[glyphmap[glyph].sym.symidx] : '?';
    if (glyph_is_statue(glyph)) {
        out->kind = NHV_G_STATUE;
        out->index = glyph_to_mon(glyph);
    } else if (glyph_is_body(glyph)) {
        out->kind = NHV_G_BODY;
        out->index = glyph_to_mon(glyph);
    } else if (glyph_is_ridden_monster(glyph)) {
        out->kind = NHV_G_RIDDEN;
        out->index = glyph_to_mon(glyph);
    } else if (glyph_is_detected_monster(glyph)) {
        out->kind = NHV_G_DETECTED;
        out->index = glyph_to_mon(glyph);
    } else if (glyph_is_pet(glyph)) {
        out->kind = NHV_G_PET;
        out->index = glyph_to_mon(glyph);
    } else if (glyph_is_monster(glyph)) {
        out->kind = NHV_G_MON;
        out->index = glyph_to_mon(glyph);
    } else if (glyph_is_invisible(glyph)) {
        out->kind = NHV_G_INVIS;
    } else if (glyph_is_object(glyph)) {
        out->kind = NHV_G_OBJ;
        out->index = glyph_to_obj(glyph);
    } else if (glyph_is_cmap(glyph)) {
        out->kind = NHV_G_CMAP;
        out->index = glyph_to_cmap(glyph);
    } else if (glyph_is_explosion(glyph)) {
        out->kind = NHV_G_EXPLODE;
    } else if (glyph_is_cmap_zap(glyph)) {
        out->kind = NHV_G_ZAP;
    } else if (glyph_is_swallow(glyph)) {
        out->kind = NHV_G_SWALLOW;
    } else if (glyph_is_warning(glyph)) {
        out->kind = NHV_G_WARNING;
        out->index = glyph_to_warning(glyph);
    } else if (glyph_is_unexplored(glyph)) {
        out->kind = NHV_G_UNEXPLORED;
    } else if (glyph_is_nothing(glyph)) {
        out->kind = NHV_G_NOTHING;
    }
}

NHV_API int
nhv_max_glyph(void)
{
    return MAX_GLYPH;
}

NHV_API int
nhv_tile_count(void)
{
    extern int total_tiles_used;

    return total_tiles_used;
}

struct nhv_enum_name {
    int val;
    const char *nm;
};
#define DUMP_ENUMS_PCHAR
static const struct nhv_enum_name cmap_names[] = {
#include "defsym.h"
};
#undef DUMP_ENUMS_PCHAR

NHV_API const char *
nhv_cmap_name(int symidx)
{
    size_t i;

    for (i = 0; i < SIZE(cmap_names); i++)
        if (cmap_names[i].val == symidx)
            return cmap_names[i].nm;
    return "";
}

NHV_API int
nhv_cmap_tile(int symidx)
{
    if (symidx < 0 || symidx >= MAXPCHARS
        || !(nhv_state() == NHV_WAITING || nhv_state() == NHV_ENDED)
        || !program_state.in_moveloop)
        return -1;
    return glyphmap[cmap_to_glyph(symidx)].tileidx;
}

NHV_API const char *
nhv_mon_name(int mndx)
{
    ensure_mons();
    if (mndx < LOW_PM || mndx >= NUMMONS)
        return "";
    /* some monsters only have male/female names */
    if (mons[mndx].pmnames[NEUTRAL])
        return mons[mndx].pmnames[NEUTRAL];
    if (mons[mndx].pmnames[MALE])
        return mons[mndx].pmnames[MALE];
    return mons[mndx].pmnames[FEMALE] ? mons[mndx].pmnames[FEMALE] : "";
}

/* NetHack fills mons[] when a game starts; for static queries before
   that (the editor), fill it ourselves */
static void
ensure_mons(void)
{
    if (!mons[LOW_PM].pmnames[NEUTRAL] && !mons[LOW_PM].pmnames[MALE]
        && game_state == NHV_NOT_STARTED)
        monst_globals_init();
}

NHV_API int
nhv_num_monsters(void)
{
    ensure_mons();
    return NUMMONS;
}

NHV_API int
nhv_mon_info(int mndx, nhv_moninfo *out)
{
    int g;

    memset(out, 0, sizeof *out);
    ensure_mons();
    if (mndx < LOW_PM || mndx >= NUMMONS)
        return 0;
    out->size = mons[mndx].msize;
    g = mndx + GLYPH_MON_MALE_OFF;
    out->tile = glyphmap[g].tileidx;
    out->sym = def_monsyms[(int) mons[mndx].mlet].sym;
    return 1;
}

NHV_API const char *
nhv_obj_name(int otyp)
{
    if (otyp < 0 || otyp >= NUM_OBJECTS)
        return "";
    return OBJ_NAME(objects[otyp]) ? OBJ_NAME(objects[otyp]) : "";
}

/*nhv_api.c*/
