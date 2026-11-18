#include <immintrin.h>

int main() { return static_cast<int>(sizeof(__m256) / sizeof(float)); }
