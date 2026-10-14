#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <winspool.h>
#include <mmsystem.h>
#include <setupapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int bad(const char *what) { fprintf(stderr,"FAIL %s error=%lu\n",what,GetLastError()); return 1; }
static int printer(const wchar_t *output) {
    if (!output || wcsncmp(output,L"Z:\\",3)) return bad("print output must be test file");
    DWORD size=0,count=0; EnumPrintersW(PRINTER_ENUM_LOCAL,NULL,2,NULL,0,&size,&count);
    BYTE *buffer=calloc(1,size); if (!buffer || !EnumPrintersW(PRINTER_ENUM_LOCAL,NULL,2,buffer,size,&size,&count) || !count) return bad("EnumPrinters");
    printf("PRINTERS %lu\n",count);
    PRINTER_INFO_2W *info=(PRINTER_INFO_2W*)buffer;
    HDC dc=CreateDCW(L"WINSPOOL",info[0].pPrinterName,NULL,NULL); if (!dc) return bad("Create printer DC");
    DOCINFOW doc={0};doc.cbSize=sizeof(doc);doc.lpszDocName=L"ExeRunner print-to-file control";doc.lpszOutput=output;
    if (StartDocW(dc,&doc)<=0) return bad("StartDoc to file");
    if (StartPage(dc)<=0) return bad("StartPage");
    SetTextColor(dc,RGB(20,60,110));TextOutW(dc,160,160,L"ExeRunner printing control",wcslen(L"ExeRunner printing control"));
    Rectangle(dc,160,260,1600,860);MoveToEx(dc,160,260,NULL);LineTo(dc,1600,860);
    if (EndPage(dc)<=0 || EndDoc(dc)<=0) return bad("EndDoc");
    DeleteDC(dc);free(buffer);puts("RESULT PASS printing");return 0;
}
static int serial(const wchar_t *port) {
    wchar_t name[64];swprintf(name,64,L"\\\\.\\%ls",port);
    HANDLE handle=CreateFileW(name,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_EXISTING,0,NULL);
    if(handle==INVALID_HANDLE_VALUE)return bad("open COM");
    DCB dcb={0};dcb.DCBlength=sizeof(dcb);
    if(!GetCommState(handle,&dcb))return bad("GetCommState");
    dcb.BaudRate=CBR_9600;dcb.ByteSize=8;dcb.Parity=NOPARITY;dcb.StopBits=ONESTOPBIT;
    dcb.fDtrControl=DTR_CONTROL_DISABLE;dcb.fRtsControl=RTS_CONTROL_DISABLE;
    if(!SetCommState(handle,&dcb))return bad("SetCommState");
    COMMTIMEOUTS timeout={0};timeout.ReadIntervalTimeout=MAXDWORD;timeout.ReadTotalTimeoutConstant=1000;
    if(!SetCommTimeouts(handle,&timeout))return bad("timeouts");
    DWORD n=0;const char ping[]="EXERUNNER-PING";
    if(!WriteFile(handle,ping,sizeof(ping)-1,&n,NULL)||n!=sizeof(ping)-1)return bad("COM write");
    char response[64]={0};
    const char pong[]="EXERUNNER-PONG";
    if(!ReadFile(handle,response,sizeof(response)-1,&n,NULL)||n!=sizeof(pong)-1||memcmp(response,pong,sizeof(pong)-1))return bad("COM read");
    CloseHandle(handle);puts("RESULT PASS serial");return 0;
}
static int midi(const wchar_t *wanted) {
    UINT count=midiOutGetNumDevs();printf("MIDI_OUTPUTS %u\n",count);
    for(UINT i=0;i<count;i++){
        MIDIOUTCAPSW caps={0};if(midiOutGetDevCapsW(i,&caps,sizeof(caps))!=MMSYSERR_NOERROR)continue;
        if(!wcsstr(caps.szPname,wanted))continue;
        HMIDIOUT handle;MMRESULT status=midiOutOpen(&handle,i,0,0,CALLBACK_NULL);
        if(status!=MMSYSERR_NOERROR)return bad("midiOutOpen");
        status=midiOutShortMsg(handle,0x00644090);midiOutClose(handle);
        if(status!=MMSYSERR_NOERROR)return bad("midiOutShortMsg");
        puts("RESULT PASS midi");return 0;
    }
    return bad("virtual MIDI output missing");
}
static int inventory(void) {
    HMODULE usb=LoadLibraryW(L"winusb.dll");
    if(!usb||!GetProcAddress(usb,"WinUsb_Initialize"))return bad("WinUSB API");FreeLibrary(usb);
    static const GUID cls={0xa5dcbf10,0x6530,0x11d2,{0x90,0x1f,0x00,0xc0,0x4f,0xb9,0x51,0xed}};
    HDEVINFO list=SetupDiGetClassDevsW(&cls,NULL,NULL,DIGCF_PRESENT|DIGCF_DEVICEINTERFACE);
    if(list==INVALID_HANDLE_VALUE)return bad("USB enumeration");
    SP_DEVICE_INTERFACE_DATA data={0};data.cbSize=sizeof(data);DWORD count=0;
    while(SetupDiEnumDeviceInterfaces(list,NULL,&cls,count,&data))count++;
    if(GetLastError()!=ERROR_NO_MORE_ITEMS)return bad("USB enumeration status");SetupDiDestroyDeviceInfoList(list);
    UINT raw=0;if(GetRawInputDeviceList(NULL,&raw,sizeof(RAWINPUTDEVICELIST))==(UINT)-1)return bad("HID enumeration");
    printf("USB_INTERFACES %lu HID_RAW %u\n",count,raw);
    HMODULE opencl=LoadLibraryW(L"OpenCL.dll");
    typedef int (WINAPI *Platforms)(UINT,void **,UINT *);
    Platforms get=(Platforms)(opencl?GetProcAddress(opencl,"clGetPlatformIDs"):NULL);
    UINT platforms=0;int result=get?get(0,NULL,&platforms):-999;
    if(!get || (result!=0 && result!=-1001))return bad("OpenCL API");
    printf("OPENCL_PLATFORMS %u\n",platforms);FreeLibrary(opencl);
    puts("RESULT PASS inventory");return 0;
}
int wmain(int argc,wchar_t **argv) {
    if(argc==3&&!wcscmp(argv[1],L"printing"))return printer(argv[2]);
    if(argc==3&&!wcscmp(argv[1],L"serial"))return serial(argv[2]);
    if(argc==3&&!wcscmp(argv[1],L"midi"))return midi(argv[2]);
    if(argc==2&&!wcscmp(argv[1],L"inventory"))return inventory();
    return 2;
}
