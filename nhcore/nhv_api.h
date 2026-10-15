/* nhv_api.h - C interface to NetHack running as a library (nethack.dll).
 *
 * Threading model
 * ---------------
 * nhv_start() launches NetHack on its own thread. NetHack runs until it
 * needs input (a command key, a y/n answer, a menu selection, a line of
 * text) and then blocks; the state becomes NHV_WAITING and nhv_request()
 * describes what it wants.
 *
 * Input is queued with nhv_send_*(). Queued input is consumed in order by
 * whatever NetHack asks for next, so a whole action can be scripted ahead
 * of time (e.g. key 'q' then key 'a' = quaff item a). When the queue runs
 * dry NetHack blocks again.
 *
 * While the state is NHV_WAITING (or NHV_ENDED) the game thread is parked,
 * so the snapshot functions (nhv_get_*) may safely read game state.
 * Never call them while NHV_BUSY.
 *
 * One game per DLL load: NetHack keeps its state in globals, so the host
 * should FreeLibrary/LoadLibrary between games.
 */
#ifndef NHV_API_H
#define NHV_API_H

#ifdef NHV_BUILDING_DLL
#define NHV_API __declspec(dllexport)
#else
#define NHV_API __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define NHV_API_VERSION 8
#define NHV_COLNO 80
#define NHV_ROWNO 21

/* ------------------------------------------------------------ lifecycle */
enum nhv_state {
    NHV_NOT_STARTED = 0,
    NHV_BUSY,       /* game thread is running */
    NHV_WAITING,    /* blocked waiting for input; see nhv_request() */
    NHV_ENDED       /* game over / saved / quit; thread has exited */
};

/* datadir: read-only NetHack data (lua levels, rumors, ...).
 * userdir: writable dir for saves, bones, level files, record, config.
 * options: NetHack option string(s) in .nethackrc syntax, one per line
 *          (may be NULL). Example: "OPTIONS=role:valkyrie,!autopickup"
 * name:    character name; a matching save game is restored if present.
 * Returns 0 on success. */
NHV_API int nhv_start(const char *datadir, const char *userdir,
                      const char *options, const char *name);
NHV_API int nhv_state(void);
/* Block until the game thread is no longer BUSY or timeout_ms elapses
 * (timeout_ms < 0 waits forever). Returns the state. */
NHV_API int nhv_wait(int timeout_ms);
/* Exit status after NHV_ENDED (0 = normal). */
NHV_API int nhv_exit_code(void);
NHV_API int nhv_api_version(void);

/* ------------------------------------------------------------ requests */
enum nhv_req_kind {
    NHV_REQ_NONE = 0,
    NHV_REQ_KEY,    /* any keystroke: normally the next command */
    NHV_REQ_YN,     /* yn_function: prompt + allowed choices */
    NHV_REQ_MENU,   /* menu selection; see nhv_get_menu_item() */
    NHV_REQ_LINE,   /* getlin: free text */
    NHV_REQ_EXTCMD  /* extended command name, answer with nhv_send_text */
};

enum nhv_menu_how { NHV_PICK_NONE = 0, NHV_PICK_ONE = 1, NHV_PICK_ANY = 2 };

typedef struct nhv_request {
    int kind;           /* enum nhv_req_kind */
    int def;            /* yn default char (0 if none) */
    int menu_how;       /* enum nhv_menu_how */
    int menu_count;     /* number of menu lines (incl. headers) */
    int for_command;    /* KEY: nonzero when NetHack wants a new command */
    char prompt[256];   /* question text / menu title */
    char choices[64];   /* yn choices, e.g. "ynq" */
} nhv_request;

typedef struct nhv_menu_item {
    int glyph;          /* NO_GLYPH (-1) if none */
    int tile;           /* tile index for glyph, -1 if none */
    int selectable;
    int preselected;
    int attr;
    char sel;           /* selector char used to pick it (0 = header) */
    char text[159];
} nhv_menu_item;

NHV_API void nhv_get_request(nhv_request *out);
NHV_API int nhv_get_menu_item(int index, nhv_menu_item *out);

/* ------------------------------------------------------------ input */
NHV_API void nhv_send_key(int ch);
/* Answer a NHV_REQ_LINE / NHV_REQ_EXTCMD (no trailing newline needed).
 * Sending "\033" cancels. */
NHV_API void nhv_send_text(const char *text);
/* Answer a NHV_REQ_MENU with the selector chars of the chosen items.
 * Empty string = select nothing / cancel. "\x01" alone = all items. */
NHV_API void nhv_send_menu(const char *selectors);
/* Drop any queued, unconsumed input. */
NHV_API void nhv_clear_input(void);

