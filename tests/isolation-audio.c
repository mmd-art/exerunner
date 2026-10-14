#define COBJMACROS
#include <windows.h>
#include <mmsystem.h>
#include <dsound.h>
#include <stdio.h>
int main(){UINT count=waveOutGetNumDevs();printf("OUTPUT_DEVICES=%u\n",count);IDirectSound8 *sound=NULL;HRESULT hr=DirectSoundCreate8(NULL,&sound,NULL);printf("DIRECTSOUND_RESULT=%08lx\n",(unsigned long)hr);if(sound)IDirectSound8_Release(sound);return count>0&&SUCCEEDED(hr)?0:1;}
