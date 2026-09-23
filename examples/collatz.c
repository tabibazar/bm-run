/* collatz.c -- the Collatz conjecture, tested for every number below a million.
 *
 * Start anywhere. If the number is even, halve it; if odd, triple it and add
 * one. Nobody has proved you always reach 1, but every number ever tried does.
 * Which start below a million takes the longest? (The answer is known: 837,799,
 * with a chain of 525 numbers.) */
#include <stdio.h>
#include <stdint.h>

#define LIMIT 1000000
static uint16_t cache[LIMIT];   /* chain length for each start, filled as we go */

int main(void) {
	uint32_t best = 1, best_len = 1;
	uint64_t highest = 0;
	cache[1] = 1;
	for (uint32_t s = 2; s < LIMIT; s++) {
		uint64_t n = s; uint32_t steps = 0;
		while (n >= LIMIT || cache[n] == 0) {
			n = (n & 1) ? 3 * n + 1 : n / 2; steps++;
			if (n > highest) highest = n;
		}
		uint32_t len = steps + cache[n];
		cache[s] = (uint16_t)len;
		if (len > best_len) { best_len = len; best = s; }
	}
	printf("every start below %d reaches 1\n", LIMIT);
	printf("the longest chain starts at %u and has %u numbers\n", best, best_len);
	printf("the highest number any chain climbs to: %llu\n", (unsigned long long)highest);
	int ok = best == 837799 && best_len == 525;
	printf("%s\n", ok ? "correct: that is the known answer" : "WRONG: the known answer is 837799 with 525 numbers");
	return !ok;
}
