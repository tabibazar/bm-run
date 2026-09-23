/* life.c -- Conway's Game of Life, and a check that it is right.
 *
 * A glider is five cells that crawl one square diagonally every four
 * generations. After 40 generations it must be exactly 10 squares away,
 * with the same shape. */
#include <stdio.h>
#include <string.h>

#define W 24
#define H 16
static unsigned char g[H][W], n[H][W];

static void step(void) {
	for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
		int c = 0;
		for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++)
			if (dy || dx) c += g[(y + dy + H) % H][(x + dx + W) % W];
		n[y][x] = c == 3 || (c == 2 && g[y][x]);
	}
	memcpy(g, n, sizeof g);
}
static void show(int gen) {
	printf("generation %d\n", gen);
	for (int y = 0; y < H; y++) { for (int x = 0; x < W; x++) putchar(g[y][x] ? '#' : '.'); putchar('\n'); }
	putchar('\n');
}
int main(void) {
	static const int glider[5][2] = { {0,1}, {1,2}, {2,0}, {2,1}, {2,2} };   /* {row, col} */
	for (int i = 0; i < 5; i++) g[1 + glider[i][0]][1 + glider[i][1]] = 1;
	show(0);
	for (int i = 0; i < 40; i++) step();
	show(40);
	int ok = 1, alive = 0;
	for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) alive += g[y][x];
	for (int i = 0; i < 5; i++) ok &= g[11 + glider[i][0]][11 + glider[i][1]];
	ok &= alive == 5;
	printf("%s\n", ok ? "correct: the glider moved exactly 10 squares diagonally and kept its shape"
	                  : "WRONG: the glider is not where it must be");
	return !ok;
}
