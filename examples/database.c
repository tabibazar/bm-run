/* database.c -- a real SQL database, SQLite, on a machine with no operating
 * system. It lives in memory, holds the planets, and checks Kepler's third law:
 * the square of a planet's year is the cube of its distance from the Sun. */
#include <stdio.h>
#include <sqlite3.h>

static sqlite3 *db;
static int run(const char *sql) {
	char *err = NULL;
	if (sqlite3_exec(db, sql, NULL, NULL, &err) != SQLITE_OK) { printf("SQL error: %s\n", err); sqlite3_free(err); return 1; }
	return 0;
}
int main(void) {
	printf("SQLite %s, in memory\n\n", sqlite3_libversion());
	if (sqlite3_open(":memory:", &db) != SQLITE_OK) { printf("could not open a database\n"); return 1; }
	if (run("CREATE TABLE planets (name TEXT, au REAL, years REAL);"
	        "INSERT INTO planets VALUES"
	        " ('Mercury', 0.3871, 0.2408), ('Venus', 0.7233, 0.6152), ('Earth', 1.0000, 1.0000),"
	        " ('Mars', 1.5237, 1.8808), ('Jupiter', 5.2029, 11.862), ('Saturn', 9.5370, 29.457),"
	        " ('Uranus', 19.189, 84.011), ('Neptune', 30.070, 164.79);")) return 1;

	sqlite3_stmt *q;
	sqlite3_prepare_v2(db, "SELECT name, au, years, years * years / (au * au * au) FROM planets ORDER BY au", -1, &q, NULL);
	printf("%-8s %9s %9s   %s\n", "planet", "distance", "year", "year^2 / distance^3");
	double lo = 9, hi = 0; int n = 0;
	while (sqlite3_step(q) == SQLITE_ROW) {
		double r = sqlite3_column_double(q, 3);
		printf("%-8s %6.3f AU %6.2f yr   %.4f\n", sqlite3_column_text(q, 0), sqlite3_column_double(q, 1), sqlite3_column_double(q, 2), r);
		if (r < lo) lo = r; if (r > hi) hi = r; n++;
	}
	sqlite3_finalize(q);
	sqlite3_close(db);
	int ok = n == 8 && lo > 0.99 && hi < 1.01;
	printf("\n%s\n", ok ? "correct: the ratio is 1 for every planet, as Kepler found in 1619"
	                    : "WRONG: the ratio should be 1 for every planet");
	return !ok;
}
