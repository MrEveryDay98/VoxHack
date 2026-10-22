/* nhv_sound.c - NetHack's sound interface, forwarded to the host.
 *
 * Takes the "vissound" sound library slot. Every sound effect, spoken line
 * (verbalize/SetVoice), achievement, ambience change and played tune
 * becomes an NHV_EV_SOUND event; the host decides what (if anything) to
 * play, using the sound/voice configuration made in the sound editor.
 *
 * Event text formats (fields separated by '|'):
 *   effect|<name>|<volume>[|<x>|<y>|<m_id or 0>]   (where it happens, if known)
 *   verbal|<speaker m_id or 0>|<speaker monster name>|<gender>|<tone>|<volume>|<text>
 *   achievement|<a>|<b>|<c>
 *   ambience|<action>|<id>|<proximity>
 *   notes|<instrument>|<volume>|<notes>
 *   usersound|<volume>|<file>
 *   quest|<section>|<message id>     (from questpgr.c)
 */
#include "hack.h"
#include "nhv_internal.h"

#ifdef SND_LIB_VISSOUND

#undef SEFFECTS_ENUM
#define SEFFECTS_AUTOMAP
static const struct {
    int id;
    const char *name;
} se_names[] = {
#include "seffects.h"
};
#undef SEFFECTS_AUTOMAP

static const char *sound_place(void);

static const char *
se_name(int32_t seid)
{
    size_t i;

    for (i = 0; i < SIZE(se_names); i++)
        if (se_names[i].id == seid)
            return se_names[i].name;
    return "unknown";
}

static void
sound_event(const char *fmt, ...)
{
    char buf[256];
    va_list ap;

    va_start(ap, fmt);
    (void) vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    nhv_push_event(NHV_EV_SOUND, 0, buf);
}

static void
nhv_snd_init(void)
{
}

static void
nhv_snd_exit(const char *reason UNUSED)
{
}

static void
nhv_snd_achievement(schar a, schar b, int32_t c)
{
    sound_event("achievement|%d|%d|%d", (int) a, (int) b, (int) c);
}

static void
nhv_snd_effect(char *desc UNUSED, int32_t seid, int32_t volume)
{
    sound_event("effect|%s|%d%s", se_name(seid), (int) volume, sound_place());
}

static void
nhv_snd_notes(int32_t instrument, const char *str, int32_t volume)
{
    sound_event("notes|%d|%d|%s", (int) instrument, (int) volume, str ? str : "");
}

static void
nhv_snd_usersound(char *filename, int32_t volume, int32_t idx UNUSED)
{
    sound_event("usersound|%d|%s", (int) volume, filename ? filename : "");
}

static void
nhv_snd_ambience(int32_t action, int32_t id, int32_t proximity)
{
    sound_event("ambience|%d|%d|%d", (int) action, (int) id, (int) proximity);
}

static void
nhv_snd_verbal(char *text, int32_t gender, int32_t tone, int32_t vol,
               int32_t moreinfo)
{
    unsigned id = (unsigned) gv.voice.serialno;
    const char *who = "";
    struct monst *m;

    /* the Oracle's rumors are said with no speaker set, only her voice:
       she's the one on the level (so the host knows her voice and where
       she sits) */
    if ((moreinfo & voice_oracle) != 0) {
        for (m = fmon; m; m = m->nmon)
            if (m->data == &mons[PM_ORACLE] && !DEADMONSTER(m)) {
                id = m->m_id;
                break;
            }
        if (!m)
            who = "Oracle";
    }
    for (m = fmon; m; m = m->nmon)
        if (m->m_id == id && !DEADMONSTER(m)) {
            who = pmname(m->data, m->female ? FEMALE : MALE);
            break;
        }
    if (!*who)
        who = (id == 4) ? "deity" : (id == 3) ? "artifact" : "voice";
    sound_event("verbal|%u|%s|%d|%d|%d|%s", id, who, (int) gender, (int) tone,
                (int) vol, text ? text : "");
}

struct sound_procs vissound_procs = {
    SOUNDID(vissound),
    SOUND_TRIGGER_USERSOUNDS | SOUND_TRIGGER_HEROMUSIC
        | SOUND_TRIGGER_ACHIEVEMENTS | SOUND_TRIGGER_SOUNDEFFECTS
        | SOUND_TRIGGER_AMBIENCE | SOUND_TRIGGER_VERBAL,
    nhv_snd_init,
    nhv_snd_exit,
    nhv_snd_achievement,
    nhv_snd_effect,
    nhv_snd_notes,
    nhv_snd_usersound,
    nhv_snd_ambience,
    nhv_snd_verbal,
};

/* where the next sound happens (NHV_SNDAT, NHV_HOOK_AT/MON,
   SoundeffectAt/Mon in nhvhooks.h): used by one sound, this turn only */
static struct {
    coordxy x, y;
    unsigned m_id;
    long moves;
    boolean set;
} snd_at;

void
nhv_sound_at(coordxy x, coordxy y, unsigned m_id)
{
    snd_at.x = x, snd_at.y = y, snd_at.m_id = m_id;
    snd_at.moves = svm.moves;
    snd_at.set = TRUE;
}

/* "|x|y|m_id" for the sound being made, or "" if it has no place of its
   own (none was given, or it's the hero's own square) */
static const char *
sound_place(void)
{
    static char buf[48];

    buf[0] = '\0';
    if (snd_at.set && snd_at.moves == svm.moves && isok(snd_at.x, snd_at.y)
        && !(u_at(snd_at.x, snd_at.y) && !snd_at.m_id))
        Snprintf(buf, sizeof buf, "|%d|%d|%u", (int) snd_at.x,
                 (int) snd_at.y, snd_at.m_id);
    snd_at.set = FALSE;
    return buf;
}

/* a sound hook placed in NetHack's code (NHV_HOOK) */
void
nhv_sound_hook(const char *id)
{
    sound_event("effect|%s|100%s", id, sound_place());
}

/* trap.c: the hero set off a trap: "trap_<name>" */
void
nhv_trap_hook(int ttyp)
{
    char buf[64], *p;

    Snprintf(buf, sizeof buf, "trap_%s",
             defsyms[trap_to_defsym(ttyp)].explanation);
    for (p = buf; *p; p++)
        if (*p == ' ' || *p == '-')
            *p = '_';
    sound_event("effect|%s|100", buf);
}

/* questpgr.c: a quest message is being shown */
void
nhv_quest_event(const char *section, const char *msgid)
{
    sound_event("quest|%s|%s", section ? section : "", msgid ? msgid : "");
}

#endif /* SND_LIB_VISSOUND */

/*nhv_sound.c*/
