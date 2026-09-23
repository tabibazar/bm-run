/* primes.c -- count the primes below ten million, and check the answer.
 *
 * The count is known exactly: there are 664,579 of them. A program that knows
 * its own right answer can tell you whether the machine it ran on got it
 * right, which is the habit worth copying. */
#include <stdio.h>
#include <string.h>

#define N 10000000
static unsigned char composite[N / 8 + 1];              /* one bit per number: 1.25 MB */
#define SET(i) (composite[(i) >> 3] |= (unsigned char)(1u << ((i) & 7)))
#define GET(i) (composite[(i) >> 3] & (1u << ((i) & 7)))

int main(void) {
	for (long p = 2; p * p < N; p++)
		if (!GET(p))
			for (long m = p * p; m < N; m += p) SET(m);
	long count = 0;
	for (long i = 2; i < N; i++) if (!GET(i)) count++;
	printf("primes below %d: %ld\n", N, count);
	printf("%s\n", count == 664579 ? "correct: that is the known value" : "WRONG: the known value is 664579");
	return count == 664579 ? 0 : 1;
}
