/* mandelbrot.c -- the Mandelbrot set, drawn in text. */
#include <stdio.h>

int main(void) {
	/* how quickly a point escapes decides its character; points that never
	   escape are inside the set */
	const char *shade = " .,:;=+*%#";
	const int band[9] = { 2, 3, 4, 6, 9, 14, 22, 40, 80 };
	for (int y = 0; y < 32; y++) {
		for (int x = 0; x < 78; x++) {
			double cr = -2.2 + x * 3.0 / 78, ci = -1.2 + y * 2.4 / 32;
			double zr = 0, zi = 0; int n = 0;
			while (n < 200 && zr * zr + zi * zi < 4) {
				double t = zr * zr - zi * zi + cr;
				zi = 2 * zr * zi + ci; zr = t; n++;
			}
			int k = 0; while (k < 9 && n > band[k]) k++;
			putchar(n == 200 ? '@' : shade[k]);
		}
		putchar('\n');
	}
	return 0;
}
