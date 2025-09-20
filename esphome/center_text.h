#include "esphome/components/display/display_buffer.h"
#include "esphome/components/font/font.h"
#include <cstdarg>

void center_text(esphome::display::Display &display, int y_position, esphome::font::Font *font_id, const char *format, ...) {
  char buf[512];
  va_list args;
  va_start(args, format);
  vsnprintf(buf, sizeof(buf), format, args);
  va_end(args);

  int x1, y1, text_width, text_height;
  display.get_text_bounds(0, 0, buf, font_id, esphome::display::TextAlign::TOP_LEFT, &x1, &y1, &text_width, &text_height);
  int x_position = (128 - text_width) / 2;

  display.print(x_position, y_position, font_id, buf);
}
