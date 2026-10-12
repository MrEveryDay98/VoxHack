/* nhv_main.c - NetHack startup/shutdown when running as nethack.dll.
 *
 * Adapted from sys/windows/windmain.c: same startup sequence, minus the
 * console and GUI handling. The game runs on a thread created by
 * nhv_api.c; nethack_exit() unwinds back to that thread's entry point
 * with longjmp instead of terminating the host process.
 */
#include "win32api.h"
#include "hack.h"
#include "dlb.h"
#include <sys/stat.h>
#include <errno.h>
#include <setjmp.h>
#include "nhv_internal.h"

/* globals that the rest of the Windows port expects */
char orgdir[PATHLEN];
boolean getreturn_enabled;
int windows_startup_state = 0;
HANDLE hStdOut;
char default_window_sys[7] = "shim";
int GUILaunched = 0;

static jmp_buf nhv_exit_jmp;
static int nhv_exit_status;
static char nhv_datadir[PATHLEN], nhv_userdir[PATHLEN];

static int eraseoldlocks(void);

void
nhv_set_dirs(const char *datadir, const char *userdir)
{
    Snprintf(nhv_datadir, sizeof nhv_datadir, "%s", datadir);
    Snprintf(nhv_userdir, sizeof nhv_userdir, "%s", userdir);
    append_slash(nhv_datadir);
    append_slash(nhv_userdir);
}

/* Replaces the windsys.c version: everything lives in two folders. */
void
set_default_prefix_locations(const char *programPath UNUSED)
{
    gf.fqn_prefix[SYSCONFPREFIX] = nhv_datadir;
    gf.fqn_prefix[DATAPREFIX] = nhv_datadir;
    gf.fqn_prefix[CONFIGPREFIX] = nhv_userdir;
    gf.fqn_prefix[HACKPREFIX] = nhv_userdir;
    gf.fqn_prefix[SAVEPREFIX] = nhv_userdir;
    gf.fqn_prefix[LEVELPREFIX] = nhv_userdir;
    gf.fqn_prefix[BONESPREFIX] = nhv_userdir;
    gf.fqn_prefix[SCOREPREFIX] = nhv_userdir;
    gf.fqn_prefix[LOCKPREFIX] = nhv_userdir;
    gf.fqn_prefix[TROUBLEPREFIX] = nhv_userdir;
}

/* Replaces the windsys.c version: unwind to the game thread's entry. */
ATTRNORETURN void
nethack_exit(int code)
{
    nhv_exit_status = code;
    longjmp(nhv_exit_jmp, 1);
}

int
nhv_game_thread_main(const char *rcfile, const char *name)
{
    static char *argv[] = { "nethack", 0 };
    int argc = 1;
    boolean resuming = FALSE;
    NHFILE *nhfp;
    char fnamebuf[BUFSZ], encodedfnamebuf[BUFSZ], failbuf[BUFSZ];
    int getlock_result;

    if (setjmp(nhv_exit_jmp))
        return nhv_exit_status;

    early_init(argc, argv);
    gh.hname = "NetHack";
    set_default_prefix_locations(argv[0]);
    choose_windows("shim");

    initoptions_init();
    set_default_prefix_locations(argv[0]);
    if (rcfile && *rcfile)
        gc.cmdline_rcfile = dupstr(rcfile);
    initoptions();
    if (name && *name)
        Snprintf(svp.plname, sizeof svp.plname, "%s", name);

    check_recordfile((char *) 0);
    for (int i = 0; i < PREFIX_COUNT; i++)
        fqn_prefix_locked[i] = TRUE;
    if (!validate_prefix_locations(failbuf)) {
        raw_printf("Invalid directory locations: %s", failbuf);
        nethack_exit(EXIT_FAILURE);
    }

    init_nhwindows(&argc, argv);
    if (!dlb_init())
        error("Unable to open the NetHack data file \"%s\".", DLBFILE);

    u.uhp = 1; /* prevent RIP on early quits */
    u.ux = 0;  /* prevent flush_screen() */
    iflags.use_background_glyph = FALSE;

    plnamesuffix();
    set_playmode();
    iflags.renameallowed = FALSE;
    Sprintf(fnamebuf, "%s", svp.plname);
    (void) fname_encode(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_-.", '%',
        fnamebuf, encodedfnamebuf, BUFSZ);
    Snprintf(gl.lock, sizeof gl.lock, "%s", encodedfnamebuf);
    if ((getlock_result = getlock()) == 0)
        nethack_exit(EXIT_SUCCESS);
    if (getlock_result < 0)
        set_savefile_name(TRUE);

    nhfp = create_levelfile(0, (char *) 0);
    if (!nhfp) {
        raw_print("Cannot create lock file");
    } else {
        svh.hackpid = GetCurrentProcessId();
        (void) write(nhfp->fd, (genericptr_t) &svh.hackpid,
                     sizeof svh.hackpid);
        close_nhfile(nhfp);
    }

    vision_init();
    init_sound_disp_gamewindows();

    if ((getlock_result != -1) && (nhfp = restore_saved_game()) != 0) {
        pline("Restoring save file...");
        mark_synch();
        if (dorecover(nhfp))
            resuming = TRUE;
        if (program_state.in_self_recover) {
            program_state.in_self_recover = FALSE;
            set_savefile_name(TRUE);
        }
    }
    if (!resuming) {
        player_selection();
        newgame();
    }
    moveloop(resuming);
    nethack_exit(EXIT_SUCCESS);
    /*NOTREACHED*/
    return 0;
}

