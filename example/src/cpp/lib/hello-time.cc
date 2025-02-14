#include "hello-time.h"
// warning: included header ctime is not used directly [misc-include-cleaner]
#include <get/get-time.h>

#include <ctime>
#include <iostream>

// Deliberately bad code
void print_localtime() {
  char* localtime = get_localtime();
  // warning: do not call c-style vararg functions
  // [cppcoreguidelines-pro-type-vararg,hicpp-vararg]
  printf("%s\n", localtime);

  // local defines are added to clang-tidy so it can compile
  static const char* str = LOCAL_DEFINE_IS_DEFINED;
  printf("%s\n   ", str);
}
