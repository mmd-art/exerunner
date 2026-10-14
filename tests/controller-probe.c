/* Read-only XInput/WinMM inventory and input-state sampling. No rumble or configuration writes. */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <xinput.h>
#include <mmsystem.h>
#include <stdio.h>
#include <string.h>
int wmain(int argc, wchar_t **argv) {
    int seconds=argc>1?_wtoi(argv[1]):3;
    if (seconds<1 || seconds>120) return 2;
    setvbuf(stdout,NULL,_IONBF,0);
    UINT count=joyGetNumDevs(); int mm=0, xi=0;
    for(UINT i=0;i<count;i++) {
        JOYCAPSW caps={0}; JOYINFOEX state={0};state.dwSize=sizeof(state);state.dwFlags=JOY_RETURNALL;
        if(joyGetDevCapsW(i,&caps,sizeof(caps))==JOYERR_NOERROR && joyGetPosEx(i,&state)==JOYERR_NOERROR) {
            printf("WINMM %u %ls vendor=%04x product=%04x buttons=%u axes=%u\n",i,caps.szPname,caps.wMid,caps.wPid,caps.wNumButtons,caps.wNumAxes);mm++;
        }
    }
    XINPUT_STATE old[4]={{0}};
    for(DWORD i=0;i<4;i++) {
        if(XInputGetState(i,&old[i])==ERROR_SUCCESS){printf("XINPUT %lu connected packet=%lu\n",i,old[i].dwPacketNumber);xi++;}
    }
    printf("READY winmm=%d xinput=%d\n",mm,xi);
    int changes=0;WORD buttons=0;int left=0,right=0;
    for(int t=0;t<seconds*20;t++) {
        for(DWORD i=0;i<4;i++) {
            XINPUT_STATE state={0};
            if(XInputGetState(i,&state)==ERROR_SUCCESS && memcmp(&state.Gamepad,&old[i].Gamepad,sizeof(state.Gamepad))) {
                if(changes<40)printf("INPUT %lu buttons=%04x left=%d,%d right=%d,%d triggers=%u,%u\n",i,state.Gamepad.wButtons,state.Gamepad.sThumbLX,state.Gamepad.sThumbLY,state.Gamepad.sThumbRX,state.Gamepad.sThumbRY,state.Gamepad.bLeftTrigger,state.Gamepad.bRightTrigger);
                changes++;buttons|=state.Gamepad.wButtons;
                if(abs(state.Gamepad.sThumbLX)>8000 || abs(state.Gamepad.sThumbLY)>8000)left=1;
                if(abs(state.Gamepad.sThumbRX)>8000 || abs(state.Gamepad.sThumbRY)>8000)right=1;
                old[i]=state;
            }
        }
        Sleep(50);
    }
    printf("RESULT connected=%d input_changes=%d buttons_seen=%04x left_stick=%d right_stick=%d\n",xi,changes,buttons,left,right);
    return xi?0:1;
}
