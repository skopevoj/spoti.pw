#include "SGRImmersiveState.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    SGRImmersiveState s = {0};
    assert(!SGRImmersiveAdvance(&s, 100)); // constructing a page is not presenting it
    SGRImmersiveSetVisible(&s, true, true, 100);
    assert(!SGRImmersiveAdvance(&s, 101.999));
    assert(SGRImmersiveAdvance(&s, 102.0));
    assert(SGRImmersiveInteract(&s, 102.01)); // first touch only reveals
    assert(!SGRImmersiveInteract(&s, 102.02)); // next touch may seek
    assert(!SGRImmersiveAdvance(&s, 104.019));
    assert(SGRImmersiveAdvance(&s, 104.02));

    const unsigned reasons[] = {SGRImmersiveTouch, SGRImmersiveBrowse, SGRImmersiveMenu,
                               SGRImmersiveAccessibility, SGRImmersiveControl};
    for (unsigned i = 0; i < sizeof reasons / sizeof *reasons; i++) {
        SGRImmersiveHold(&s, reasons[i], true, 200);
        assert(!SGRImmersiveAdvance(&s, 1000));
        SGRImmersiveHold(&s, reasons[i], false, 1000);
        assert(!SGRImmersiveAdvance(&s, 1001.999));
        assert(SGRImmersiveAdvance(&s, 1002));
    }
    SGRImmersiveHold(&s, SGRImmersiveTouch, true, 2000);
    SGRImmersiveHold(&s, SGRImmersiveMenu, true, 2000);
    SGRImmersiveHold(&s, SGRImmersiveTouch, false, 2001);
    assert(!SGRImmersiveAdvance(&s, 3000)); // lifting a finger must not release an open menu
    SGRImmersiveHold(&s, SGRImmersiveMenu, false, 3000);
    assert(SGRImmersiveAdvance(&s, 3002));
    SGRImmersiveSetVisible(&s, true, false, 4000); // app inactive, interruption, rotation
    assert(!SGRImmersiveAdvance(&s, 5000));
    SGRImmersiveSetVisible(&s, true, true, 5000);
    assert(!SGRImmersiveAdvance(&s, 5001));
    assert(SGRImmersiveAdvance(&s, 5002));
    SGRImmersiveSetVisible(&s, false, true, 6000); // closed
    assert(!SGRImmersiveAdvance(&s, 7000));
    SGRImmersiveSetVisible(&s, true, true, 7000); // reopen, all old holds cleared
    assert(!s.immersive && !s.holds);
    assert(!SGRImmersiveAdvance(&s, NAN));
    assert(!SGRImmersiveAdvance(&s, INFINITY));
    assert(SGRImmersiveAdvance(&s, 7002));
    puts("immersive: deadlines, nested holds, reveal-only tap and lifecycle passed");
}
