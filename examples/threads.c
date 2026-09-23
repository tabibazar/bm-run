/* threads.c -- four threads on a machine with one CPU and no operating system.
 * BareMetal has no scheduler of its own, so its C library provides threads.
 * Each thread sums a quarter of the numbers from 1 to 40 million. */
#include <stdio.h>
#include <stdint.h>
#include <pthread.h>

#define N 40000000ULL
#define T 4
static uint64_t partial[T];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t shared_count;

static void *work(void *arg) {
	int id = (int)(intptr_t)arg;
	uint64_t lo = id * (N / T) + 1, hi = (id + 1) * (N / T), s = 0;
	for (uint64_t i = lo; i <= hi; i++) s += i;
	partial[id] = s;
	for (int i = 0; i < 100000; i++) { pthread_mutex_lock(&lock); shared_count++; pthread_mutex_unlock(&lock); }
	return NULL;
}
int main(void) {
	pthread_t th[T];
	for (int i = 0; i < T; i++) pthread_create(&th[i], NULL, work, (void *)(intptr_t)i);
	for (int i = 0; i < T; i++) pthread_join(th[i], NULL);
	uint64_t total = 0;
	for (int i = 0; i < T; i++) { printf("thread %d summed %llu\n", i, (unsigned long long)partial[i]); total += partial[i]; }
	printf("total                %llu\n", (unsigned long long)total);
	printf("shared counter       %llu (each thread added 100,000 under a mutex)\n", (unsigned long long)shared_count);
	int ok = total == N * (N + 1) / 2 && shared_count == T * 100000ULL;
	printf("%s\n", ok ? "correct: the total is n(n+1)/2 and no increment was lost" : "WRONG");
	return !ok;
}