/* ------------------------------------------------------------ events */
enum nhv_event_kind {
    NHV_EV_MESSAGE = 1, /* message line */
    NHV_EV_TEXT_BEGIN,  /* start of a text window (help, ^X, etc.) */
    NHV_EV_TEXT_LINE,
    NHV_EV_TEXT_END,
    NHV_EV_RAW,         /* raw_print output (errors, early messages) */
    NHV_EV_LEVEL_CHANGE,/* hero arrived on a different level */
    NHV_EV_BELL,
    NHV_EV_DELAY,       /* animation frame boundary (delay_output) */
    NHV_EV_MISSILE,     /* missile outcome: "hit|miss|stop|pass|land <pid>" */
    NHV_EV_COMBAT,      /* "attack <attacker m_id> <target m_id, 0 = hero> <melee>" */
    NHV_EV_SOUND,       /* sound/voice hook, see nhv_sound.c */
    NHV_EV_RAY,         /* ray outcome: "hit|miss|reflect|stop <rid>" */
    NHV_EV_CONTAINER,   /* "open|fail|changed|gone <container id>" */
    NHV_EV_SPLEV        /* "<game id> <ledger> <proto> <n> <x> <y> <w> <h>":
                           a special level's fixed region n */
};

typedef struct nhv_event {
    int kind;
    int attr;
    char text[256];
} nhv_event;

/* Returns 1 and fills *out if an event was pending, else 0. */
NHV_API int nhv_poll_event(nhv_event *out);

/* ------------------------------------------------------------ snapshot */
/* nhv_loc.flags */
#define NHV_LOC_SEEN     0x01  /* hero has seen this spot at some point */
#define NHV_LOC_CANSEE   0x02  /* currently in line of sight */
#define NHV_LOC_LIT      0x04  /* location is lit */
#define NHV_LOC_WASLIT   0x08  /* remembered as lit */
#define NHV_LOC_COULDSEE 0x10  /* clear path from hero (ignoring light) */

typedef struct nhv_loc {
    int glyph;      /* display buffer: what is shown right now */
    int mem_glyph;  /* remembered background (objects/traps/terrain) */
    short tile;     /* tile index of glyph */
    short mem_tile; /* tile index of mem_glyph */
    unsigned char typ;      /* true terrain type (levl[x][y].typ) */
    unsigned char flags;    /* NHV_LOC_* */
    unsigned char door;     /* D_* bits when typ is DOOR */
    unsigned char back;     /* true background: cmap symbol index (S_*) of
                               what's really there, seen or not (stairs
                               up/down, fountain, ...; never traps or
                               objects), 255 if none */
} nhv_loc;

/* Fills buf[x * NHV_ROWNO + y] for every map location. */
NHV_API void nhv_get_map(nhv_loc *buf);

#define NHV_MON_PET      0x01
#define NHV_MON_PEACEFUL 0x02
#define NHV_MON_INVIS    0x04 /* remembered/unseen 'I' marker */
#define NHV_MON_DETECTED 0x08 /* sensed via telepathy/warning/detection */
#define NHV_MON_WARNING  0x10 /* warning number glyph */
#define NHV_MON_SHOPKEEPER 0x20 /* a shopkeeper in its own shop */

typedef struct nhv_mon {
    unsigned id;    /* m_id, stable across turns; 0 for markers */
    int x, y;
    int glyph;
    int tile;
    int flags;      /* NHV_MON_* */
    int mndx;       /* monster type as displayed (-1 if unknown) */
    int size;       /* MZ_TINY .. MZ_GIGANTIC as displayed */
} nhv_mon;

/* Monsters the hero currently perceives (excludes the hero).
 * Returns the count (may exceed max; only max are written). */
NHV_API int nhv_get_monsters(nhv_mon *buf, int max);

#define NHV_HERO_BLIND     0x0001
#define NHV_HERO_HALLU     0x0002
#define NHV_HERO_LEVITATE  0x0004
#define NHV_HERO_FLYING    0x0008
#define NHV_HERO_INVIS     0x0010
#define NHV_HERO_STUN      0x0020
#define NHV_HERO_CONF      0x0040
#define NHV_HERO_UNDERWATER 0x0080
#define NHV_HERO_SWALLOWED 0x0100
#define NHV_HERO_TRAPPED   0x0200
#define NHV_HERO_POLY      0x0400
#define NHV_HERO_DEAD      0x0800
#define NHV_HERO_RIDING    0x1000
#define NHV_HERO_FAST      0x2000
#define NHV_HERO_VFAST     0x4000
#define NHV_HERO_INSHOP    0x8000
#define NHV_HERO_INTEMPLE  0x10000
#define NHV_HERO_OWES      0x20000 /* owes the shop it's in (unpaid items, fees) */
#define NHV_HERO_NOSQUEEZE 0x40000 /* can't squeeze diagonally past boulders and
                                      corners (too much carried, too big, Sokoban) */

