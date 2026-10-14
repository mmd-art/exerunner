#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <windowsx.h>
static LRESULT CALLBACK wnd(HWND w, UINT m, WPARAM a, LPARAM b) {
    if (m == WM_MOUSEMOVE || m == WM_LBUTTONDOWN) {
        POINT p = {GET_X_LPARAM(b), GET_Y_LPARAM(b)};
        ClientToScreen(w, &p);
        printf("INPUT_MOUSE=%u,%ld,%ld\n", m, p.x, p.y); fflush(stdout);
    }
    if (m == WM_KEYDOWN) { printf("INPUT_KEY=%u\n", (unsigned)a); fflush(stdout); }
    if (m == WM_CLOSE) { DestroyWindow(w); return 0; }
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(w,m,a,b);
}
int main(int argc,char **argv) {
    WNDCLASSA c={0}; c.lpfnWndProc=wnd; c.hInstance=GetModuleHandleA(NULL); c.lpszClassName="ExeRunnerPresentCheck";
    RegisterClassA(&c);
    HWND w=CreateWindowA(c.lpszClassName,"ExeRunner controlled Direct3D9 check",WS_OVERLAPPEDWINDOW,100,100,640,420,NULL,NULL,c.hInstance,NULL);
    if(!w) return 1;
    ShowWindow(w,SW_SHOWNORMAL); UpdateWindow(w); SetForegroundWindow(w);
    HWND target=w;
    if(argc>1) {target=CreateWindowA("STATIC","child",WS_CHILD|WS_VISIBLE,0,0,600,360,w,NULL,c.hInstance,NULL);}
    IDirect3D9 *d=Direct3DCreate9(D3D_SDK_VERSION); if(!d) return 2;
    D3DPRESENT_PARAMETERS p={0};p.Windowed=TRUE;p.SwapEffect=D3DSWAPEFFECT_DISCARD;p.hDeviceWindow=target;
    p.BackBufferFormat=D3DFMT_X8R8G8B8;p.BackBufferWidth=600;p.BackBufferHeight=360;
    IDirect3DDevice9 *v=NULL; HRESULT hr=IDirect3D9_CreateDevice(d,0,D3DDEVTYPE_HAL,w,D3DCREATE_SOFTWARE_VERTEXPROCESSING,&p,&v);
    printf("DEVICE=%08lx PTR_BITS=%u CHILD=%d\n",(unsigned long)hr,(unsigned)(sizeof(void*)*8),argc>1); fflush(stdout);
    if(FAILED(hr)) return 3;
    DWORD until=GetTickCount()+20000;MSG m;int error=0;unsigned frames=0;
    while(GetTickCount()<until) {
        while(PeekMessageA(&m,NULL,0,0,PM_REMOVE)){if(m.message==WM_QUIT)goto done;TranslateMessage(&m);DispatchMessageA(&m);}
        D3DCOLOR color=((GetTickCount()/1000)%2)?0xff284f89:0xffab6540;
        hr=IDirect3DDevice9_Clear(v,0,NULL,D3DCLEAR_TARGET,color,1,0);if(FAILED(hr))error=1;
        hr=IDirect3DDevice9_Present(v,NULL,NULL,NULL,NULL);if(FAILED(hr))error=1;
        frames++;Sleep(30);
    }
done:
    printf("PRESENT=%08lx FRAMES=%u\n",(unsigned long)hr,frames);fflush(stdout);
    IDirect3DDevice9_Release(v);IDirect3D9_Release(d);if(IsWindow(w))DestroyWindow(w);return error?4:0;
}
