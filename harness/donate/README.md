# Donate harness

The donate sheet, the certificate offer and the Ko-fi button over a stand-in Home, on the simulator. Only `Donate.m`, the
page style and Core's glass are compiled.

    ./build.sh
    xcrun simctl install booted build/DonateHarness.app
    xcrun simctl launch booted com.vojta.donateharness sheet   # or: tour, certificate (SIMCTL_CHILD_HARNESS_LOGO=<png> for the logo)
