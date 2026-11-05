/* factor.c -- factor the numbers you give it.
 *
 *   ./bm run --args "600851475143 1000000007 1234567890" examples/factor.c
 *
 * Arguments arrive in argv, as on any computer. With none, it factors a few
 * of its own. Each answer is checked by multiplying the factors back together. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

static int factor(const char *s) {
	char *end; uint64_t n = strtoull(s, &end, 10);
	if (*end || n < 2) { printf("%s: not a whole number above 1\n", s); return 1; }
	uint64_t m = n, prod = 1;
	printf("%llu =", (unsigned long long)n);
	const char *sep = " ";
	for (uint64_t p = 2; p * p <= m; p += (p == 2 ? 1 : 2))
		while (m % p == 0) { printf("%s%llu", sep, (unsigned long long)p); sep = " x "; m /= p; prod *= p; }
	if (m > 1) { printf("%s%llu", sep, (unsigned long long)m); prod *= m; }
	printf("%s\n", prod == n ? "" : "   WRONG: the factors do not multiply back");
	return prod != n;
}
int main(int argc, char **argv) {
	static const char *mine[] = { "600851475143", "1000000007", "1234567890" };
	int bad = 0;
	if (argc < 2) {
		printf("no arguments given, so factoring some of my own (try --args \"360 97\")\n\n");
		for (int i = 0; i < 3; i++) bad += factor(mine[i]);
	} else
		for (int i = 1; i < argc; i++) bad += factor(argv[i]);
	printf("\n%s\n", bad ? "something failed" : "correct: every factorisation multiplies back to its number");
	return bad != 0;
}
