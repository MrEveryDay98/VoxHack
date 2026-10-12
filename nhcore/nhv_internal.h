/* nhv_internal.h - shared between the nhcore source files (not exported). */
#ifndef NHV_INTERNAL_H
#define NHV_INTERNAL_H

#include "nhv_api.h"

/* one queued piece of host input */
enum nhv_qitem_type { NHV_Q_KEY = 1, NHV_Q_TEXT, NHV_Q_MENU };
typedef struct nhv_qitem {
    int type;
    int key;
    char str[256];
} nhv_qitem;

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
