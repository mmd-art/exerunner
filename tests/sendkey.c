/* Test helper: presses a key or clicks in a window of the same bottle, from inside wine (no Mac
 * accessibility, the Mac's cursor stays put). Used to step through installers that wait for a
 * button.
 * build: x86_64-w64-mingw32-gcc -O2 -municode -o sendkey.exe sendkey.c
 * run:   wine sendkey.exe "Battle.net Setup" return
 *        wine sendkey.exe "Battle.net Setup" click 622 421     (client coordinates) */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static BOOL CALLBACK list_window(HWND window, LPARAM unused)
{
    wchar_t title[256], class[256];
    DWORD pid = 0;
    (void)unused;
    if (!IsWindowVisible(window)) return TRUE;
    GetWindowTextW(window, title, 256);
    GetClassNameW(window, class, 256);
    GetWindowThreadProcessId(window, &pid);
    wprintf(L"%p pid %lu class %ls title %ls\n", (void *)window, pid, class, title);
    return TRUE;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc == 2 && !wcscmp(argv[1], L"list")) { EnumWindows(list_window, 0); fflush(stdout); return 0; }
    HWND window;
    RECT rect;

    if (argc < 3) { fprintf(stderr, "usage: sendkey <window title> return|tab|space|click x y\n"); return 2; }
    if (!(window = FindWindowW(NULL, argv[1]))) { fprintf(stderr, "no window\n"); fflush(stderr); return 1; }
    GetWindowRect(window, &rect);
    printf("window %p at %ld,%ld size %ldx%ld\n", (void *)window, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top);
    if (!wcscmp(argv[2], L"click") && argc > 4) {
        int x = _wtoi(argv[3]), y = _wtoi(argv[4]);
        HWND target = ChildWindowFromPointEx(window, (POINT){x, y}, CWP_SKIPINVISIBLE);
        if (!target) target = window;
        POINT p = {x, y};
        MapWindowPoints(window, target, &p, 1);
        LPARAM at = MAKELPARAM(p.x, p.y);
        PostMessageW(target, WM_MOUSEMOVE, 0, at);
        PostMessageW(target, WM_LBUTTONDOWN, MK_LBUTTON, at);
        Sleep(80);
        PostMessageW(target, WM_LBUTTONUP, 0, at);
        printf("clicked %d,%d in %p\n", x, y, (void *)target);
        return 0;
    }
    WPARAM key = !wcscmp(argv[2], L"tab") ? VK_TAB : !wcscmp(argv[2], L"space") ? VK_SPACE : VK_RETURN;
    PostMessageW(window, WM_KEYDOWN, key, 1);
    PostMessageW(window, WM_KEYUP, key, 0xC0000001);
    printf("pressed\n");
    return 0;
}
