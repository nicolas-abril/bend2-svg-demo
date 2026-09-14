// Pixels
// ======

// Writes w by h packed 0xRRGGBB pixels as a P3 text matrix to standard
// output, one pixel per line, straight from the array's lanes.
static char* pixels_write_byte(char* at, uint32_t v) {
  if (v >= 100) {
    *at++ = (char)('0' + v / 100);
    *at++ = (char)('0' + (v / 10) % 10);
  } else if (v >= 10) {
    *at++ = (char)('0' + v / 10);
  }
  *at++ = (char)('0' + v % 10);
  return at;
}

Term pixels_write_run(Env e, Term* f, IoWork* io) {
  Term arr = f[0];
  u64 w = (u64)(uint32_t)f[1];
  u64 h = (u64)(uint32_t)f[2];
  Loc loc = term_loc(arr);
  u64 n = w * h;
  u64 cap = 32 + n * 12;
  char* buf = io_mem(malloc(cap));
  char* at = buf + snprintf(buf, cap, "P3\n%llu %llu\n255\n", (unsigned long long)w, (unsigned long long)h);
  for (u64 i = 0; i < n; i += 1) {
    uint32_t v = (uint32_t)blk_read(e.mem, 0, loc, (u32)i);
    at = pixels_write_byte(at, (v >> 16) & 255);
    *at++ = ' ';
    at = pixels_write_byte(at, (v >> 8) & 255);
    *at++ = ' ';
    at = pixels_write_byte(at, v & 255);
    *at++ = '\n';
  }
  u64 len = (u64)(at - buf);
  int bad = fwrite(buf, 1, len, stdout) != len || fflush(stdout) != 0;
  free(buf);
  if (bad) {
    return io_tup(e, arr, io_fail(e, errno != 0 ? (u32)errno : EIO, NULL));
  }
  return io_tup(e, arr, io_done(e, term_pak(CID_UNIT, 0)));
}

static void __attribute__((constructor)) pixels_write_use(void) {
  io_eff(CID_PIXELS_WRITE, pixels_write_run, 0);
}
