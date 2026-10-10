/* mfdecode: decodes a video file inside a bottle through Media Foundation's source reader, the way
 * games play their cutscenes, and prints how many video frames and audio buffers came out. Under
 * wine this goes through winegstreamer to the engine's GStreamer and its FFmpeg plugin.
 *
 * build: x86_64-w64-mingw32-gcc -O2 -municode -o mfdecode.exe mfdecode.c -lmfplat -lmfreadwrite -lmfuuid -lole32 -luuid
 * run:   wine mfdecode.exe Z:\path\to\file.wmv
 */
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <stdio.h>

static int read_stream(IMFSourceReader *reader, DWORD stream, const GUID *major, const GUID *subtype, const char *what)
{
    IMFMediaType *type;
    HRESULT hr;
    int count = 0;

    IMFSourceReader_SetStreamSelection(reader, MF_SOURCE_READER_ALL_STREAMS, FALSE);
    if (FAILED(hr = IMFSourceReader_SetStreamSelection(reader, stream, TRUE))) {
        printf("%s: no stream (%08lx)\n", what, hr);
        return -1;
    }
    MFCreateMediaType(&type);
    IMFMediaType_SetGUID(type, &MF_MT_MAJOR_TYPE, major);
    IMFMediaType_SetGUID(type, &MF_MT_SUBTYPE, subtype);
    hr = IMFSourceReader_SetCurrentMediaType(reader, stream, NULL, type);
    IMFMediaType_Release(type);
    if (FAILED(hr)) {
        printf("%s: no decoder (%08lx)\n", what, hr);
        return -1;
    }
    for (;;) {
        DWORD index, flags;
        LONGLONG time;
        IMFSample *sample = NULL;
        if (FAILED(hr = IMFSourceReader_ReadSample(reader, stream, 0, &index, &flags, &time, &sample))) {
            printf("%s: read failed (%08lx) after %d\n", what, hr, count);
            return -1;
        }
        if (sample) { count++; IMFSample_Release(sample); }
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    }
    printf("%s: %d\n", what, count);
    return count;
}

int wmain(int argc, wchar_t **argv)
{
    IMFSourceReader *reader;
    PROPVARIANT start = {0};
    HRESULT hr;
    int video, audio;

    if (argc < 2) { printf("usage: mfdecode <file>\n"); return 2; }
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (FAILED(hr = MFCreateSourceReaderFromURL(argv[1], NULL, &reader))) {
        printf("open failed (%08lx)\n", hr);
        return 1;
    }
    video = read_stream(reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM, &MFMediaType_Video, &MFVideoFormat_NV12, "video frames");
    start.vt = VT_I8;
    IMFSourceReader_SetCurrentPosition(reader, &GUID_NULL, &start);
    audio = read_stream(reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, &MFMediaType_Audio, &MFAudioFormat_PCM, "audio buffers");
    IMFSourceReader_Release(reader);
    MFShutdown();
    return video > 0 && audio != 0 ? 0 : 1;
}
