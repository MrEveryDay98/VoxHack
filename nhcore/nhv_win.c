/* nhv_win.c - the "shim" window port for NetHack Voxel.
 *
 * Nothing is drawn here. Output becomes events for the host (messages,
 * text windows); input requests block the game thread until the host
 * answers through the queue in nhv_api.c. The map itself is not mirrored:
 * the host reads NetHack's display buffer directly via nhv_get_map().
 */
#include "hack.h"
#include "dlb.h"
#include "func_tab.h"
#include "nhv_internal.h"

extern glyph_map glyphmap[MAX_GLYPH]; /* display.c / tile.c */

#ifdef SHIM_GRAPHICS

#define MAXWIN 32
#define MAXLINES 512

struct nhv_line {
    int glyph;
    char sel, gsel;
    int attr;
    int selectable, preselected;
    anything ident;
    char *text;
};

struct nhv_window {
    int active;
    int type;
    int nlines;
    struct nhv_line lines[MAXLINES];
    char *prompt;
};

static struct nhv_window wins[MAXWIN];
static int menu_win = -1; /* window currently offered via a MENU request */
static int menu_how = PICK_NONE;
static char last_msg[BUFSZ];

/* ------------------------------------------------------------ helpers */
static void
clear_lines(struct nhv_window *w)
{
    int i;

    for (i = 0; i < w->nlines; i++)
        free(w->lines[i].text), w->lines[i].text = 0;
    w->nlines = 0;
    if (w->prompt)
        free(w->prompt), w->prompt = 0;
}

static struct nhv_window *
getwin(winid id)
{
    if (id < 0 || id >= MAXWIN || !wins[id].active)
        return (struct nhv_window *) 0;
    return &wins[id];
}

static struct nhv_line *
add_line(struct nhv_window *w, const char *text)
{
    struct nhv_line *ln;

    if (w->nlines >= MAXLINES)
        return (struct nhv_line *) 0;
    ln = &w->lines[w->nlines++];
    memset(ln, 0, sizeof *ln);
    ln->glyph = NO_GLYPH;
    ln->text = dupstr(text ? text : "");
    return ln;
}

static void
emit_text_window(struct nhv_window *w)
{
    int i;

    nhv_push_event(NHV_EV_TEXT_BEGIN, 0, w->prompt ? w->prompt : "");
    for (i = 0; i < w->nlines; i++)
        nhv_push_event(NHV_EV_TEXT_LINE, w->lines[i].attr, w->lines[i].text);
    nhv_push_event(NHV_EV_TEXT_END, 0, "");
}

static void
wait_for(int kind, const char *prompt, const char *choices, int def,
         nhv_qitem *out)
{
    nhv_request req;

    memset(&req, 0, sizeof req);
    req.kind = kind;
    req.def = def;
    req.for_command = (kind == NHV_REQ_KEY
                       && program_state.input_state == commandInp);
    Snprintf(req.prompt, sizeof req.prompt, "%s", prompt ? prompt : "");
    Snprintf(req.choices, sizeof req.choices, "%s", choices ? choices : "");
    if (kind == NHV_REQ_MENU && menu_win >= 0) {
        req.menu_count = wins[menu_win].nlines;
        req.menu_how = (menu_how == PICK_ANY) ? NHV_PICK_ANY : NHV_PICK_ONE;
    }
    nhv_wait_input(&req, out);
    last_msg[0] = '\0'; /* answered; don't reuse it as the next prompt */
}

const char *
nhv_win_last_message(void)
{
    return last_msg;
}

int
nhv_win_menu_item(int index, nhv_menu_item *out)
{
    struct nhv_window *w;
    struct nhv_line *ln;

    if (menu_win < 0 || !(w = getwin(menu_win)) || index < 0
        || index >= w->nlines)
        return 0;
    ln = &w->lines[index];
    memset(out, 0, sizeof *out);
    out->glyph = ln->glyph;
    out->tile = (ln->glyph >= 0 && ln->glyph < MAX_GLYPH)
                    ? glyphmap[ln->glyph].tileidx : -1;
    out->selectable = ln->selectable;
    out->preselected = ln->preselected;
    out->attr = ln->attr;
    out->sel = ln->sel;
    Snprintf(out->text, sizeof out->text, "%s", ln->text);
    return 1;
}

/* ------------------------------------------------------------ procs */
static void
nhv_init_nhwindows(int *argc UNUSED, char **argv UNUSED)
{
    memset(wins, 0, sizeof wins);
    iflags.window_inited = TRUE;
}

static void
nhv_player_selection(void)
{
    genl_player_selection();
}

