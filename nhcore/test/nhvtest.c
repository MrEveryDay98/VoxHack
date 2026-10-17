/* nhvtest - drives nethack.dll headlessly to check the API works.
 *
 * usage: nhvtest <datadir> <userdir> [keys...]
 * Each extra argument is sent as input: a single char is a key,
 * "text:..." is a getlin/extcmd answer, "menu:..." a menu answer,
 * "save" sends S then y. The map is printed after every request.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "nhv_api.h"

static void
drain_events(void)
{
    nhv_event ev;

    while (nhv_poll_event(&ev)) {
        switch (ev.kind) {
        case NHV_EV_MESSAGE: printf("MSG: %s\n", ev.text); break;
        case NHV_EV_RAW: printf("RAW: %s\n", ev.text); break;
        case NHV_EV_MISSILE: printf("MISSILE: %s\n", ev.text); break;
        case NHV_EV_SOUND: printf("SOUND: %s\n", ev.text); break;
        case NHV_EV_COMBAT: printf("COMBAT: %s\n", ev.text); break;
        case NHV_EV_RAY: printf("RAYEV: %s\n", ev.text); break;
        case NHV_EV_TEXT_BEGIN: printf("TEXT [%s] {\n", ev.text); break;
        case NHV_EV_TEXT_LINE: printf("  | %s\n", ev.text); break;
        case NHV_EV_TEXT_END: printf("}\n"); break;
        default: break;
        }
    }
}

static void
dump_map(void)
{
    static nhv_loc map[NHV_COLNO * NHV_ROWNO];
    nhv_hero h;
    nhv_mon mons[64];
    int x, y, n, i;

    nhv_get_map(map);
    nhv_get_hero(&h);
    printf("HERO at %d,%d flags=%x\n", h.x, h.y, h.flags);
    for (y = 0; y < NHV_ROWNO; y++) {
        char line[NHV_COLNO + 1];

        for (x = 0; x < NHV_COLNO; x++) {
            nhv_glyph_info gi;

            nhv_get_glyph_info(map[x * NHV_ROWNO + y].glyph, &gi);
            line[x] = (x == h.x && y == h.y) ? '@'
                      : (gi.sym >= 32 && gi.sym < 127) ? (char) gi.sym : '?';
        }
        line[NHV_COLNO] = 0;
        printf("%s\n", line);
    }
    printf("HERO %s the %s @%d,%d %s HP %d/%d Pw %d/%d AC %d XL %d T:%ld\n",
           h.name, h.rank, h.x, h.y, h.level_desc, h.hp, h.hpmax, h.pw,
           h.pwmax, h.ac, h.xlvl, h.moves);
    n = nhv_get_monsters(mons, 64);
    for (i = 0; i < n && i < 64; i++)
        printf("  MON id=%u %s at %d,%d tile=%d flags=%x\n", mons[i].id,
               nhv_mon_name(mons[i].mndx), mons[i].x, mons[i].y,
               mons[i].tile, mons[i].flags);
}

static void
show_request(void)
{
    nhv_request r;
    int i;

    nhv_get_request(&r);
    printf("REQ kind=%d cmd=%d prompt=\"%s\" choices=\"%s\"\n", r.kind,
           r.for_command, r.prompt, r.choices);
    if (r.kind == NHV_REQ_MENU) {
        for (i = 0; i < r.menu_count; i++) {
            nhv_menu_item it;

            if (nhv_get_menu_item(i, &it))
                printf("  [%c]%s %s\n", it.sel ? it.sel : ' ',
                       it.preselected ? "*" : " ", it.text);
        }
    }
}

static void
send_arg(const char *a)
{
    if (!strncmp(a, "text:", 5))
        nhv_send_text(a + 5);
    else if (!strncmp(a, "menu:", 5))
        nhv_send_menu(a + 5);
    else if (!strcmp(a, "esc"))
        nhv_send_key('\033');
    else if (!strcmp(a, "free"))
        nhv_set_freemove(1), nhv_send_key('#'), nhv_send_text("nhvtick");
    else if (!strncmp(a, "tick", 4))
        nhv_send_key('#'), nhv_send_text("nhvtick");
    else if (!strncmp(a, "mstep:", 6) || !strncmp(a, "hmove:", 6)) {
        /* relative: first monster / hero moves by dx,dy */
        int dx, dy;
        nhv_hero h;
        nhv_monfull m[8];
        char buf[64];

        if (sscanf(a + 6, "%d,%d", &dx, &dy) == 2) {
            nhv_get_hero(&h);
            if (a[0] == 'm' && nhv_get_all_monsters(m, 8) > 0) {
                printf("STEP -> %d\n", nhv_move_monster(m[0].id, m[0].x + dx, m[0].y + dy));
                nhv_send_key('#'), nhv_send_text("nhvtick");
            } else if (a[0] == 'h') {
                sprintf(buf, "nhvmove %d %d", h.x + dx, h.y + dy);
                nhv_send_key('#'), nhv_send_text(buf);
            }
        }
    } else if (!strcmp(a, "into")) {
        /* walk into the first monster next to the hero (#nhvmove): they
           share the square; then list who's where */
        static nhv_mon mons[64];
        nhv_hero h;
        int n = nhv_get_monsters(mons, 64), k;
        char buf[64];

        nhv_get_hero(&h);
        for (k = 0; k < n && k < 64; k++)
            if (abs(mons[k].x - h.x) <= 1 && abs(mons[k].y - h.y) <= 1
                && (mons[k].x != h.x || mons[k].y != h.y)) {
                printf("INTO %d,%d (hero %d,%d)\n", mons[k].x, mons[k].y, h.x, h.y);
                sprintf(buf, "nhvmove %d %d", mons[k].x, mons[k].y);
                nhv_send_key('#'), nhv_send_text(buf);
                return;
            }
        printf("INTO: nobody next to the hero\n");
        nhv_send_key('#'), nhv_send_text("nhvtick");
    } else if (!strcmp(a, "mons")) {
        static nhv_mon mons[64];
        nhv_hero h;
        int n = nhv_get_monsters(mons, 64), k;

        nhv_get_hero(&h);
        for (k = 0; k < n && k < 64; k++)
            printf("MON id %u at %d,%d%s\n", mons[k].id, mons[k].x, mons[k].y,
                   (mons[k].x == h.x && mons[k].y == h.y) ? " (sharing the hero's square)" : "");
        nhv_send_key('#'), nhv_send_text("nhvtick");
    } else if (!strcmp(a, "passchain")) {
        /* #nhvpass in its route form: over the first monster next to the
           hero to a free floor square beyond it */
        static nhv_mon mons[64];
        static nhv_loc map[NHV_COLNO * NHV_ROWNO];
        nhv_hero h;
        int n = nhv_get_monsters(mons, 64), k, dx, dy;
        char buf[64];

        nhv_get_hero(&h);
        nhv_get_map(map);
        for (k = 0; k < n && k < 64; k++) {
            int mx = mons[k].x, my = mons[k].y;

            if (abs(mx - h.x) > 1 || abs(my - h.y) > 1 || (mx == h.x && my == h.y))
                continue;
            for (dx = -1; dx <= 1; dx++)
                for (dy = -1; dy <= 1; dy++) {
                    int x = mx + dx, y = my + dy, j, taken = 0;

                    if ((abs(x - h.x) > abs(y - h.y) ? abs(x - h.x) : abs(y - h.y)) != 2 || x < 1 || y < 0
                        || x >= NHV_COLNO || y >= NHV_ROWNO)
                        continue;
                    for (j = 0; j < n; j++)
                        if (mons[j].x == x && mons[j].y == y)
                            taken = 1;
                    if (taken || map[x * NHV_ROWNO + y].typ < 25) /* (ROOM and up) */
                        continue;
                    printf("  passchain over %d,%d to %d,%d (hero %d,%d)\n", mx, my, x, y, h.x, h.y);
                    snprintf(buf, sizeof buf, "nhvpass %d %d %d %d", mx, my, x, y);
                    nhv_send_key('#'), nhv_send_text(buf);
                    return;
                }
        }
        nhv_send_key('#'), nhv_send_text("nhvtick");
    } else if (!strncmp(a, "fight:", 6)) {
        /* fight:name - attack (F + direction) the adjacent monster named */
        static nhv_mon mons[64];
        nhv_hero h;
        int n = nhv_get_monsters(mons, 64), k;
        static const char keys[3][3] = {{'y', 'h', 'b'}, {'k', '.', 'j'}, {'u', 'l', 'n'}};

        nhv_get_hero(&h);
        for (k = 0; k < n && k < 64; k++) {
            int dx = mons[k].x - h.x, dy = mons[k].y - h.y;
            nhv_glyph_info gi;

            if (abs(dx) > 1 || abs(dy) > 1 || (!dx && !dy) || mons[k].mndx < 0)
                continue;
            (void) gi;
            nhv_send_key('F'), nhv_send_key(keys[dx + 1][dy + 1]);
            return;
        }
        nhv_send_key('#'), nhv_send_text("nhvtick");
    } else if (!strcmp(a, "poleset") || !strcmp(a, "pole")) {
        /* poleset: step to a square 2 away from the first hostile monster
           (squared distance 4); pole: #nhvpole at it */
        nhv_hero h;
        nhv_monfull m[16];
        int n = nhv_get_all_monsters(m, 16), k, dx, dy;
        char buf[64];

        nhv_get_hero(&h);
        for (k = 0; k < n && k < 16; k++)
            if (!(m[k].flags & NHV_MF_TAME))
                break;
        if (k < n && k < 16) {
            printf("  target id=%u at %d,%d (hero %d,%d)\n", m[k].id, m[k].x,
                   m[k].y, h.x, h.y);
            if (!strcmp(a, "pole")) {
                snprintf(buf, sizeof buf, "nhvpole %u", m[k].id);
                nhv_send_key('#'), nhv_send_text(buf);
                return;
            }
            for (dx = -1; dx <= 1; dx++)
                for (dy = -1; dy <= 1; dy++) {
                    int x = h.x + dx, y = h.y + dy;

                    if ((x - m[k].x) * (x - m[k].x) + (y - m[k].y) * (y - m[k].y) == 4) {
                        snprintf(buf, sizeof buf, "nhvmove %d %d", x, y);
                        nhv_send_key('#'), nhv_send_text(buf);
                        return;
                    }
                }
        }
        nhv_send_key('#'), nhv_send_text("nhvtick");
    } else if (!strcmp(a, "pass")) {
        /* hop over the first monster next to the hero (#nhvpass) */
        nhv_hero h;
        nhv_monfull m[16];
        int n = nhv_get_all_monsters(m, 16), k;
        char buf[64];

        static nhv_loc map[NHV_COLNO * NHV_ROWNO];
        int dx, dy;

        nhv_get_hero(&h);
        nhv_get_map(map);
        for (k = 0; k < n && k < 16; k++)
            if (abs(m[k].x - h.x) <= 1 && abs(m[k].y - h.y) <= 1)
                /* a floor square two steps away, next to the monster */
                for (dx = -2; dx <= 2; dx++)
                    for (dy = -2; dy <= 2; dy++) {
                        int x = h.x + dx, y = h.y + dy;
                        nhv_glyph_info gi;

                        if ((abs(dx) != 2 && abs(dy) != 2) || x < 1 || y < 0
                            || x >= NHV_COLNO || y >= NHV_ROWNO
                            || abs(x - m[k].x) > 1 || abs(y - m[k].y) > 1)
                            continue;
                        nhv_get_glyph_info(map[x * NHV_ROWNO + y].glyph, &gi);
                        if (gi.sym != '.')
                            continue;
                        sprintf(buf, "nhvpass %d %d", x, y);
                        printf("PASS over %d,%d to %d,%d\n", m[k].x, m[k].y, x, y);
                        nhv_send_key('#'), nhv_send_text(buf);
                        return;
                    }
        printf("PASS: nobody next to the hero\n");
        nhv_send_key('#'), nhv_send_text("nhvtick");
    } else if (!strcmp(a, "missiles")) {
        /* list new missiles; the first one reaches the hero */
        nhv_missile ms[16];
        int n = nhv_get_missiles(ms, 16), k;
        char buf[64];

        for (k = 0; k < n; k++)
            printf("  MISSILE pid=%u from mon %u at %d,%d otyp=%d tile=%d\n",
                   ms[k].pid, ms[k].mon_id, ms[k].x, ms[k].y, ms[k].otyp,
                   ms[k].tile);
        if (n > 0) {
            sprintf(buf, "nhvmhit %u", ms[0].pid);
            nhv_send_key('#'), nhv_send_text(buf);
        } else {
            nhv_send_key('#'), nhv_send_text("nhvtick");
        }
    } else if (!strncmp(a, "step:", 5)) {
        unsigned id; int x, y;
        if (sscanf(a + 5, "%u,%d,%d", &id, &x, &y) == 3)
            printf("STEP -> %d\n", nhv_move_monster(id, x, y));
        nhv_send_key('#'), nhv_send_text("nhvtick");
    } else if (!strcmp(a, "rays")) {
        /* list new rays; the first one ends where it started */
        nhv_ray rs[8];
        int n = nhv_get_rays(rs, 8), k;
        char buf[64];

        for (k = 0; k < n; k++)
            printf("  RAY rid=%u type=%d kind=%d at %d,%d dir %d,%d range %d hero=%d caster=%u\n",
                   rs[k].rid, rs[k].type, rs[k].kind, rs[k].x, rs[k].y,
                   rs[k].dx, rs[k].dy, rs[k].range, rs[k].from_hero,
                   rs[k].caster);
        if (n > 0) {
            sprintf(buf, "nhvrayend %u %d %d", rs[0].rid, rs[0].x, rs[0].y);
            nhv_send_key('#'), nhv_send_text(buf);
        } else {
            nhv_send_key('#'), nhv_send_text("nhvtick");
        }
    } else if (!strcmp(a, "save"))
        nhv_send_key('S'), nhv_send_key('y');
    else
        nhv_send_key((unsigned char) a[0]);
}

