// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * lightmoss-volkeys: one input device for the volume rocker.
 *
 * The Retroid Pocket Mini V2 reports Volume Up on a gpio-keys device and
 * Volume Down on the PMIC's "resin" key device. spruce (and PyUI) watch the
 * volume keys on a single node, the first one that reports both. This
 * creates that node, "LightMoss Volume Keys", through uinput and forwards
 * every KEY_VOLUMEUP/KEY_VOLUMEDOWN event of the real devices to it. The
 * real devices are not grabbed: anything reading them still sees the keys.
 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define NAME     "LightMoss Volume Keys"
#define MAX_DEVS 8
#define LONG_BITS (sizeof(long) * 8)
#define NLONGS(x) (((x) + LONG_BITS - 1) / LONG_BITS)

static int has_key(const unsigned long *bits, int key)
{
	return (bits[key / LONG_BITS] >> (key % LONG_BITS)) & 1;
}

/* Opens every event device that reports a volume key (not our own); returns
   how many, and which of the two keys they cover between them. */
static int scan(struct pollfd *fds, int *up, int *down)
{
	DIR *dir = opendir("/dev/input");
	struct dirent *e;
	int n = 0;

	*up = *down = 0;
	if (!dir)
		return 0;
	while ((e = readdir(dir)) && n < MAX_DEVS) {
		unsigned long keys[NLONGS(KEY_CNT)];
		char path[300], name[256] = "";
		int fd, u, d;

		if (strncmp(e->d_name, "event", 5) != 0)
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
		fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		memset(keys, 0, sizeof(keys));
		ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name);
		if (strcmp(name, NAME) == 0 ||
		    ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keys)), keys) < 0) {
			close(fd);
			continue;
		}
		u = has_key(keys, KEY_VOLUMEUP);
		d = has_key(keys, KEY_VOLUMEDOWN);
		if (!u && !d) {
			close(fd);
			continue;
		}
		fprintf(stderr, "lightmoss-volkeys: %s (%s):%s%s\n", path, name,
			u ? " up" : "", d ? " down" : "");
		*up |= u;
		*down |= d;
		fds[n].fd = fd;
		fds[n].events = POLLIN;
		n++;
	}
	closedir(dir);
	return n;
}

static int emit(int fd, int type, int code, int value)
{
	struct input_event ev;

	memset(&ev, 0, sizeof(ev));
	ev.type = type;
	ev.code = code;
	ev.value = value;
	return write(fd, &ev, sizeof(ev)) == sizeof(ev) ? 0 : -1;
}

int main(void)
{
	struct pollfd fds[MAX_DEVS];
	struct uinput_setup setup;
	int n = 0, up = 0, down = 0, tries, i, out;

	/* The key devices may still be probing: wait for both keys, up to 30 s,
	   then go on with what there is. */
	for (tries = 0; tries < 30; tries++) {
		n = scan(fds, &up, &down);
		if (up && down)
			break;
		for (i = 0; i < n; i++)
			close(fds[i].fd);
		n = 0;
		sleep(1);
	}
	if (n == 0)
		n = scan(fds, &up, &down);
	if (n == 0) {
		fprintf(stderr, "lightmoss-volkeys: no device reports a volume key\n");
		return 1;
	}

	out = open("/dev/uinput", O_WRONLY | O_CLOEXEC);
	if (out < 0) {
		perror("lightmoss-volkeys: /dev/uinput");
		return 1;
	}
	ioctl(out, UI_SET_EVBIT, EV_KEY);
	ioctl(out, UI_SET_KEYBIT, KEY_VOLUMEUP);
	ioctl(out, UI_SET_KEYBIT, KEY_VOLUMEDOWN);
	memset(&setup, 0, sizeof(setup));
	setup.id.bustype = BUS_VIRTUAL;
	setup.id.vendor = 0x4c4d;  /* "LM" */
	setup.id.product = 0x0001;
	snprintf(setup.name, sizeof(setup.name), "%s", NAME);
	if (ioctl(out, UI_DEV_SETUP, &setup) < 0 || ioctl(out, UI_DEV_CREATE) < 0) {
		perror("lightmoss-volkeys: uinput");
		return 1;
	}

	for (;;) {
		if (poll(fds, n, -1) < 0) {
			if (errno == EINTR)
				continue;
			perror("lightmoss-volkeys: poll");
			return 1;
		}
		for (i = 0; i < n; i++) {
			struct input_event evs[16];
			ssize_t len;
			size_t j;

			if (fds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
				fprintf(stderr, "lightmoss-volkeys: a key device went away\n");
				return 1;  /* systemd restarts us, and we rescan */
			}
			if (!(fds[i].revents & POLLIN))
				continue;
			len = read(fds[i].fd, evs, sizeof(evs));
			if (len <= 0)
				continue;
			for (j = 0; j < (size_t)len / sizeof(evs[0]); j++) {
				if (evs[j].type != EV_KEY ||
				    (evs[j].code != KEY_VOLUMEUP && evs[j].code != KEY_VOLUMEDOWN))
					continue;
				emit(out, EV_KEY, evs[j].code, evs[j].value);
				emit(out, EV_SYN, SYN_REPORT, 0);
			}
		}
	}
}
