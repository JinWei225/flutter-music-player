// Window widths, in logical pixels, at which the shell changes shape.

/// Below this the sidebar and full player bar do not fit, so the phone layout
/// (bottom navigation + mini player) is used instead.
const double kCompactBreakpoint = 700;

/// Between the compact and medium breakpoints (a tablet held upright) the
/// sidebar shrinks to an icon rail and Now Playing slides over the library
/// instead of docking beside it.
const double kMediumBreakpoint = 1000;

/// From here on there is room for the library and Now Playing together, so
/// the panel opens by itself when a track starts.
const double kExpandedBreakpoint = 1300;
