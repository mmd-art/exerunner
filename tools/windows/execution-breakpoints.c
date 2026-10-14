/* Prototype execution-breakpoint support for Rosetta, without changing watched
 * instruction bytes. Loaded only into an explicitly selected child.
 * Each explicit SetThreadContext arms one event per slot; not a full debugger.
 */
#include <windows.h>
#include <winternl.h>
typedef BOOL (WINAPI *set_fn)(HANDLE,const CONTEXT*);
typedef struct {
    DWORD tid;ULONG64 address[4],dr7;ULONG_PTR page[4];DWORD protection[4];BOOL armed[4];
    DWORD stepping_tid;unsigned stepping_slot;
} state;
static state records[16];static set_fn original_set;static PVOID handler_registration;
static char buffer[768];static unsigned used;
typedef struct {ULONG Flags;const UNICODE_STRING *FullName,*BaseName;PVOID Base;ULONG ImageSize;} notice_data;
typedef union {notice_data Loaded,Unloaded;} notice;
typedef void (CALLBACK *notice_fn)(ULONG,const notice*,PVOID);
typedef LONG (WINAPI *register_fn)(ULONG,notice_fn,PVOID,PVOID*);
static void text(const char*s){while(*s&&used<sizeof(buffer)-1)buffer[used++]=*s++;}
static void hex(ULONG64 v){const char*d="0123456789abcdef";text("0x");for(int i=60;i>=0;i-=4){char s[2]={d[(v>>i)&15],0};text(s);}}
static void emit(const char*event,DWORD tid,ULONG64 address,ULONG64 detail){
    DWORD n;used=0;text("PAGE_EXEC_BP ");text(event);text(" tid=");hex(tid);text(" address=");hex(address);text(" detail=");hex(detail);text("\n");WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),buffer,used,&n,NULL);
}
static BOOL protect(ULONG_PTR page,DWORD protection){DWORD old;BOOL result=VirtualProtect((LPVOID)page,4096,protection,&old);if(result)FlushInstructionCache(GetCurrentProcess(),(LPVOID)page,4096);return result;}
static state*find(DWORD tid,BOOL create){
    state*empty=0;for(unsigned i=0;i<16;i++){if(records[i].tid==tid)return &records[i];if(!records[i].tid&&!empty)empty=&records[i];}
    if(create&&empty){empty->tid=tid;return empty;}return 0;
}
static LONG deliver(state*r,unsigned slot,PEXCEPTION_POINTERS p){
    protect(r->page[slot],r->protection[slot]);r->armed[slot]=FALSE;r->stepping_tid=0;
    p->ExceptionRecord->ExceptionCode=EXCEPTION_SINGLE_STEP;p->ExceptionRecord->ExceptionAddress=(PVOID)(ULONG_PTR)r->address[slot];p->ExceptionRecord->NumberParameters=0;
    CONTEXT*c=p->ContextRecord;c->Dr0=r->address[0];c->Dr1=r->address[1];c->Dr2=r->address[2];c->Dr3=r->address[3];c->Dr6=(ULONG64)1<<slot;c->Dr7=r->dr7;
    c->EFlags=(c->EFlags&~0x100)|0x10000;c->ContextFlags|=CONTEXT_DEBUG_REGISTERS;
    emit("delivered",r->tid,c->Rip,slot);return EXCEPTION_CONTINUE_SEARCH;
}
static LONG CALLBACK exceptions(PEXCEPTION_POINTERS p){
    DWORD tid=GetCurrentThreadId();CONTEXT*c=p->ContextRecord;ULONG_PTR ip=c->Rip;
    if(p->ExceptionRecord->ExceptionCode==EXCEPTION_SINGLE_STEP){
        for(unsigned i=0;i<16;i++){
            state*r=&records[i];if(r->stepping_tid!=tid)continue;
            unsigned slot=r->stepping_slot;
            if(r->armed[slot]&&tid==r->tid&&ip==r->address[slot])return deliver(r,slot,p);
            if(ip<r->page[slot]||ip>=r->page[slot]+4096){
                if(r->armed[slot])protect(r->page[slot],PAGE_READWRITE);
                r->stepping_tid=0;c->EFlags&=~0x100;
            }else c->EFlags|=0x100;
            return EXCEPTION_CONTINUE_EXECUTION;
        }
        return EXCEPTION_CONTINUE_SEARCH;
    }
    if(p->ExceptionRecord->ExceptionCode!=EXCEPTION_ACCESS_VIOLATION||p->ExceptionRecord->NumberParameters<2||p->ExceptionRecord->ExceptionInformation[0]!=8)return EXCEPTION_CONTINUE_SEARCH;
    for(unsigned i=0;i<16;i++){
        state*r=&records[i];for(unsigned slot=0;slot<4;slot++){
            if(!r->armed[slot]||ip<r->page[slot]||ip>=r->page[slot]+4096)continue;
            if(!protect(r->page[slot],r->protection[slot]))return EXCEPTION_CONTINUE_SEARCH;
            if(tid==r->tid&&ip==r->address[slot])return deliver(r,slot,p);
            r->stepping_tid=tid;r->stepping_slot=slot;c->EFlags|=0x100;return EXCEPTION_CONTINUE_EXECUTION;
        }
    }
    return EXCEPTION_CONTINUE_SEARCH;
}
static BOOL WINAPI set_context(HANDLE thread,const CONTEXT*context){
    BOOL result=original_set(thread,context);DWORD error=GetLastError();if(!result)return result;
    if((context->ContextFlags&CONTEXT_DEBUG_REGISTERS)!=CONTEXT_DEBUG_REGISTERS)return result;
    DWORD tid=GetThreadId(thread);state*r=find(tid,TRUE);if(!r){SetLastError(error);return result;}
    for(unsigned slot=0;slot<4;slot++){if(r->armed[slot])protect(r->page[slot],r->protection[slot]);r->armed[slot]=FALSE;}
    r->stepping_tid=0;r->dr7=context->Dr7;
    if(handler_registration)RemoveVectoredExceptionHandler(handler_registration);
    handler_registration=AddVectoredExceptionHandler(1,exceptions);
    for(unsigned slot=0;slot<4;slot++){
        r->address[slot]=(&context->Dr0)[slot];
        BOOL enabled=(context->Dr7&((ULONG64)3<<(2*slot)))!=0;unsigned type=(context->Dr7>>(16+4*slot))&3;
        if(!enabled||!r->address[slot])continue;
        if(type!=0){emit("unsupported_type",tid,r->address[slot],type);continue;}
        MEMORY_BASIC_INFORMATION memory;if(!VirtualQuery((void*)(ULONG_PTR)r->address[slot],&memory,sizeof(memory))||memory.State!=MEM_COMMIT)continue;
        r->page[slot]=(ULONG_PTR)r->address[slot]&~(ULONG_PTR)4095;r->protection[slot]=memory.Protect;
        r->armed[slot]=protect(r->page[slot],PAGE_READWRITE);
        emit(r->armed[slot]?"armed":"arm_failed",tid,r->address[slot],r->protection[slot]);
    }
    SetLastError(error);return result;
}
static BOOL same(const char*a,const char*b){while(*a&&*a==*b){a++;b++;}return *a==*b;}
static BOOL install(void){
    if(original_set)return TRUE;
    unsigned char*base=(unsigned char*)GetModuleHandleW(NULL);IMAGE_DOS_HEADER*dos=(IMAGE_DOS_HEADER*)base;IMAGE_NT_HEADERS64*nt=(IMAGE_NT_HEADERS64*)(base+dos->e_lfanew);
    DWORD rva=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;if(!rva)return FALSE;
    for(IMAGE_IMPORT_DESCRIPTOR*d=(IMAGE_IMPORT_DESCRIPTOR*)(base+rva);d->Name;d++){
        if(!d->OriginalFirstThunk)continue;
        IMAGE_THUNK_DATA64*n=(IMAGE_THUNK_DATA64*)(base+d->OriginalFirstThunk),*a=(IMAGE_THUNK_DATA64*)(base+d->FirstThunk);
        for(;n->u1.AddressOfData;n++,a++){
            if(IMAGE_SNAP_BY_ORDINAL64(n->u1.Ordinal))continue;
            const char*name=(const char*)((IMAGE_IMPORT_BY_NAME*)(base+n->u1.AddressOfData))->Name;
            if(!same(name,"SetThreadContext"))continue;
            set_fn entry=(set_fn)(ULONG_PTR)a->u1.Function;
            if(entry!=(set_fn)GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"SetThreadContext"))return FALSE;
            DWORD old,ignored;if(!VirtualProtect(&a->u1.Function,8,PAGE_READWRITE,&old))return FALSE;
            original_set=entry;a->u1.Function=(ULONG64)(ULONG_PTR)set_context;VirtualProtect(&a->u1.Function,8,old,&ignored);
            emit("installed",GetCurrentThreadId(),(ULONG_PTR)&a->u1.Function,(ULONG_PTR)entry);return TRUE;
        }
    }
    return FALSE;
}
static void CALLBACK loaded(ULONG reason,const notice*data,PVOID context){
    if(reason!=1||!data->Loaded.BaseName||data->Loaded.BaseName->Length!=20)return;
    static const WCHAR name[]=L"dbdata.dll";for(unsigned i=0;i<10;i++){WCHAR c=data->Loaded.BaseName->Buffer[i];if(c>=L'A'&&c<=L'Z')c+=32;if(c!=name[i])return;}install();
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID reserved){
    if(reason!=DLL_PROCESS_ATTACH)return TRUE;
    register_fn notify=(register_fn)GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"LdrRegisterDllNotification");PVOID cookie=0;if(notify)notify(0,loaded,NULL,&cookie);
    install();return TRUE;
}
