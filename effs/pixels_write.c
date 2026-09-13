// Pixels
// ======

// Writes w by h packed 0xRRGGBB pixels as a P3 text matrix to standard
// output, one pixel per line, straight from the array's lanes.
Term pixels_write_run(Env e, Term* f, IoWork* io) {
  Term arr = f[0];
  u64 w = (u64)(uint32_t)f[1];
  u64 h = (u64)(uint32_t)f[2];
  Loc loc = term_loc(arr);
  u64 n = w * h;
  u64 cap = 32 + n * 12;
  char* buf = io_mem(malloc(cap));
  u64 at = (u64)snprintf(buf, cap, "P3\n%llu %llu\n255\n", (unsigned long long)w, (unsigned long long)h);
  for (u64 i = 0; i < n; i += 1) {
    uint32_t v = (uint32_t)blk_read(e.mem, 0, loc, (u32)i);
    at += (u64)snprintf(buf + at, cap - at, "%u %u %u\n", (v >> 16) & 255, (v >> 8) & 255, v & 255);
  }
  int bad = fwrite(buf, 1, at, stdout) != at || fflush(stdout) != 0;
  free(buf);
  if (bad) {
    return io_tup(e, arr, io_fail(e, io_sys_fall(errno != 0 ? (uint32_t)errno : EIO)));
  }
  return io_tup(e, arr, io_done(e, term_pak(CID_UNIT, 0)));
}

static void __attribute__((constructor)) pixels_write_use(void) {
  io_eff(FID_PIXELS_WRITE, CID_PIXELS_WRITE, pixels_write_run, 0);
}
