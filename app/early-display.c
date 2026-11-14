/*
 * early-display-service: simulated automotive display.
 * Prints a READY banner with uptime to the console and to /dev/kmsg
 * (so the marker appears in dmesg next to the kernel log), then exits.
 * Grep marker for benchmarks: "AUTOMOTIVE DISPLAY READY"
 */
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
	char up[32] = "?";
	char line[96];
	FILE *f = fopen("/proc/uptime", "r");
	int fd;

	if (f) {
		if (fscanf(f, "%31s", up) != 1)
			strcpy(up, "?");
		fclose(f);
	}

	snprintf(line, sizeof(line), "AUTOMOTIVE DISPLAY READY (uptime=%s s)", up);

	puts("\n============================================");
	printf(" %s\n", line);
	puts("============================================");
	fflush(stdout);

	fd = open("/dev/kmsg", O_WRONLY);
	if (fd >= 0) {
		char k[128];

		snprintf(k, sizeof(k), "<6>early-display: %s", line);
		(void)!write(fd, k, strlen(k));
		close(fd);
	}

	return 0;
}