int
main(int argc, char **argv)
{
    int st, i;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 3) {
        fprintf(stderr, "usage: nhvtest datadir userdir [inputs...]\n");
        return 2;
    }
    /* NHVTEST_WIZARD=1: debug mode (for #wizgenesis etc.) */
    /* NHVTEST_OPTIONS: the whole OPTIONS line instead (another role...) */
    if (nhv_start(argv[1], argv[2],
                  getenv("NHVTEST_OPTIONS") ? getenv("NHVTEST_OPTIONS")
                  : getenv("NHVTEST_WIZARD")
                  ? "OPTIONS=role:barbarian,race:human,gender:male,"
                    "align:neutral,!autopickup,pettype:none,!tutorial,!legacy,"
                    "!splash_screen,suppress_alert:3.4.3,playmode:debug"
                  : "OPTIONS=role:valkyrie,race:human,gender:female,"
                    "align:neutral,!autopickup,pettype:cat,!tutorial,!legacy,"
                    "!splash_screen,suppress_alert:3.4.3",
                  getenv("NHVTEST_WIZARD") ? "wizard" : "tester") != 0) {
        fprintf(stderr, "nhv_start failed\n");
        return 1;
    }
    for (i = 3;; i++) {
        st = nhv_wait(30000);
        drain_events();
        if (st != NHV_WAITING)
            break;
        dump_map();
        show_request();
        if (i >= argc) {
            printf("(out of inputs)\n");
            return 0;
        }
        printf(">> %s\n", argv[i]);
        send_arg(argv[i]);
    }
    printf("STATE %d exit=%d\n", st, nhv_exit_code());
    return 0;
}