static void
nhv_askname(void)
{
    char buf[BUFSZ];

    getlin("Who are you?", buf);
    if (!*buf || *buf == '\033')
        Strcpy(buf, "Adventurer");
    Snprintf(svp.plname, sizeof svp.plname, "%s", buf);
}

static void
nhv_get_nh_event(void)
{
}

static void
nhv_exit_nhwindows(const char *str)
{
    if (str && *str)
        nhv_push_event(NHV_EV_RAW, 0, str);
    iflags.window_inited = FALSE;
}

static void
nhv_suspend_nhwindows(const char *str UNUSED)
{
}

static void
nhv_resume_nhwindows(void)
{
}

static winid
nhv_create_nhwindow(int type)
{
    int i;

    for (i = 0; i < MAXWIN; i++)
        if (!wins[i].active) {
            memset(&wins[i], 0, sizeof wins[i]);
            wins[i].active = 1;
            wins[i].type = type;
            return i;
        }
    panic("nhv: out of windows");
    /*NOTREACHED*/
    return WIN_ERR;
}

static void
nhv_clear_nhwindow(winid id)
{
    struct nhv_window *w = getwin(id);

    if (w && w->type != NHW_MESSAGE)
        clear_lines(w);
}

static void
nhv_display_nhwindow(winid id, boolean blocking UNUSED)
{
    struct nhv_window *w = getwin(id);

    if (!w)
        return;
    if ((w->type == NHW_TEXT || w->type == NHW_MENU) && w->nlines > 0) {
        emit_text_window(w);
        clear_lines(w);
    }
}

static void
nhv_destroy_nhwindow(winid id)
{
    struct nhv_window *w = getwin(id);

    if (!w)
        return;
    if ((w->type == NHW_TEXT) && w->nlines > 0)
        emit_text_window(w);
    clear_lines(w);
    w->active = 0;
    if (menu_win == id)
        menu_win = -1;
}

static void
nhv_curs(winid id UNUSED, int x UNUSED, int y UNUSED)
{
}

static void
nhv_putstr(winid id, int attr, const char *str)
{
    struct nhv_window *w = getwin(id);
    struct nhv_line *ln;

    if (!w)
        return;
    switch (w->type) {
    case NHW_MESSAGE:
        Snprintf(last_msg, sizeof last_msg, "%s", str);
        nhv_push_event(NHV_EV_MESSAGE, attr, str);
        break;
    case NHW_TEXT:
    case NHW_MENU:
        if ((ln = add_line(w, str)) != 0)
            ln->attr = attr;
        break;
    default: /* status, map: host reads state directly */
        break;
    }
}

static void
nhv_display_file(const char *fname, boolean complain)
{
    dlb *f;
    char buf[BUFSZ];
    winid win;

    if (!(f = dlb_fopen(fname, "r"))) {
        if (complain)
            pline("Cannot open \"%s\".", fname);
        return;
    }
    win = nhv_create_nhwindow(NHW_TEXT);
    while (dlb_fgets(buf, sizeof buf, f)) {
        char *nl = strchr(buf, '\n');

        if (nl)
            *nl = '\0';
        nhv_putstr(win, 0, buf);
    }
    (void) dlb_fclose(f);
    nhv_destroy_nhwindow(win);
}

static void
nhv_start_menu(winid id, unsigned long mbehavior UNUSED)
{
    struct nhv_window *w = getwin(id);

    if (w)
        clear_lines(w);
}

static void
nhv_add_menu(winid id, const glyph_info *glyphinfo, const ANY_P *identifier,
             char ch, char gch, int attr, int clr UNUSED, const char *str,
             unsigned int itemflags)
{
    struct nhv_window *w = getwin(id);
    struct nhv_line *ln;

    if (!w || !(ln = add_line(w, str)))
        return;
    ln->glyph = glyphinfo ? glyphinfo->glyph : NO_GLYPH;
    ln->sel = ch;
    ln->gsel = gch;
    ln->attr = attr;
    ln->ident = *identifier;
    ln->selectable = (identifier->a_void != 0);
    ln->preselected = (itemflags & MENU_ITEMFLAGS_SELECTED) != 0;
}

static void
nhv_end_menu(winid id, const char *prompt)
{
    struct nhv_window *w = getwin(id);
    static const char autosel[] =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    int i, next = 0;

    if (!w)
        return;
    if (w->prompt)
        free(w->prompt);
    w->prompt = dupstr(prompt ? prompt : "");
    /* give every selectable line without an accelerator its own one,
       skipping letters already in use */
    for (i = 0; i < w->nlines; i++) {
        struct nhv_line *ln = &w->lines[i];

        if (!ln->selectable || ln->sel)
            continue;
        while (autosel[next]) {
            int j, used = 0;

            for (j = 0; j < w->nlines; j++)
                if (w->lines[j].sel == autosel[next])
                    used = 1;
            if (!used)
                break;
            next++;
        }
        if (autosel[next])
            ln->sel = autosel[next++];
    }
}

