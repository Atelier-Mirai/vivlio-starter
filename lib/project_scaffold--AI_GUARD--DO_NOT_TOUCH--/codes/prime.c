#include <stdio.h>
#include <math.h>
#include <stdbool.h>

bool isPrime(int num) {
    if (num <= 1) return false;
    for (int i = 2; i <= sqrt(num); i++) {
        if (num % i == 0) return false;
    }
    return true;
}

int main() {
    printf("1から100までの素数:\n");
    for (int num = 1; num <= 100; num++) {
        if (isPrime(num)) {
            printf("%d ", num);
        }
    }
    printf("\n");
    return 0;
}