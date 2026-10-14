/* ExeRunner child-process compatibility launcher. No gameplay time limit.
 * It loads our Windows API adapter only into the child it explicitly creates,
 * keeps the game's command line/current directory and reports its full status.
 */
#include <windows.h>
static WCHAR target[1024],dll[1024],command[32768];
static char output[512];static unsigned used;
void *memset(void*d,int value,size_t n){volatile unsigned char*p=d;while(n--)*p++=(unsigned char)value;return d;}
static void text(const char*s){while(*s&&used<sizeof(output)-1)output[used++]=*s++;}
static void hex(ULONG64 v){const char*d="0123456789abcdef";text("0x");for(int i=60;i>=0;i-=4){char s[2]={d[(v>>i)&15],0};text(s);}}
static void emit(const char*event,ULONG64 a,ULONG64 b){DWORD n;used=0;text("EXERUNNER_COMPAT ");text(event);text(" a=");hex(a);text(" b=");hex(b);text("\n");WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),output,used,&n,NULL);}
void WINAPI mainCRTStartup(void){
    DWORD tl=GetEnvironmentVariableW(L"EXERUNNER_COMPAT_TARGET",target,1024),dl=GetEnvironmentVariableW(L"EXERUNNER_COMPAT_DLL",dll,1024),cl=GetEnvironmentVariableW(L"EXERUNNER_COMPAT_COMMAND_LINE",command,32768);
    if(!tl||tl>=1024||!dl||dl>=1024||!cl||cl>=32768){emit("invalid_configuration",tl,cl);ExitProcess(2);}
    STARTUPINFOW startup={0};PROCESS_INFORMATION child={0};startup.cb=sizeof(startup);
    if(!CreateProcessW(target,command,NULL,NULL,TRUE,CREATE_SUSPENDED,NULL,NULL,&startup,&child)){emit("create_failed",GetLastError(),0);ExitProcess(3);}
    emit("created",child.dwProcessId,child.dwThreadId);
    LPVOID remote=VirtualAllocEx(child.hProcess,NULL,(dl+1)*sizeof(WCHAR),MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);SIZE_T written=0;
    BOOL copied=remote&&WriteProcessMemory(child.hProcess,remote,dll,(dl+1)*sizeof(WCHAR),&written)&&written==(dl+1)*sizeof(WCHAR);
    HANDLE loader=copied?CreateRemoteThread(child.hProcess,NULL,0,(LPTHREAD_START_ROUTINE)GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"LoadLibraryW"),remote,0,NULL):NULL;
    DWORD wait=loader?WaitForSingleObject(loader,15000):WAIT_FAILED,loaded=0;if(loader)GetExitCodeThread(loader,&loaded);
    emit("adapter_loaded",wait,loaded);
    if(wait!=WAIT_OBJECT_0||!loaded){TerminateProcess(child.hProcess,4);WaitForSingleObject(child.hProcess,5000);ExitProcess(4);}
    CloseHandle(loader);VirtualFreeEx(child.hProcess,remote,0,MEM_RELEASE);
    if(ResumeThread(child.hThread)==(DWORD)-1){emit("resume_failed",GetLastError(),0);TerminateProcess(child.hProcess,6);ExitProcess(6);}
    WaitForSingleObject(child.hProcess,INFINITE);
    DWORD code=0;GetExitCodeProcess(child.hProcess,&code);emit("windows_exit",code,0);
    CloseHandle(child.hThread);CloseHandle(child.hProcess);ExitProcess(code);
}