typedef struct nhv_hero {
    int x, y;
    int ux0, uy0;           /* previous position */
    int dnum, dlevel;       /* dungeon branch and level within it */
    int depth;              /* absolute depth */
    int ledger;             /* unique level id */
    long moves;             /* game turn counter */
    int hp, hpmax, pw, pwmax, ac, xlvl;
    long xp, gold;
    int str, dex, con, intl, wis, cha;
    int speed;              /* current movement rate (12 = normal) */
    int hunger;             /* u.uhs */
    int encumbrance;
    int glyph, tile;
    int mndx;               /* form (polymorph) */
    unsigned flags;         /* NHV_HERO_* */
    int dx, dy;             /* last movement direction */
    char name[32];
    char rank[32];
    char align[16];
    char dungeon_name[32];
    char level_desc[32];    /* e.g. "Dlvl:3" */
} nhv_hero;

NHV_API void nhv_get_hero(nhv_hero *out);

#define NHV_OBJ_WORN     0x01
#define NHV_OBJ_WIELDED  0x02
#define NHV_OBJ_QUIVERED 0x04
#define NHV_OBJ_CURSED_KNOWN 0x08
#define NHV_OBJ_BLESSED_KNOWN 0x10
#define NHV_OBJ_ALTWEP   0x20
#define NHV_OBJ_CONTAINER 0x40
#define NHV_OBJ_LIT      0x80

typedef struct nhv_obj {
    unsigned id;    /* o_id */
    char invlet;
    char oclass;    /* object class symbol index (ILLOBJ_CLASS..) */
    short otyp;
    long quan;
    int glyph, tile;
    int flags;      /* NHV_OBJ_* */
    int weight;
    unsigned worn;  /* owornmask: W_ARM 0x1, W_ARMC 0x2, W_ARMH 0x4, W_ARMS 0x8,
                       W_ARMG 0x10, W_ARMF 0x20, W_ARMU 0x40, W_WEP 0x100,
                       W_QUIVER 0x200, W_SWAPWEP 0x400, W_AMUL 0x10000,
                       W_RINGL 0x20000, W_RINGR 0x40000, W_TOOL 0x80000 */
    int armcat;     /* armor category (ARM_SUIT..ARM_SHIRT) or -1 */
    char name[160]; /* doname() */
} nhv_obj;

/* Hero inventory. Returns count. */
NHV_API int nhv_get_inventory(nhv_obj *buf, int max);
/* Objects on a map square (only meaningful where the hero can see / is). */
NHV_API int nhv_get_floor_objects(int x, int y, nhv_obj *buf, int max);
/* Contents of a container the hero can reach (carried, or on/next to their
 * square), once it has been opened ("#nhvloot <id>"; NHV_EV_CONTAINER
 * "open <id>"). Items move with "#nhvcontin <id> <obj id> <count>" and
 * "#nhvcontout <id> <obj id> <count>" (count 0 = all). Returns count, or
 * -1 if there's no such container. */
NHV_API int nhv_get_container(unsigned id, nhv_obj *buf, int max);

/* ------------------------------------------------------------ glyph info */
enum nhv_glyph_kind {
    NHV_G_NONE = 0, NHV_G_MON, NHV_G_PET, NHV_G_INVIS, NHV_G_DETECTED,
    NHV_G_BODY, NHV_G_RIDDEN, NHV_G_OBJ, NHV_G_CMAP, NHV_G_EXPLODE,
    NHV_G_ZAP, NHV_G_SWALLOW, NHV_G_WARNING, NHV_G_STATUE, NHV_G_UNEXPLORED,
    NHV_G_NOTHING
};
typedef struct nhv_glyph_info {
    int kind;       /* enum nhv_glyph_kind */
    int index;      /* mndx / otyp / cmap symbol index (S_*) / etc */
    int tile;
    int color;      /* CLR_* */
    int sym;        /* ascii/unicode symbol */
} nhv_glyph_info;
NHV_API void nhv_get_glyph_info(int glyph, nhv_glyph_info *out);
NHV_API int nhv_max_glyph(void);
NHV_API int nhv_tile_count(void);
/* Name of the cmap symbol S_* index ("vwall", "room", "dnstair" ...). */
NHV_API const char *nhv_cmap_name(int symidx);
NHV_API const char *nhv_mon_name(int mndx);
NHV_API const char *nhv_obj_name(int otyp); /* true (identified) name */

/* Static monster data; works without a running game. */
typedef struct nhv_moninfo {
    int size;       /* MZ_TINY .. MZ_GIGANTIC */
    int tile;       /* tile of its (male) glyph */
    int sym;        /* class symbol */
} nhv_moninfo;
NHV_API int nhv_num_monsters(void);
NHV_API int nhv_mon_info(int mndx, nhv_moninfo *out);

