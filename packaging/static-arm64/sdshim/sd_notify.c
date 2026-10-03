/* Minimal sd_notify(3): send state as a datagram to $NOTIFY_SOCKET.
 * Supports filesystem and abstract ('@') sockets, like libsystemd. */
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include "systemd/sd-daemon.h"

int sd_notify(int unset_environment, const char *state)
{
	const char *path = getenv("NOTIFY_SOCKET");
	struct sockaddr_un sa;
	size_t len;
	socklen_t salen;
	int fd, rc = 0;

	if(!path || !state) goto out;
	len = strlen(path);
	if(len < 2 || len >= sizeof(sa.sun_path) || (path[0] != '/' && path[0] != '@')){
		rc = -EINVAL;
		goto out;
	}
	memset(&sa, 0, sizeof(sa));
	sa.sun_family = AF_UNIX;
	memcpy(sa.sun_path, path, len);
	if(path[0] == '@') sa.sun_path[0] = '\0';
	salen = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + len + (path[0] == '/' ? 1 : 0));

	fd = socket(AF_UNIX, SOCK_DGRAM|SOCK_CLOEXEC, 0);
	if(fd < 0){
		rc = -errno;
		goto out;
	}
	if(sendto(fd, state, strlen(state), MSG_NOSIGNAL, (struct sockaddr *)&sa, salen) < 0){
		rc = -errno;
	}else{
		rc = 1;
	}
	close(fd);
out:
	if(unset_environment) unsetenv("NOTIFY_SOCKET");
	return rc;
}
