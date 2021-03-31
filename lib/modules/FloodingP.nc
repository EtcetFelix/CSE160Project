#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module FloodingP {
	provides interface Flooding;
	uses interface SimpleSend;
	uses interface MapList<uint16_t, uint16_t> as PacketsReceived;
}
Implementation {
	pack sendPackage;
	uint16_t sequenceNum = 0;

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    command void Flooding.handleFlooding(pack* letter){                                 // Letter is the same as "packet"
        if(call PacketsReceived.containsVal(letter -> src, letter -> seq)){
            dbg(FLOODING_CHANNEL, "Duplicate packet. Will not forward...\n");           //Debugging Message PRint
        } else if(letter -> TTL == 0) {                                                 //When the packet's time to live has expired we don't forward the packet infinitely
            dbg(FLOODING_CHANNEL, "Packet has expired. Will not forward to prevent infinite loop...\n");
        } else if(letter -> dest ==  TOS_NODE_ID){
            if(letter -> protocol == PROTOCOL_PING){                                    //inplementing HANDLE PAYLOAD RECEIVED
                dbg(FLOODING_CHANNEL, "Package has reached the destination!...\n");
                //logPack(letter); //figure out if it breaks the code

                call PacketsReceived.insertVal(letter -> src, letter -> seq);           //Keeping track of the source of our pakets and it's respective sequence
                makePack(&sendPackage, letter -> dest, letter -> src, BETTER_TTL, PROTOCOL_PINGREPLY, sequenceNum++, (unint8_t *) letter -> payload, PACKET_MAX_PAYLOAD_SIZE);     //RePacket to send to subsequent nodes
                call Sender.send(senndPackage, AM_BROADCAST_ADDR);                      //Send new package to  all modules
                dbg(FLOODING_CHANNEL, "RePackage has been resent!...\n");               //Debug Message being printed
            } else if(letter -> protocol == PROTOCOL_PINGREPLY){
                dbg(FLOODING_CHANNEL, "RePackage has reached destination...\n");
                //logPack(letter); //figure out what this line does
                call PacketsReceived.insertVal(letter -> src, letter -> seq);           //Login PAcket information into the Maplist
            }
        } else {
            letter -> TTL -= 1;                                                         //HANDLEFORWARD call
            
            call PacketsReceived.insertVal(letter -> src, letter -> seq);               //Calling to record package RECEIVED
            call Sender.send(*letter, AM_BROADCAST_ADDR);                               //Module that sends packets

            dbg(FLOODING_CHANNEL, "New package has been forwarded with new Time To Live...\n") //
        }
    }//end of function
}