/* Selection answer format: string of selector chars. "\x01" = all. */
static int
nhv_select_menu(winid id, int how, MENU_ITEM_P **menu_list)
{
    struct nhv_window *w = getwin(id);
    nhv_qitem in;
    const char *sels;
    char keybuf[2];
    int i, n = 0, all;

    *menu_list = (MENU_ITEM_P *) 0;
    if (!w)
        return -1;
    if (how == PICK_NONE) {
        emit_text_window(w);
        return 0;
    }
    menu_win = id;
    menu_how = how;
    wait_for(NHV_REQ_MENU, w->prompt, "", 0, &in);
    menu_win = -1;

    if (in.type == NHV_Q_KEY) {
        if (in.key == '\033')
            return -1;
        keybuf[0] = (char) in.key, keybuf[1] = '\0';
        sels = keybuf;
    } else {
        sels = in.str;
    }
    all = (sels[0] == '\x01');
    *menu_list = (MENU_ITEM_P *) alloc(sizeof(MENU_ITEM_P)
                                       * (unsigned) (w->nlines + 1));
    for (i = 0; i < w->nlines; i++) {
        struct nhv_line *ln = &w->lines[i];

        if (!ln->selectable)
            continue;
        if (all || (ln->sel && strchr(sels, ln->sel))
            || (ln->gsel && strchr(sels, ln->gsel))) {
            (*menu_list)[n].item = ln->ident;
            (*menu_list)[n].count = -1L;
            (*menu_list)[n].itemflags = 0;
            n++;
            if (how == PICK_ONE)
                break;
        }
    }
    if (!n) {
        free((genericptr_t) *menu_list);
        *menu_list = (MENU_ITEM_P *) 0;
    }
    return n;
}

static char
nhv_message_menu(char let, int how UNUSED, const char *mesg)
{
    pline("%s", mesg);
    return let;
}

static void
nhv_mark_synch(void)
{
}

static void
nhv_wait_synch(void)
{
}

#ifdef CLIPPING
static void
nhv_cliparound(int x UNUSED, int y UNUSED)
{
}
#endif

static void
nhv_print_glyph(winid id UNUSED, coordxy x UNUSED, coordxy y UNUSED,
                const glyph_info *glyphinfo UNUSED,
                const glyph_info *bkglyphinfo UNUSED)
{
}

static void
nhv_raw_print(const char *str)
{
    nhv_push_event(NHV_EV_RAW, 0, str);
}

static int
nhv_nh_poskey(coordxy *x, coordxy *y, int *mod)
{
    nhv_qitem in;
    /* picking a place on the map (getpos): the host shows the map, and a
       square clicked there comes back as "@x,y" - a mouse click, which
       getpos takes as the choice */
    boolean pos = (x && y && mod && program_state.input_state == getposInp);

    wait_for(pos ? NHV_REQ_POS : NHV_REQ_KEY, last_msg, "", 0, &in);
    if (pos && in.type == NHV_Q_TEXT && in.str[0] == '@') {
        int px, py;

        if (sscanf(in.str + 1, "%d,%d", &px, &py) == 2 && isok(px, py)) {
            *x = (coordxy) px, *y = (coordxy) py;
            *mod = CLICK_1;
            return 0;
        }
        return '\033';
    }
    if (in.type == NHV_Q_KEY)
        return in.key;
    /* text where a key was expected: use its first char */
    return in.str[0] ? (unsigned char) in.str[0] : '\033';
}

/* the hero is helpless this turn (moveloop): wait until the host says a
   turn of time has passed, so sleeping, being paralysed, fainting... last
   as long in the world as they do in NetHack, instead of all at once */
void
nhv_helpless_turn(void)
{
    nhv_qitem in;

    wait_for(NHV_REQ_TURN, "", "", 0, &in);
}

static int
nhv_nhgetch(void)
{
    return nhv_nh_poskey((coordxy *) 0, (coordxy *) 0, (int *) 0);
}

static void
nhv_nhbell(void)
{
    nhv_push_event(NHV_EV_BELL, 0, "");
}

static int
nhv_doprev_message(void)
{
    return 0;
}

