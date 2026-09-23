/* machine.c -- what does a computer with no operating system look like from
 * the inside? Your program is the only thing running on it. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <errno.h>

static void cpu_brand(char out[49]) {
	memset(out, 0, 49);
#if defined(__x86_64__)
	unsigned r[12];
	for (unsigned i = 0; i < 3; i++)
		__asm__ volatile("cpuid" : "=a"(r[4*i]), "=b"(r[4*i+1]), "=c"(r[4*i+2]), "=d"(r[4*i+3]) : "a"(0x80000002u + i), "c"(0));
	memcpy(out, r, 48);
	char *p = out; while (*p == ' ') p++; memmove(out, p, strlen(p) + 1);
#else
	strcpy(out, "(not an x86-64 CPU)");
#endif
}
int main(void) {
	char brand[49]; cpu_brand(brand);
	printf("processor:   %s\n", brand);

	time_t t = time(NULL); char when[64];
	strftime(when, sizeof when, "%Y-%m-%d %H:%M:%S UTC", gmtime(&t));
	printf("clock:       %s\n", when);

	/* How much memory can we get? Ask for less and less until it works. */
	size_t mb = 16;
	void *p = NULL;
	while (mb > 0 && !(p = malloc(mb << 20))) mb--;
	printf("memory:      the biggest single malloc() that succeeds is %zu MiB of the machine's 16\n", mb);
	printf("             (any 'out of memory' lines above are the C library turning down the bigger requests)\n");
	free(p);

	/* One address space: your code, your stack and your heap sit side by side. */
	int local = 0; void *heap = malloc(16);
	printf("addresses:   main() at %p, a local variable at %p, the heap at %p\n", (void *)main, (void *)&local, heap);
	free(heap);

	FILE *f = fopen("/etc/os-release", "r");
	if (f) { printf("os-release:  present (the cloud attached a disk)\n"); fclose(f); }
	else printf("os-release:  not found (%s): there is no operating system to describe\n", strerror(errno));

	printf("\nNo processes, no scheduler, no shell. When main() returns, this machine stops.\n");
	return 0;
}
