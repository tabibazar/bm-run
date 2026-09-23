#include <stdio.h>
int main(void) { printf("about to loop forever\n"); for (volatile unsigned long i = 0; ; i++) {} }
