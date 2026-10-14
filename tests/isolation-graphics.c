#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
int main(){HWND w=CreateWindowExA(0,"STATIC","ExeRunner isolation graphics probe",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,400,260,NULL,NULL,GetModuleHandleA(NULL),NULL);if(!w){printf("WINDOW_FAIL %lu\n",GetLastError());return 1;}
IDirect3D9 *d=Direct3DCreate9(D3D_SDK_VERSION);if(!d){puts("D3D9_CREATE_FAIL");return 2;}
D3DPRESENT_PARAMETERS p={0};p.Windowed=TRUE;p.SwapEffect=D3DSWAPEFFECT_DISCARD;p.hDeviceWindow=w;
IDirect3DDevice9 *v=NULL;HRESULT hr=IDirect3D9_CreateDevice(d,D3DADAPTER_DEFAULT,D3DDEVTYPE_HAL,w,D3DCREATE_SOFTWARE_VERTEXPROCESSING,&p,&v);if(FAILED(hr)){printf("D3D9_DEVICE_FAIL %lx\n",(unsigned long)hr);return 3;}
for(int i=0;i<3;i++){IDirect3DDevice9_Clear(v,0,NULL,D3DCLEAR_TARGET,0xff284f89,1,0);hr=IDirect3DDevice9_Present(v,NULL,NULL,NULL,NULL);Sleep(250);}
IDirect3DDevice9_Clear(v,0,NULL,D3DCLEAR_TARGET,0xff284f89,1,0);
IDirect3DSurface9 *back=NULL,*copy=NULL;D3DSURFACE_DESC desc;
IDirect3DDevice9_GetBackBuffer(v,0,0,D3DBACKBUFFER_TYPE_MONO,&back);IDirect3DSurface9_GetDesc(back,&desc);
IDirect3DDevice9_CreateOffscreenPlainSurface(v,desc.Width,desc.Height,desc.Format,D3DPOOL_SYSTEMMEM,&copy,NULL);
HRESULT read=IDirect3DDevice9_GetRenderTargetData(v,back,copy);D3DLOCKED_RECT lock;unsigned long pixel=0;
if(SUCCEEDED(read)&&SUCCEEDED(IDirect3DSurface9_LockRect(copy,&lock,NULL,D3DLOCK_READONLY))){pixel=*(unsigned long*)lock.pBits;IDirect3DSurface9_UnlockRect(copy);}
printf("READBACK %lx PIXEL %08lx\n",(unsigned long)read,pixel);if(copy)IDirect3DSurface9_Release(copy);if(back)IDirect3DSurface9_Release(back);
printf("D3D9_PRESENT %lx\n",(unsigned long)hr);IDirect3DDevice9_Release(v);IDirect3D9_Release(d);DestroyWindow(w);return FAILED(hr)||FAILED(read)||(pixel & 0xffffff)!=0x284f89?4:0;}
