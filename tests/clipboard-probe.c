/* Two-way Unicode clipboard control. Outputs status only, never copied user content. */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
int wmain(int argc, wchar_t **argv) {
    if (argc != 3) return 2;
    for (int i=0; i<20; i++) { if (OpenClipboard(NULL)) break; Sleep(100); }
    HANDLE handle = GetClipboardData(CF_UNICODETEXT);
    const wchar_t *text = handle ? GlobalLock(handle) : NULL;
    int correct = text && wcscmp(text,argv[1]) == 0;
    if (text) GlobalUnlock(handle);
    CloseClipboard();
    if (!correct) { puts("FAIL: Mac-to-Windows Unicode clipboard"); return 1; }
    size_t length = (wcslen(argv[2])+1)*sizeof(wchar_t);
    HGLOBAL output = GlobalAlloc(GMEM_MOVEABLE,length);
    if (!output) return 3;
    void *copy = GlobalLock(output); memcpy(copy,argv[2],length); GlobalUnlock(output);
    if (!OpenClipboard(NULL)) { GlobalFree(output); return 4; }
    EmptyClipboard();
    if (!SetClipboardData(CF_UNICODETEXT,output)) { CloseClipboard(); GlobalFree(output); return 5; }
    CloseClipboard();
    for (int i=0; i<30; i++) { MSG msg; while(PeekMessageW(&msg,NULL,0,0,PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); } Sleep(100); }
    puts("PASS: Mac-to-Windows Unicode clipboard and Windows write");
    return 0;
}
