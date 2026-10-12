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

#define NHV_API_VERSION 1
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
    NHV_EV_DELAY        /* animation frame boundary (delay_output) */
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
    unsigned char extra;    /* reserved */
} nhv_loc;

/* Fills buf[x * NHV_ROWNO + y] for every map location. */
NHV_API void nhv_get_map(nhv_loc *buf);

#define NHV_MON_PET      0x01
#define NHV_MON_PEACEFUL 0x02
#define NHV_MON_INVIS    0x04 /* remembered/unseen 'I' marker */
#define NHV_MON_DETECTED 0x08 /* sensed via telepathy/warning/detection */
#define NHV_MON_WARNING  0x10 /* warning number glyph */

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
    char name[160]; /* doname() */
} nhv_obj;

/* Hero inventory. Returns count. */
NHV_API int nhv_get_inventory(nhv_obj *buf, int max);
/* Objects on a map square (only meaningful where the hero can see / is). */
NHV_API int nhv_get_floor_objects(int x, int y, nhv_obj *buf, int max);

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
NHV_API const char *nhv_obj_name(int otyp); /* actual (unidentified-safe? no: true) name */

#ifdef __cplusplus
}
#endif
#endif /* NHV_API_H */
