// Bytes
// =====

// The whole file as a Bin.Bytes value: a balanced tree of packed byte leaves
// over the next power of two, with zero leaves standing in for the unused
// tail, plus the byte count and that capacity. Built here so no Bend-side
// conversion touches every byte.
static Term bytes_read_tree(Env e, const uint8_t* p, u64 n, u64 lo, u64 cap) {
  if (lo >= n) {
    return term_pak(CID_BIN_BYTEFLAT, 0);
  }
  if (cap == 1) {
    return term_pak(CID_BIN_BYTEFLAT, (u64)p[lo]);
  }
  u64 half = cap / 2;
  Term left = bytes_read_tree(e, p, n, lo, half);
  Term right = bytes_read_tree(e, p, n, lo + half, half);
  return io_node(e, CID_BIN_BYTENODE, left, right, IO_HOTS & 1);
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
  u64 size = 1;
  while (size < len) {
    size *= 2;
  }
  Term tree = bytes_read_tree(e, buf, len, 0, size);
  free(buf);
  Loc l = heap_alloc(e, 2);
  e.mem[l]     = io_seal(e, tree, IO_HOTS & 1);
  e.mem[l + 1] = io_seal(e, (Term)len, IO_HOTS & 1);
  e.mem[l + 2] = io_seal(e, (Term)size, IO_HOTS & 1);
  return io_done(e, term_ctr(CID_BIN_BYTES, l));
}

static void __attribute__((constructor)) bytes_read_raw_use(void) {
  io_eff(FID_BYTES_READ_RAW, CID_BYTES_READ_RAW, bytes_read_raw_run, 0);
}
