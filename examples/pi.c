/* pi.c -- the first 1,000 digits of pi, one at a time, with only integers.
 *
 * This is the spigot algorithm of Rabinowitz and Wagon (1995): it produces
 * digits in order without ever storing pi as a number. The first 100 digits
 * are checked against the known value. */
#include <stdio.h>
#include <string.h>

#define N 1000
static int a[N * 10 / 3 + 1];
static char out[N + 2];
static int pos;
static void emit(int d) { if (pos < N + 1) out[pos++] = (char)('0' + d); }

int main(void) {
	int len = N * 10 / 3 + 1, nines = 0, predigit = 0;
	for (int i = 0; i < len; i++) a[i] = 2;
	for (int j = 1; j <= N + 1; j++) {
		int q = 0;
		for (int i = len; i > 0; i--) {
			int x = 10 * a[i - 1] + q * i;
			a[i - 1] = x % (2 * i - 1);
			q = x / (2 * i - 1);
		}
		a[0] = q % 10; q /= 10;
		if (q == 9) nines++;
		else if (q == 10) { emit(predigit + 1); for (int k = 0; k < nines; k++) emit(0); predigit = 0; nines = 0; }
		else { if (j > 1) emit(predigit); predigit = q; for (int k = 0; k < nines; k++) emit(9); nines = 0; }
	}
	out[N] = 0;
	printf("pi = %c.", out[0]);
	for (int i = 1; i < N; i++) { putchar(out[i]); if (i % 50 == 0) printf("\n     "); }
	printf("\n\n");
	const char *known = "31415926535897932384626433832795028841971693993751"
	                    "05820974944592307816406286208998628034825342117067"
	                    "9";
	int ok = strncmp(out, known, 101) == 0;
	printf("%s\n", ok ? "correct: the first 100 decimals match the known value" : "WRONG: the first 100 decimals do not match");
	return !ok;
}
