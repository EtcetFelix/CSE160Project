#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration FloodingC{
	provides interface Flooding;
}
implementation {
	components FloodingP;
	Flooding = FloodingP;

	components new SimpleSendC(AM_PACK);
    FloodingP.simpleSend -> SimpleSendC;
    
    //components new MapListC(uint16_t, uint16_t, 20, 20);
    //FloodingP.PreviousPackets -> MapListC;

    components new HashmapC(uint32_t, 20);
    FloodingP.PreviousPackets -> HashmapC;
}