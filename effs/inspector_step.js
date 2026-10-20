// The native window backend is C/AppKit; keep headless App.play checks usable.
function inspector_step(info) { return ""; }

io_eff(CID(inspector.step), inspector_step);