/* ------------------------------------------------------------ free movement
 * In free-movement mode the host owns physical positions. Monsters stop
 * stepping around the grid by themselves; the host moves them and calls
 * nhv_move_monster() when a body crosses into another square. Melee range is
 * whatever the host reports through nhv_set_monstates(). The hero moves
 * with "#nhvmove x y" (no time), time passes with "#nhvtick", and melee
 * attacks with "#nhvattack <m_id>". */
NHV_API void nhv_set_freemove(int on);

typedef struct nhv_monstate {
    unsigned id;
    int in_reach;           /* can hit the hero in melee right now */
    unsigned melee_target;  /* m_id this monster should fight, or 0 */
} nhv_monstate;
NHV_API void nhv_set_monstates(const nhv_monstate *states, int n);

#define NHV_MF_TAME     0x001
#define NHV_MF_PEACEFUL 0x002
#define NHV_MF_FLEE     0x004
#define NHV_MF_CANMOVE  0x008  /* awake, not trapped/paralyzed/eating */
#define NHV_MF_SEES_U   0x010
#define NHV_MF_GRID     0x020  /* NetHack keeps moving it on the grid */
#define NHV_MF_VISIBLE  0x040  /* hero can perceive it */
#define NHV_MF_CONFUSED 0x080
#define NHV_MF_HIDER    0x100
#define NHV_MF_HIDDEN   0x200
#define NHV_MF_KEEPAWAY 0x400  /* prefers to fight from a distance */

typedef struct nhv_monfull {
    unsigned id;
    int x, y;       /* NetHack square */
    int mndx;       /* true monster type */
    int speed;      /* movement rate, 12 = normal */
    int size;
    int mux, muy;   /* where it thinks the hero is */
    int flags;      /* NHV_MF_* */
    int hp, hpmax;
} nhv_monfull;
/* Every monster on the level (true state, for the host's simulation;
 * only draw what nhv_get_monsters() says the hero perceives). */
NHV_API int nhv_get_all_monsters(nhv_monfull *buf, int max);

/* Move monster <id> onto adjacent square <x,y>. Only while WAITING; runs
 * synchronously on the game thread. Returns 1 moved, 0 refused (the
 * square itself won't do), -1 the monster is gone (e.g. died in a trap),
 * -2 not now (the game is busy; try again shortly), -3 someone is
 * standing there (the hero or another monster; it may clear soon). */
NHV_API int nhv_move_monster(unsigned id, int x, int y);

/* Missiles monsters throw at the hero don't resolve on the grid: they are
 * handed to the host, which flies them and reports the outcome with
 * "#nhvmhit pid" (reached the hero), "#nhvmhitm pid m_id" (reached a
 * monster) or "#nhvmland pid x y" (came down). Each produces an
 * NHV_EV_MISSILE event; "miss" means the to-hit roll failed (dodged) and
 * the missile keeps flying. */
typedef struct nhv_missile {
    unsigned pid;
    unsigned mon_id;    /* thrower, 0 if none */
    int x, y;           /* launch square */
    int range;          /* squares */
    int otyp, glyph, tile;
} nhv_missile;
/* missiles launched since the last call */
NHV_API int nhv_get_missiles(nhv_missile *buf, int max);
NHV_API void nhv_clear_missiles(void);

/* Rays (wands, spells, breath) are handed to the host too. It flies and
 * bounces them and reports: "#nhvrayhit rid m_id" (reached a body; m_id 0
 * = hero; NHV_EV_RAY says hit/miss/reflect/stop), "#nhvraysq rid x y ..."
 * (crossed squares: burning, freezing...), "#nhvrayend rid x y" (spent). */
typedef struct nhv_ray {
    unsigned rid;
    int type;           /* NetHack ray type (see dobuzz) */
    int kind;           /* 0 magic missile, 1 fire, 2 cold, 3 sleep, 4 death,
                           5 lightning, 6 poison gas, 7 acid */
    int x, y, dx, dy;   /* start square and grid direction */
    int range;          /* squares */
    int from_hero;
    unsigned caster;    /* m_id of the monster that fired it, or 0 */
} nhv_ray;
NHV_API int nhv_get_rays(nhv_ray *buf, int max);
NHV_API void nhv_clear_rays(void);

#ifdef __cplusplus
}
#endif
/* Spells the hero knows (for the host's spell menu): name, the tile of
   its spellbook and whether it's cast in a direction. */
typedef struct nhv_spell {
    char name[64];
    int tile;
    int directional; /* 1: cast at something (a direction or yourself) */
} nhv_spell;
NHV_API int nhv_get_spells(nhv_spell *buf, int max);

/* tells this game apart from others (when it was started) */
NHV_API long nhv_game_id(void);

#endif /* NHV_API_H */