boolean
authorize_wizard_mode(void)
{
    return !strcmp(svp.plname, WIZARD_NAME);
}

boolean
authorize_explore_mode(void)
{
    return TRUE;
}

#ifdef PORT_HELP
void
port_help(void)
{
    display_file(PORT_HELP, 1);
}
#endif

static int
eraseoldlocks(void)
{
    int i;

    for (i = 1; i <= MAXDUNGEON * MAXLEVEL + 1; i++) {
        set_levelfile_name(gl.lock, i);
        (void) unlink(fqname(gl.lock, LEVELPREFIX, 0));
    }
    set_levelfile_name(gl.lock, 0);
    if (unlink(fqname(gl.lock, LEVELPREFIX, 0)))
        return 0;
    return 1;
}

/* A leftover lock means the last session crashed mid-game: always try to
 * recover it (no prompt), falling back to discarding it.
 * Returns 1 if the old game was recovered/none existed, -1 if discarded. */
int
getlock(void)
{
    int fd, result = 1;
    const char *fq_lock;

    if (!lock_file(HLOCK, LOCKPREFIX, 10))
        error("Quitting.");

    set_levelfile_name(gl.lock, 0);
    fq_lock = fqname(gl.lock, LEVELPREFIX, 1);
    if ((fd = open(fq_lock, 0)) == -1) {
        if (errno == ENOENT)
            goto gotlock;
        unlock_file(HLOCK);
        raw_printf("Cannot open %s", fq_lock);
        nethack_exit(EXIT_FAILURE);
    }
    (void) nhclose(fd);

    if (recover_savefile()) {
        raw_print("Recovered a game interrupted by a crash.");
    } else if (eraseoldlocks()) {
        raw_print("Could not recover the interrupted game; starting fresh.");
        result = -1;
    } else {
        unlock_file(HLOCK);
        raw_print("Couldn't remove the old game's files.");
        return 0;
    }

gotlock:
    fd = creat(fq_lock, FCMASK);
    unlock_file(HLOCK);
    if (fd == -1) {
        raw_printf("cannot create lock file %s", fq_lock);
    } else {
        if (write(fd, (char *) &svh.hackpid, sizeof svh.hackpid)
            != sizeof svh.hackpid)
            error("cannot write lock (%s)", fq_lock);
        (void) nhclose(fd);
    }
    return result;
}

boolean
file_newer(const char *a_path, const char *b_path)
{
    struct stat a_sb = { 0 }, b_sb = { 0 };

    if (stat(a_path, &a_sb))
        return FALSE;
    if (stat(b_path, &b_sb))
        return TRUE;
    return difftime(a_sb.st_mtime, b_sb.st_mtime) > 0;
}

/*nhv_main.c*/
