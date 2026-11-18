#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <algorithm>
#include <string>
#include <vector>

// Forward declaration with intentionally different parameter name
// to trigger readability-inconsistent-declaration-parameter-name,
// which .clang-tidy promotes to an error via WarningsAsErrors.
int string_to_int(const char *str);

// deliberately bad code to trigger clang-tidy warning
int string_to_int(const char *num) { return atoi(num); }

// deliberately insecure code to trigger clang-tidy warning
void ls() { system("ls"); }

// Code with a fixable issue
void remove_from_vector() {
  std::vector<int> xs = {1, 2, 3, 4, 5, 6};
  std::remove(xs.begin(), xs.end(), 4);
}

// Code with a fixable issue
static auto stringCpy(const std::string &str) -> char * {
  char *result = reinterpret_cast<char *>(malloc(str.size()));
  strcpy(result, str.data());
  return result;
}

class dummy {
 public:
  dummy(){};

 private:
  int x;
};

static int compare(int x, int y) {
  if (x < y)
    ;
  { x++; }
  return x;
}

int main() {
  printf("Hello, world!\n");
  compare(3, 4);
  char *a = NULL;
  char *b = 0;
}

