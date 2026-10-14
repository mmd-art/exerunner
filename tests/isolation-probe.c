#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
static int read_file(char *p){ HANDLE f=CreateFileA(p,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,0,NULL);if(f==INVALID_HANDLE_VALUE)return 0;char b;DWORD n;int ok=ReadFile(f,&b,1,&n,NULL);CloseHandle(f);return ok; }
static int write_file(char *p){ HANDLE f=CreateFileA(p,GENERIC_WRITE,0,NULL,CREATE_ALWAYS,0,NULL);if(f==INVALID_HANDLE_VALUE)return 0;CloseHandle(f);return 1; }
static void init_net(){WSADATA d;WSAStartup(MAKEWORD(2,2),&d);}
#else
#include <unistd.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <arpa/inet.h>
#include <fcntl.h>
static int read_file(char *p){int f=open(p,O_RDONLY);if(f<0)return 0;char b;int ok=read(f,&b,1)>=0;close(f);return ok;}
static int write_file(char *p){int f=open(p,O_WRONLY|O_CREAT,0600);if(f<0)return 0;close(f);return 1;}
static void init_net(){}
#endif
static int failures=0;
static void check(char *name,int got,int want){printf("%s: %s (access=%d expected=%d)\n",name,got==want?"PASS":"FAIL",got,want);if(got!=want)failures++;}
static int network(char *ip,int port){int s=socket(AF_INET,SOCK_STREAM,0);if(s<0)return 0;struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(port);a.sin_addr.s_addr=inet_addr(ip);int ok=connect(s,(struct sockaddr*)&a,sizeof(a))==0;
#ifdef _WIN32
closesocket(s);
#else
close(s);
#endif
return ok;}
static int udp(char *ip){int s=socket(AF_INET,SOCK_DGRAM,0);if(s<0)return 0;struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(9);a.sin_addr.s_addr=inet_addr(ip);int ok=sendto(s,"probe",5,0,(struct sockaddr*)&a,sizeof(a))==5;
#ifdef _WIN32
closesocket(s);
#else
close(s);
#endif
return ok;}
int main(int argc,char **argv){if(argc!=8){printf("expected: allowed-read blocked-read blocked-write link-read localhost-port mode child\n");return 90;}int deny=atoi(argv[6]);init_net();
check("own-file-readable",read_file(argv[1]),1);check("outside-file-readable",read_file(argv[2]),!deny);check("outside-file-writable",write_file(argv[3]),!deny);check("symlink-escape",read_file(argv[4]),!deny);check("loopback-TCP",network("127.0.0.1",atoi(argv[5])),!deny);
check("nonlocal-UDP",udp("192.0.2.1"),!deny);
#ifdef _WIN32
if(strcmp(argv[7],"child")){ char cmd[8192];snprintf(cmd,sizeof(cmd),"\"%s\" \"%s\" \"%s\" \"%s\" \"%s\" %s %s child",argv[0],argv[1],argv[2],argv[3],argv[4],argv[5],argv[6]);STARTUPINFOA si={.cb=sizeof(si)};PROCESS_INFORMATION pi;int ok=CreateProcessA(NULL,cmd,NULL,NULL,FALSE,0,NULL,NULL,&si,&pi);check("spawn-child",ok,1);if(ok){WaitForSingleObject(pi.hProcess,20000);DWORD status=99;GetExitCodeProcess(pi.hProcess,&status);check("child-inherits-restrictions",status==0,1);CloseHandle(pi.hThread);CloseHandle(pi.hProcess);}}
#else
if(strcmp(argv[7],"child")){pid_t p=fork();if(p==0){argv[7]="child";execv(argv[0],argv);_exit(99);}int status=0;waitpid(p,&status,0);check("child-inherits-restrictions",WIFEXITED(status)&&WEXITSTATUS(status)==0,1);}
#endif
return failures?1:0;}
