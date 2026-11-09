# Pinned entity menu regression

Build with `sh harness/entity-menu/build.sh`, then run `harness/entity-menu/run.sh DUO_SIMULATOR_UDID`.
This compiles the production common Kit implementation and uses a real UINavigationController and
native Back, not a painted Back stand-in. Playlist, album and artist names exercise separate common
helper instances; their full Spotify header hooks are tested by their existing individual harnesses.

Checks cover page ownership, 44pt center/corner window hit routes, system rail placement below Back,
source forwarding once, recorder identity before source dispatch, repeated feeds, missing sources,
scroll, push/pop, sheet coverage/dismiss/reopen, container resizing without header callbacks, and
safe suppression/restoration where no unobstructed second slot fits. Actual hardware folding is not
simulated. The 130pt synthetic window deliberately provides no usable menu slot.

The phone diagnostic run intentionally reports the plain UINavigationController's existing top-corner
hit interception and stale positions when header callbacks are disabled. Compare against the exact
pre-edit SGRActionRow.m with `ACTION_ROW_SRC=/path/to/before/SGRActionRow.m OUT=/tmp/baseline sh
harness/entity-menu/build.sh`; do not claim these raw phone checks pass. On the tested iOS 26.5 phone,
all 11 phase geometries and all 43 failure signatures match the pre-edit baseline exactly. No phone
placement or refresh behavior was changed.

`harness/tabbar` additionally accepts `reservation` to exercise production tab composition with twelve
custom plus four built-in tabs, with labels shown and hidden. It checks every tab's scrolling/window hits at 470, 220, 164, 112, 80,
and restored 470pt rail heights, selection retention, default group geometry and offset recovery.
The reservation conservatively leaves space for a complete labeled row in either label mode.
When Back and a full row cannot both fit, the extra menu yields and navigation retains its row. No device model or width threshold selects the layout.
