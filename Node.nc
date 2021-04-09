/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include <string.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
   uses interface Flooding as Flooding;
   uses interface DistanceVectorRouting as DistanceVectorRouting;
   uses interface NeighborDiscovery as NeighborDiscovery;
}

implementation {
   pack sendPackage;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");

      call NeighborDiscovery.start();
      call DistanceVectorRouting.start();
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      if(len==sizeof(pack)){
      	 pack* myMsg = (pack*) payload;
      	 // Don't print messages from neighbor probe packets (packets are created in NeighborDiscovery)
      	 if( strcmp( (char*)(myMsg->payload), "NeighborProbing") && (myMsg->protocol) != PROTOCOL_DV) {
      		dbg(GENERAL_CHANNEL, "Packet Received\n");
      	 	dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
      	 }
         if(myMsg->protocol == PROTOCOL_DV) {
         	//dbg(GENERAL_CHANNEL, "Distance Vector Protocol\n");
           	call DistanceVectorRouting.handleDV(myMsg);
         }
         else if (myMsg->dest == 0) {
            //dbg(GENERAL_CHANNEL, "Neighbor Discovery called\n");
      		call NeighborDiscovery.discover(myMsg);
      	 }
          else {
            //dbg(GENERAL_CHANNEL, "Got Here\n");
            //call Flooding.Flood(myMsg);
            call DistanceVectorRouting.routePacket(myMsg);
          }
         return msg;
      }
      // print these only when packet not recognised
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      //dbg(GENERAL_CHANNEL, "INITIATED ping\n");
      //call Flooding.ping(destination, payload);
      call DistanceVectorRouting.ping(destination, payload);
   }

   event void CommandHandler.printNeighbors(){
   		//dbg(GENERAL_CHANNEL, "Should be Printing\n");
   		call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){
   		call DistanceVectorRouting.printRouteTable();
   }

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
