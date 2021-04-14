#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
//#include "../../includes/dv_strategy.h"

#define MAX_ROUTES  22
#define MAX_COST    20
#define DV_TTL       4
#define STRATEGY_SPLIT_HORIZON  50
#define STRATEGY_POISON_REVERSE 51
#define STRATEGY    STRATEGY_POISON_REVERSE

module DistanceVectorRoutingP {
    provides interface DistanceVectorRouting;
    
    uses interface SimpleSend as Carrier;
    uses interface NeighborDiscovery as NeighborDiscovery;
    uses interface Timer<TMilli> as timeElapsed;
    uses interface Random as RNG;
}

implementation {

    typedef struct {
        uint8_t targetDest;
        uint8_t subJump;
        uint8_t price;
        uint8_t timeAlive;
    } Route;
    
    uint16_t numRoutes = 0;
    Route routingTable[MAX_ROUTES];
    pack routePack;

    // declaration of the prototypes
    void makePack(pack *Package, uint16_t src, uint16_t targetDest, uint16_t TTL, uint16_t Protocol, uint16_t seq, void *payload, uint8_t length);
    uint8_t findNextHop(uint8_t targetDest);
    void addRoute(uint8_t targetDest, uint8_t subJump, uint8_t price, uint8_t timeAlive);
    void removeRoute(uint8_t idx);
    void decrementTTLs();
    bool inputNeighbors();
    void triggerUpdate();
    
    command error_t DistanceVectorRouting.start() {                                     // init rout table for current node        
        addRoute(TOS_NODE_ID, TOS_NODE_ID, 0, DV_TTL);
        call timeElapsed.startOneShot(40000);
        dbg(ROUTING_CHANNEL, "DVR initialized on node %d\n", TOS_NODE_ID);
        return SUCCESS;
    }//end function 

    event void timeElapsed.fired() {
        if(call timeElapsed.isOneShot()) {
            call timeElapsed.startPeriodic(30000 + (uint16_t) (call RNG.rand16()%3000));
        } else {
            // Decrement TTLs
            decrementTTLs();
            // Input neighbors into the routing table, if not there
            if(!inputNeighbors())
                // Send out routing table
                triggerUpdate();
        }//end if else function 
    }//end tirgger function 

    command void DistanceVectorRouting.ping(uint16_t destination, uint8_t *payload) {
        makePack(&routePack, TOS_NODE_ID, destination, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(ROUTING_CHANNEL, "PING FROM %d TO %d\n", TOS_NODE_ID, destination);
        call DistanceVectorRouting.routePacket(&routePack);
    }//end ping function for distance vector  routing 

    command void DistanceVectorRouting.routePacket(pack* myMsg) {
        uint8_t subJump;
        if(myMsg->targetDest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING) {
            dbg(ROUTING_CHANNEL, "PING Packet has reached destination %d\n", TOS_NODE_ID);
            makePack(&routePack, myMsg->targetDest, myMsg->src, 0, PROTOCOL_PINGREPLY, 0,(uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            call DistanceVectorRouting.routePacket(&routePack);
            return;
        } else if(myMsg->targetDest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PINGREPLY) {
            dbg(ROUTING_CHANNEL, "PING_REPLY Packet has reached destination %d\n", TOS_NODE_ID);
            return;
        } else if(myMsg->targetDest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_TCP) {
            dbg(ROUTING_CHANNEL, "TCP Packet has reached destination %d\n", TOS_NODE_ID);
            return;
        }//end double if else statement 
        if((findNextHop(myMsg->targetDest)) != 0) {
            subJump = findNextHop(myMsg->targetDest);
            dbg(ROUTING_CHANNEL, "Node %d routing packet through %d\n", TOS_NODE_ID, subJump);
            call Carrier.send(*myMsg, subJump);
        } else {
            dbg(ROUTING_CHANNEL, "No route to destination. Dropping packet\n");
        }//end if else
    }//end routing paccket function for distance vector

   
    command void DistanceVectorRouting.handleDV(pack* myMsg) {                                       // Update the routing table if needed
        uint16_t i, j;
        bool routePresent = FALSE, routesAdded = FALSE;
        Route* receivedRoutes = (Route*) myMsg->payload;
        
        for(i = 0; i < 5; i++) {                                                                     // For each of up to 5 routes -> process the routes
            
            if(receivedRoutes[i].targetDest == 0) { break; }                                         // Reached the last route -> stop
           
            for(j = 0; j < numRoutes; j++) {                                                         // Process the route
                if(receivedRoutes[i].targetDest == routingTable[j].targetDest) {
                    
                    if(receivedRoutes[i].subJump != 0) {                                            // If Split Horizon packet -> do nothing // If Carrier is the source of table entry -> update// If more optimal route found -> update
                        if(routingTable[j].subJump == myMsg->src) {
                            routingTable[j].price = (receivedRoutes[i].price + 1 < MAX_COST) ? receivedRoutes[i].cost + 1 : MAX_COST;
                            routingTable[j].timeAlive = DV_TTL;
                            //dbg(ROUTING_CHANNEL, "Update to route: %d from neighbor: %d with new price %d\n", routingTable[i].targetDest, routingTable[i].subJump, routingTable[i].price);
                        } else if(receivedRoutes[i].price + 1 < MAX_COST && receivedRoutes[i].price + 1 < routingTable[j].price) {
                            routingTable[j].subJump = myMsg->src;
                            routingTable[j].price = receivedRoutes[i].price + 1;
                            routingTable[j].timeAlive = DV_TTL;
                            //dbg(ROUTING_CHANNEL, "More optimal route found to targetDest: %d through %d at price %d\n", receivedRoutes[i].targetDest, receivedRoutes[i].subJump, receivedRoutes[i].price +1);
                        }// end nested if-else statement
                    }//end if statement 
                   
                    if(routingTable[j].subJump == receivedRoutes[i].subJump && routingTable[j].price == receivedRoutes[i].price && routingTable[j].price != MAX_COST) {      // If route is already present AND not unreachable -> update the TTL
                        routingTable[j].timeAlive = DV_TTL;
                    }//end if statement
                    routePresent = TRUE;
                    break;
                }// end if statement 
            }//enf for loop 
            
            if(!routePresent && numRoutes != MAX_ROUTES && receivedRoutes[i].subJump != 0 && receivedRoutes[i].price != MAX_COST) {         // If route not in table AND there is space AND it is not a split horizon packet AND the route price is not infinite -> add it
                addRoute(receivedRoutes[i].targetDest, myMsg->src, receivedRoutes[i].price + 1, DV_TTL);
                routesAdded = TRUE;
            }//end if statement 
            routePresent = FALSE;
        }//end for loop 
        if(routesAdded) {
            triggerUpdate();
        }//end if statement 
    }//end distance vector handling fucntion 

    command void DistanceVectorRouting.handleNeighborLost(uint16_t lostNeighbor) {             // Neighbor lost, update routing table and trigger DV update   
        uint16_t i;
        if(lostNeighbor == 0)
            return;
        dbg(ROUTING_CHANNEL, "Neighbor discovery has lost neighbor %u. Distance is now infinite!\n", lostNeighbor);
        for(i = 1; i < numRoutes; i++) {
            if(routingTable[i].targetDest == lostNeighbor || routingTable[i].subJump == lostNeighbor) {
                routingTable[i].price = MAX_COST;
            }// end if statement
        }//end for loop 
        triggerUpdate();
    }//end function for neighbor scenarios

    command void DistanceVectorRouting.handleNeighborFound() {
        inputNeighbors();                                                                   // Neighbor found, update routing table and trigger DV update
    }//end neighbour scenarios function 

    command void DistanceVectorRouting.printRouteTable() {
        uint8_t i;
        dbg(ROUTING_CHANNEL, "targetDest  HOP  COST  TTL\n");
        for(i = 0; i < numRoutes; i++) {
            dbg(ROUTING_CHANNEL, "%4d%5d%6d%5d\n", routingTable[i].targetDest, routingTable[i].subJump, routingTable[i].price, routingTable[i].timeAlive);
        }//end for loop
    }//end table printing function 

    uint8_t findNextHop(uint8_t targetDest) {
        uint16_t i;
        for(i = 1; i < numRoutes; i++) {
            if(routingTable[i].targetDest == targetDest) {
                if (routingTable[i].price != MAX_COST) {
                    return routingTable[i].subJump;
                }//end nested if statemnet 
            }//end if statement
        }//end for loop 
        return 0;
    }//end find next jukmping position function

    void addRoute(uint8_t targetDest, uint8_t subJump, uint8_t price, uint8_t timeAlive) {
        
        if(numRoutes != MAX_ROUTES) {                                                       // Add route to the end of the current list
            routingTable[numRoutes].targetDest = targetDest;
            routingTable[numRoutes].subJump = subJump;
            routingTable[numRoutes].price = price;
            routingTable[numRoutes].timeAlive = timeAlive;
            numRoutes++;
        }//end if statement
    }//end add route function 

    void removeRoute(uint8_t idx) {
        uint8_t j;
       
        for(j = idx+1; j < numRoutes; j++) {                                                 // Move other entries left
            routingTable[j-1].targetDest = routingTable[j].targetDest;
            routingTable[j-1].subJump = routingTable[j].subJump;
            routingTable[j-1].price = routingTable[j].price;
            routingTable[j-1].timeAlive = routingTable[j].timeAlive;
        }//end for loop
        
        routingTable[j-1].targetDest = 0;                                                   // Zero the j-1 entry
        routingTable[j-1].subJump = 0;
        routingTable[j-1].price = MAX_COST;
        routingTable[j-1].timeAlive = 0;
        numRoutes--;        
    }//end removign route function

    void decrementTTLs() {
        uint8_t i;
        for(i = 1; i < numRoutes; i++) {
            // If valid entry in the routing table -> decrement the TTL
            if(routingTable[i].timeAlive != 0) {
                routingTable[i].timeAlive--;
            }
            
            if(routingTable[i].timeAlive == 0) {                                            // If TTL is zero -> remove the route      
                dbg(ROUTING_CHANNEL, "Route stale, removing: %u\n", routingTable[i].targetDest);
                removeRoute(i);
                triggerUpdate();
            }//end if statement
        }//end for loop
    }//end decrementation function

    bool inputNeighbors() {
        uint32_t* neighbors = call NeighborDiscovery.getNeighbors();
        uint16_t neighborsListSize = call NeighborDiscovery.getNeighborListSize();
        uint8_t i, j;
        bool routeFound = FALSE, newNeighborfound = FALSE;
        
        for(i = 0; i < neighborsListSize; i++) {                                            //dbg(ROUTING_CHANNEL, "Routing Table: Inputting Neighbors for Node %d\n", TOS_NODE_ID);
            for(j = 1; j < numRoutes; j++) {
                
                if(neighbors[i] == routingTable[j].targetDest) {                            // If neighbor found in routing table -> update table entry
                    routingTable[j].subJump = neighbors[i];
                    routingTable[j].price = 1;
                    routingTable[j].timeAlive = DV_TTL;
                    routeFound = TRUE;
                    break;
                }//end if statement
            }//end nested forloop
            
            if(!routeFound && numRoutes != MAX_ROUTES) {                                    // If neighbor not already in the list and there is room -> add new neighbor
                addRoute(neighbors[i], neighbors[i], 1, DV_TTL);                
                newNeighborfound = TRUE;
            } else if(numRoutes == MAX_ROUTES) {
                dbg(ROUTING_CHANNEL, "Routing table full. Cannot add entry for node: %u\n", neighbors[i]);
            }//end if else staement
            routeFound = FALSE;
        }//end for loop
        if(newNeighborfound) {
            triggerUpdate();
            return TRUE;        
        }//end if statment
        return FALSE;
    }//end input neighbors function

    
    void triggerUpdate() {                                                                  // Skip the route for split horizon // Alter route table for poison reverse, keeping values in temp vars // Copy route onto array // Restore original route // Send packet with copy of partial routing table
        // Send routes to all neighbors one at a time. Use split horizon, poison reverse
        uint32_t* neighbors = call NeighborDiscovery.getNeighbors();
        uint16_t neighborsListSize = call NeighborDiscovery.getNeighborListSize();
        uint8_t i = 0, j = 0, counter = 0;
        uint8_t temp;
        Route packetRoutes[5];
        bool isSwapped = FALSE;
        
        for(i = 0; i < 5; i++) {                                                            // Zero out the array
                packetRoutes[i].targetDest = 0;
                packetRoutes[i].subJump = 0;
                packetRoutes[i].price = 0;
                packetRoutes[i].timeAlive = 0;
        }//end for loop
        
        for(i = 0; i < neighborsListSize; i++) {                                            // Send to every neighbor//dbg(ROUTING_CHANNEL, "Sending packet routes to neighbor %d\n", neighbors[i]);
            
            while(j < numRoutes) {
                
                if(neighbors[i] == routingTable[j].subJump && STRATEGY == STRATEGY_SPLIT_HORIZON) {// Split Horizon/Poison Reverse
                    temp = routingTable[j].subJump;
                    routingTable[j].subJump = 0;
                    isSwapped = TRUE;
                } else if(neighbors[i] == routingTable[j].subJump && STRATEGY == STRATEGY_POISON_REVERSE) {
                    temp = routingTable[j].price;
                    routingTable[j].price = MAX_COST;
                    isSwapped = TRUE;
                }
                
                packetRoutes[counter].targetDest = routingTable[j].targetDest;              // Add route to array to be sent out
                packetRoutes[counter].subJump = routingTable[j].subJump;
                packetRoutes[counter].price = routingTable[j].price;
                counter++;
                
                if(counter == 5 || j == numRoutes-1) {                                      // If our array is full or we have added all routes -> send out packet with routes                                      
                                                                                            // Send out packet//dbg(ROUTING_CHANNEL, "Sending packet routes to neighbor %d\n", neighbors[i]);
                    makePack(&routePack, TOS_NODE_ID, neighbors[i], 1, PROTOCOL_DV, 0, &packetRoutes, sizeof(packetRoutes));
                    call Carrier.send(routePack, neighbors[i]);
                    
                    while(counter > 0) {                                                    // Zero out array
                        counter--;
                        packetRoutes[counter].targetDest = 0;
                        packetRoutes[counter].subJump = 0;
                        packetRoutes[counter].price = 0;
                    }//end while loop
                }//end if statement
                
                if(isSwapped && STRATEGY == STRATEGY_SPLIT_HORIZON) {                       // Restore the table
                    routingTable[j].subJump = temp;
                } else if(isSwapped && STRATEGY == STRATEGY_POISON_REVERSE) {
                    routingTable[j].price = temp;
                }//end if else statement
                isSwapped = FALSE;
                j++;
            }//end while loop
            j = 0;
        }//end for loop
    }//end of trigger update

    void makePack(pack *Package, uint16_t src, uint16_t targetDest, uint16_t TTL, uint16_t protocol, uint16_t seq, void* payload, uint8_t length) {
        Package->src = src;
        Package->targetDest = targetDest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    } //end of makepack   
}//end of program







I'LL BE BACK ALAN