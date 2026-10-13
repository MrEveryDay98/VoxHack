/* nhv_internal.h - shared between the nhcore source files (not exported). */
#ifndef NHV_INTERNAL_H
#define NHV_INTERNAL_H

#include "nhv_api.h"

/* one queued piece of host input */
enum nhv_qitem_type { NHV_Q_KEY = 1, NHV_Q_TEXT, NHV_Q_MENU, NHV_Q_CALL };
enum nhv_call_id { NHV_CALL_MON_STEP = 1 };
typedef struct nhv_qitem {
    int type;
    int key;
    char str[256];
    int args[4];    /* NHV_Q_CALL: call id is 'key' */
} nhv_qitem;

/* nhv_free.c */
#define NHV_MAXARGS 16
extern int nhv_cmd_args[NHV_MAXARGS];
int nhv_exec_mon_step(unsigned id, int x, int y);

/* nhv_main.c */
void nhv_set_dirs(const char *datadir, const char *userdir);
int nhv_game_thread_main(const char *rcfile, const char *name);

/* nhv_api.c -- called from the game thread */
/* Pop the next input item; if none is queued, publish *req, mark the
 * game WAITING and block until the host sends something. */
void nhv_wait_input(const nhv_request *req, nhv_qitem *out);
void nhv_push_event(int kind, int attr, const char *text);
/* The menu currently being offered to the host (owned by nhv_win.c). */
int nhv_win_menu_item(int index, nhv_menu_item *out);
/* last message line, used as the prompt for bare key requests */
const char *nhv_win_last_message(void);

#endif /* NHV_INTERNAL_H */
