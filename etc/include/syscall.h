#ifndef _SYSCALL_H
#define _SYSCALL_H 1

// services
#define SRV_core		 0
#define SRV_system  	-1
#define SRV_fs			-2
#define SRV_ui			-3
#define SRV_net			-4
#define SRV_sound		-5
#define SRV_syslog		-6
#define SRV_init		-7
#define SRV_session		-8
#define SRV_prn			-9
#define SRV_NUM     	10
#define SRV_usrfirst	-SRV_NUM
#define SRV_usrlast		-1024
// get function indeces
#include <sys/core.h>
#include <sys/syslog.h>
#include <sys/fs.h>
#include <sys/ui.h>
#include <sys/net.h>

/* async, send a message (non-blocking, except dest queue is full) */
bool_t clsend(pid_t dst, uint64_t func, uint64_t arg0, uint64_t arg1, uint64_t arg2);
/* sync, send a message and receive result (blocking) */
msg_t *clcall(pid_t dst, uint64_t func, uint64_t arg0, uint64_t arg1, uint64_t arg2);
/* async, is there a message? (non-blocking) */
bool_t clismsg();
/* sync, wait until there's a message (blocking) */
msg_t *clrecv();

#endif
