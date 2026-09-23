/* facts.c -- check what the README promises works on the machine. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

static int has_rdrand(void) {
	unsigned a, b, c, d;
	__asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(1), "c"(0));
	return (c >> 30) & 1;
}
static int rdrand64(uint64_t *v) {
	unsigned char ok;
	__asm__ volatile("rdrand %0; setc %1" : "=r"(*v), "=qm"(ok));
	return ok;
}
int main(void) {
	int fails = 0;
	time_t t = time(NULL);
	printf("time: %lld (%s)\n", (long long)t, t > 1767225600 ? "after 2026-01-01, plausible" : "IMPLAUSIBLE");
	if (t <= 1767225600) fails++;
	if (has_rdrand()) {
		uint64_t a = 0, b = 0; int ok = rdrand64(&a) && rdrand64(&b);
		printf("rdrand: %s, two draws %s\n", ok ? "works" : "FAILED", a != b ? "differ" : "EQUAL");
		if (!ok || a == b) fails++;
	} else { printf("rdrand: NOT ADVERTISED by cpuid\n"); fails++; }
	size_t n = 8u << 20; unsigned char *p = malloc(n);
	if (!p) { printf("malloc 8 MiB: FAILED\n"); fails++; }
	else {
		for (size_t i = 0; i < n; i++) p[i] = (unsigned char)(i * 131u);
		uint64_t s = 0; for (size_t i = 0; i < n; i++) s += p[i];
		uint64_t want = 0; for (size_t i = 0; i < 256; i++) want += (unsigned char)(i * 131u);
		want *= n / 256;
		printf("malloc 8 MiB: %s\n", s == want ? "works, contents checked" : "CONTENTS WRONG");
		if (s != want) fails++;
		free(p);
	}
	printf("%s\n", fails ? "FACTS FAILED" : "facts ok");
	return fails;
}
