#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"
#include "../../includes/ls_protocol.h"

configuration LinkStateRoutingC {
    provides interface LinkStateRouting;
}

implementation {
    components LinkStateRoutingP;
    LinkStateRouting = LinkStateRoutingP;

    components new SimpleSendC(AM_PACK);
    LinkStateRoutingP.Sender -> SimpleSendC;

    components new MapListC(uint16_t, uint16_t, LS_MAX_ROUTES, 30); //what to do with maplist, same as the other time?
    LinkStateRoutingP.PacketsReceived -> MapListC;

    components NeighborDiscoveryC;
    LinkStateRoutingP.NeighborDiscovery -> NeighborDiscoveryC;    

    components FloodingC;
    LinkStateRoutingP.Flooding -> FloodingC;

    components new TimerMilliC() as LSRTimer;   //change this variable name
    LinkStateRoutingP.LSRTimer -> LSRTimer;

    components RandomC as Random;               //change to RNG
    LinkStateRoutingP.Random -> Random;
}