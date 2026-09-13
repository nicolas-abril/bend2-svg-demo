// Bytes
// =====

// The whole file as a string with one character per byte (code 0..255),
// so binary data survives unlike the UTF-8 decoding File.read applies.
static Term bytes_read_string(Env e, const uint8_t* p, u64 n) {
  Term s = term_pak(CID_SNIL, 0);
  while (n > 0) {
    n -= 1;
    s = io_node(e, CID_SCON, (u64)p[n], s, IO_HOTS & 1);
  }
  return s;
}

Term bytes_read_raw_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* path = io_cstr(e, f[0], &n);
  FILE* fp = io_nul(path, n) ? NULL : fopen(path, "rb");
  if (fp == NULL) {
    free(path);
    return io_fail(e, io_sys_fall(errno != 0 ? (uint32_t)errno : ENOENT));
  }
  free(path);
  u64 cap = 1 << 16;
  u64 len = 0;
  uint8_t* buf = io_mem(malloc(cap));
  for (;;) {
    if (len == cap) {
      cap *= 2;
      buf = io_mem(realloc(buf, cap));
    }
    size_t got = fread(buf + len, 1, cap - len, fp);
    if (got == 0) {
      break;
    }
    len += got;
  }
  fclose(fp);
  Term s = bytes_read_string(e, buf, len);
  free(buf);
  return io_done(e, s);
}

static void __attribute__((constructor)) bytes_read_raw_use(void) {
  io_eff(FID_BYTES_READ_RAW, CID_BYTES_READ_RAW, bytes_read_raw_run, 0);
}
