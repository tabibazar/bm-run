#include <stdio.h>
int main(void) { printf("about to write through a null pointer\n"); fflush(stdout); *(volatile int *)0 = 42; printf("still here after the write\n"); return 0; }
