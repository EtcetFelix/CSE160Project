#include "../../includes/packet.h"
interface NeighborDiscovery {
	
	command error_t start();
   	command void discover(pack* packet);

}