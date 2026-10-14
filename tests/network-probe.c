/* Generic Windows socket transport to private Mac loopback fixtures; no external traffic. */
#ifndef UNICODE
#define UNICODE
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv) {
    if(argc!=3)return 2;
    WSADATA data;if(WSAStartup(MAKEWORD(2,2),&data))return 3;
    ULONG size=0;GetAdaptersAddresses(AF_UNSPEC,GAA_FLAG_SKIP_DNS_SERVER,NULL,NULL,&size);
    IP_ADAPTER_ADDRESSES *adapters=malloc(size);
    if(!adapters)return 4;
    if(GetAdaptersAddresses(AF_UNSPEC,GAA_FLAG_SKIP_DNS_SERVER,NULL,adapters,&size)!=NO_ERROR)return 5;
    for(IP_ADAPTER_ADDRESSES *a=adapters;a;a=a->Next)printf("ADAPTER %ls status=%u type=%u\n",a->FriendlyName,a->OperStatus,a->IfType);
    free(adapters);
    struct sockaddr_in address={0};address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    SOCKET udp=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP),tcp=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
    DWORD timeout=5000;setsockopt(udp,SOL_SOCKET,SO_RCVTIMEO,(char*)&timeout,sizeof(timeout));setsockopt(tcp,SOL_SOCKET,SO_RCVTIMEO,(char*)&timeout,sizeof(timeout));
    address.sin_port=htons((u_short)atoi(argv[1]));
    static const unsigned char packets[][32]={
        {'A','r','t','-','N','e','t',0,0,0x50,0,14,0,0,0,0,0,2,0,255},
        {0,16,0,0,'A','S','C','-','E','1','.','1','7',0,0,0,0x70,0,0,4},
        {'/','e','x','e','r','u','n','n','e','r',0,0,',','i',0,0,0,0,0,1}
    };
    unsigned char reply[64];
    for(int i=0;i<3;i++){if(sendto(udp,(char*)packets[i],sizeof(packets[i]),0,(struct sockaddr*)&address,sizeof(address))!=sizeof(packets[i]))return 6;int got=recvfrom(udp,(char*)reply,sizeof(reply),0,NULL,NULL);if(got!=sizeof(packets[i])||memcmp(reply,packets[i],sizeof(packets[i])))return 7;}
    address.sin_port=htons((u_short)atoi(argv[2]));if(connect(tcp,(struct sockaddr*)&address,sizeof(address))==SOCKET_ERROR)return 8;
    const char text[]="ExeRunner TCP canary";if(send(tcp,text,sizeof(text),0)!=sizeof(text))return 9;
    int got=0;while(got<sizeof(text)){int next=recv(tcp,(char*)reply+got,sizeof(text)-got,0);if(next<=0)return 10;got+=next;}
    if(memcmp(reply,text,sizeof(text)))return 11;
    closesocket(udp);closesocket(tcp);WSACleanup();puts("PASS: Windows UDP/TCP to Mac; Art-Net/sACN/OSC-shaped payloads unchanged");return 0;
}
