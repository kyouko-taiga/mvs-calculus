#include <chrono>

extern "C" double mvs_uptime_nanoseconds() {
  auto clock = std::chrono::high_resolution_clock::now();
  auto delta = std::chrono::duration_cast<std::chrono::nanoseconds>(clock.time_since_epoch());
  return delta.count();
}
