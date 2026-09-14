// Bytes
// =====

// The whole file as a Bin.Bytes value: a balanced tree of packed four-byte
// word leaves over the next power of two, with zero leaves standing in for
// the unused tail, plus the byte count and that capacity. Built here so no
// Bend-side conversion touches every byte. A node's fields are sealed in
// reference cells exactly when the program shares values of its type
// (HOT_BIN_BYTENODE, HOT_BIN_BYTES, defined by the compiler as IO_HOTS is
// for the base types): a shared take expects sealed fields, a plain
// consuming take expects plain ones, and either given the other corrupts
// the heap.
static Term bytes_read_tree(Env e, const uint8_t* p, u64 n, u64 lo, u64 cap) {
  if (lo >= n) {
    return term_pak(CID_BIN_BYTEFLAT, 0);
  }
  if (cap <= 4) {
    u64 word = 0;
    for (u64 k = 0; k < cap && lo + k < n; k += 1) {
      word |= (u64)p[lo + k] << (8 * k);
    }
    return term_pak(CID_BIN_BYTEWORD, word);
  }
  u64 half = cap / 2;
  Term left = bytes_read_tree(e, p, n, lo, half);
  Term right = bytes_read_tree(e, p, n, lo + half, half);
  return io_node(e, CID_BIN_BYTENODE, left, right, HOT_BIN_BYTENODE);
}

Term bytes_read_raw_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* path = io_cstr(e, f[0], &n);
  FILE* fp = io_nul(path, n) ? NULL : fopen(path, "rb");
  if (fp == NULL) {
    free(path);
    return io_fail(e, errno != 0 ? (u32)errno : ENOENT, NULL);
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
  e.mem[l]     = io_seal(e, tree, HOT_BIN_BYTES);
  e.mem[l + 1] = (Term)len;
  e.mem[l + 2] = (Term)size;
  return io_done(e, term_ctr(CID_BIN_BYTES, l));
}

static void __attribute__((constructor)) bytes_read_raw_use(void) {
  io_eff(CID_BYTES_READ_RAW, bytes_read_raw_run, 0);
}
