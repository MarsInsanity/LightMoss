// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * hpjackd: route the rk817 codec's audio to the headphones while they are
 * plugged in, and back to the speaker when they come out.
 *
 * The R36S clone's rk817 codec only plays where its "Playback Path" control
 * says, and nothing on the rg351 kernel moves it when the jack is used. The
 * sound card does report the jack, as the SW_HEADPHONE_INSERT switch of its
 * "... Headphones" input device, so this follows that switch: HP while it is
 * on, SPK while it is off.
 *
 * /boot/headphones-invert reverses the switch, for a board whose detect pin
 * reads the other way round (G80CA-MB revisions differ).
 *
 * A C port of BobMoss's hpjackd.py, so the base OS needs no Python.
 */

#include <alsa/asoundlib.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CONTROL      "Playback Path"
#define INVERT_FLAG  "/boot/headphones-invert"
#define RECHECK_MS   5000
#define FIND_TRIES   60

static void logmsg(const char *fmt, ...)
{
	va_list ap;

	fputs("hpjackd: ", stderr);
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fputc('\n', stderr);
}

/* The input device whose name ends in " Headphones": the sound card's jack. */
static int find_jack(char *path, size_t len, char *name, size_t namelen)
{
	DIR *d = opendir("/sys/class/input");
	struct dirent *e;
	int found = 0;

	if (!d)
		return 0;
	while (!found && (e = readdir(d))) {
		char p[512], n[256] = "";
		size_t l;
		FILE *f;

		if (strncmp(e->d_name, "event", 5))
			continue;
		snprintf(p, sizeof(p), "/sys/class/input/%s/device/name", e->d_name);
		f = fopen(p, "r");
		if (!f)
			continue;
		if (fgets(n, sizeof(n), f)) {
			n[strcspn(n, "\n")] = 0;
			l = strlen(n);
			if (l >= 11 && !strcmp(n + l - 11, " Headphones")) {
				snprintf(path, len, "/dev/input/%s", e->d_name);
				snprintf(name, namelen, "%s", n);
				found = 1;
			}
		}
		fclose(f);
	}
	closedir(d);
	return found;
}

static int plugged(int fd)
{
	unsigned char sw[(SW_MAX + 7) / 8] = { 0 };
	int on;

	if (ioctl(fd, EVIOCGSW(sizeof(sw)), sw) < 0)
		return -1;
	on = !!(sw[SW_HEADPHONE_INSERT / 8] & (1 << (SW_HEADPHONE_INSERT % 8)));
	return on != (access(INVERT_FLAG, F_OK) == 0);
}

/* Set the enum control to the item named want; report the old item name. */
static int set_path(const char *want, char *had, size_t hadlen)
{
	snd_ctl_t *ctl = NULL;
	snd_ctl_elem_id_t *id;
	snd_ctl_elem_info_t *info;
	snd_ctl_elem_value_t *val;
	unsigned int i, items, cur;
	int ret = -1;

	had[0] = 0;
	if (snd_ctl_open(&ctl, "hw:0", 0) < 0)
		return -1;

	snd_ctl_elem_id_alloca(&id);
	snd_ctl_elem_info_alloca(&info);
	snd_ctl_elem_value_alloca(&val);

	snd_ctl_elem_id_set_interface(id, SND_CTL_ELEM_IFACE_MIXER);
	snd_ctl_elem_id_set_name(id, CONTROL);
	snd_ctl_elem_info_set_id(info, id);
	if (snd_ctl_elem_info(ctl, info) < 0 ||
	    snd_ctl_elem_info_get_type(info) != SND_CTL_ELEM_TYPE_ENUMERATED)
		goto out;

	snd_ctl_elem_value_set_id(val, id);
	if (snd_ctl_elem_read(ctl, val) < 0)
		goto out;
	cur = snd_ctl_elem_value_get_enumerated(val, 0);

	items = snd_ctl_elem_info_get_items(info);
	for (i = 0; i < items; i++) {
		const char *name;

		snd_ctl_elem_info_set_item(info, i);
		if (snd_ctl_elem_info(ctl, info) < 0)
			continue;
		name = snd_ctl_elem_info_get_item_name(info);
		if (i == cur)
			snprintf(had, hadlen, "%s", name);
		if (!strcmp(name, want)) {
			if (i == cur) {
				ret = 0;
				goto out;
			}
			snd_ctl_elem_value_set_enumerated(val, 0, i);
			ret = snd_ctl_elem_write(ctl, val) < 0 ? -1 : 1;
		}
	}
out:
	snd_ctl_close(ctl);
	return ret;
}

int main(void)
{
	char dev[300] = "", name[256] = "", had[64];
	const char *last = NULL;
	int fd, tries;

	for (tries = 0; tries < FIND_TRIES; tries++) {
		if (find_jack(dev, sizeof(dev), name, sizeof(name)))
			break;
		sleep(1);
	}
	if (!dev[0]) {
		logmsg("no headphone jack input device, nothing to do");
		return 0;
	}

	fd = open(dev, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		logmsg("cannot open %s: %s", dev, strerror(errno));
		return 1;
	}
	logmsg("watching %s (%s)", dev, name);

	for (;;) {
		struct pollfd pfd = { .fd = fd, .events = POLLIN };
		struct input_event ev[16];
		int p = plugged(fd);
		const char *want;

		if (p < 0) {
			logmsg("%s went away", dev);
			return 1;
		}
		want = p ? "HP" : "SPK";
		if (set_path(want, had, sizeof(had)) > 0 && want != last)
			logmsg("headphones %s: %s %s -> %s", p ? "in" : "out",
			       CONTROL, had, want);
		last = want;

		if (poll(&pfd, 1, RECHECK_MS) > 0)
			while (read(fd, ev, sizeof(ev)) > 0)
				;
	}
}
