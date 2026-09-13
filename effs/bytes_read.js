// Bytes
// =====

// The whole file as a Bin.Bytes value: a balanced tree of byte leaves over
// the next power of two, zero leaves for the unused tail, byte count, capacity.
function bytes_read_tree(buf, lo, cap) {
  if (lo >= buf.length) {
    return { $: "bin.ByteFlat", value: 0 };
  }
  if (cap === 1) {
    return { $: "bin.ByteFlat", value: buf[lo] };
  }
  const half = cap / 2;
  return { $: "bin.ByteNode", left: bytes_read_tree(buf, lo, half), right: bytes_read_tree(buf, lo + half, half) };
}

function bytes_read_raw(path) {
  const fs = require("fs");
  let buf;
  try {
    buf = fs.readFileSync(path);
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 2));
  }
  let size = 1;
  while (size < buf.length) {
    size *= 2;
  }
  return io_done({ $: "bin.Bytes", bufTree: bytes_read_tree(buf, 0, size), size: buf.length, capacity: size });
}