static char
nhv_yn_function(const char *query, const char *resp, char def)
{
    nhv_qitem in;
    int ch;

    wait_for(NHV_REQ_YN, query, resp, def, &in);
    ch = (in.type == NHV_Q_KEY) ? in.key
                                : (in.str[0] ? (unsigned char) in.str[0] : 0);
    if (resp && *resp) {
        if (ch == '\033') {
            ch = strchr(resp, 'q') ? 'q' : strchr(resp, 'n') ? 'n' : def;
        } else if (ch == '\n' || ch == '\r' || ch == ' ' || !ch) {
            ch = def;
        } else if (!strchr(resp, ch)) {
            /* unexpected answer: the default is the safe choice */
            ch = def;
        }
    }
    return (char) ch;
}

static void
nhv_getlin(const char *prompt, char *outbuf)
{
    nhv_qitem in;

    wait_for(NHV_REQ_LINE, prompt, "", 0, &in);
    if (in.type == NHV_Q_KEY && in.key == '\033')
        Strcpy(outbuf, "\033");
    else if (in.type == NHV_Q_KEY)
        outbuf[0] = (char) in.key, outbuf[1] = '\0';
    else
        Snprintf(outbuf, BUFSZ, "%s", in.str);
}

static int
nhv_get_ext_cmd(void)
{
    nhv_qitem in;
    int *matches = 0, n;

    wait_for(NHV_REQ_EXTCMD, "#", "", 0, &in);
    if (in.type != NHV_Q_TEXT || !in.str[0])
        return -1;
    /* "name arg arg..." -- arguments for the #nhv* host commands */
    {
        char *sp = strchr(in.str, ' ');

        memset(nhv_cmd_args, 0, sizeof nhv_cmd_args);
        nhv_cmd_text[0] = '\0';
        if (sp)
            Snprintf(nhv_cmd_text, sizeof nhv_cmd_text, "%s", sp + 1);
        if (sp) {
            int k = 0;
            char *p = sp;

            *sp = '\0';
            while (k < NHV_MAXARGS && *++p) {
                nhv_cmd_args[k++] = atoi(p);
                while (*p && *p != ' ')
                    p++;
                if (!*p)
                    break;
            }
        }
    }
    n = extcmds_match(in.str, ECM_IGNOREAC | ECM_EXACTMATCH, &matches);
    return (n == 1 && matches) ? matches[0] : -1;
}

static void
nhv_number_pad(int state UNUSED)
{
}

static void
nhv_delay_output(void)
{
    nhv_push_event(NHV_EV_DELAY, 0, "");
}

static void
nhv_preference_update(const char *pref UNUSED)
{
}

static char *
nhv_getmsghistory(boolean init UNUSED)
{
    return (char *) 0;
}

static void
nhv_putmsghistory(const char *msg UNUSED, boolean restoring UNUSED)
{
}

static void
nhv_update_inventory(int arg UNUSED)
{
}

static win_request_info *
nhv_ctrl_nhwindow(winid window UNUSED, int request UNUSED,
                  win_request_info *wri UNUSED)
{
    return (win_request_info *) 0;
}

struct window_procs shim_procs = {
    WPID(shim),
    (WC_COLOR | WC_HILITE_PET),
    (WC2_DARKGRAY),
    { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    nhv_init_nhwindows, nhv_player_selection, nhv_askname, nhv_get_nh_event,
    nhv_exit_nhwindows, nhv_suspend_nhwindows, nhv_resume_nhwindows,
    nhv_create_nhwindow, nhv_clear_nhwindow, nhv_display_nhwindow,
    nhv_destroy_nhwindow, nhv_curs, nhv_putstr, genl_putmixed,
    nhv_display_file, nhv_start_menu, nhv_add_menu, nhv_end_menu,
    nhv_select_menu, nhv_message_menu, nhv_mark_synch, nhv_wait_synch,
#ifdef CLIPPING
    nhv_cliparound,
#endif
#ifdef POSITIONBAR
    donull,
#endif
    nhv_print_glyph, nhv_raw_print, nhv_raw_print, nhv_nhgetch,
    nhv_nh_poskey, nhv_nhbell, nhv_doprev_message, nhv_yn_function,
    nhv_getlin, nhv_get_ext_cmd, nhv_number_pad, nhv_delay_output,
#ifdef CHANGE_COLOR
    donull, donull,
#endif
    genl_outrip,
    nhv_preference_update,
    nhv_getmsghistory, nhv_putmsghistory,
    genl_status_init, genl_status_finish, genl_status_enablefield,
    genl_status_update,
    genl_can_suspend_no,
    nhv_update_inventory,
    nhv_ctrl_nhwindow,
};

#endif /* SHIM_GRAPHICS */
/*nhv_win.c*/
