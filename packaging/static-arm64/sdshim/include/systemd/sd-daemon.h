#ifndef SD_DAEMON_SHIM_H
#define SD_DAEMON_SHIM_H
/* Minimal replacement for libsystemd's sd-daemon.h, providing only the
 * sd_notify() call the broker uses. It can be linked statically. */
int sd_notify(int unset_environment, const char *state);
#endif
