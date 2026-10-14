#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#include <string.h>

static int failed;
static void check(int ok, const char *name) { printf("%s %s\n", ok ? "PASS" : "FAIL", name); fflush(stdout); if (!ok) failed++; }
int wmain(int argc, wchar_t **argv) {
    if (argc > 1 && wcscmp(argv[1], L"--reboot-code") == 0) return 3010;
    const wchar_t *path = L"C:\\exerunner-\x041F\x0440\x043E\x0431\x0430.txt";
    const char content[] = "ExeRunner generic Windows API control";
    HANDLE f = CreateFileW(path, GENERIC_READ|GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    check(f != INVALID_HANDLE_VALUE, "Unicode filename");
    if (f != INVALID_HANDLE_VALUE) {
        DWORD size = 0; char readback[128] = {0};
        int wrote = WriteFile(f, content, sizeof(content), &size, NULL) && size == sizeof(content);
        SetFilePointer(f, 0, NULL, FILE_BEGIN);
        int read = ReadFile(f, readback, sizeof(readback), &size, NULL) && size == sizeof(content) && !memcmp(readback, content, sizeof(content));
        check(wrote && read, "File write/read"); CloseHandle(f); DeleteFileW(path);
    }
    HKEY key = 0;
    LONG rc = RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\ExeRunner\\GeneralRuntimeProbe", 0, NULL, 0, KEY_READ|KEY_WRITE, NULL, &key, NULL);
    check(rc == ERROR_SUCCESS, "Registry create");
    if (rc == ERROR_SUCCESS) {
        const wchar_t value[] = L"\x041F\x0440\x043E\x0431\x0430";
        DWORD type = 0, size = 128; wchar_t result[64] = {0};
        int set = RegSetValueExW(key, L"Text", 0, REG_SZ, (const BYTE *)value, sizeof(value)) == ERROR_SUCCESS;
        int get = RegQueryValueExW(key, L"Text", NULL, &type, (BYTE *)result, &size) == ERROR_SUCCESS && type == REG_SZ && !wcscmp(result, value);
        check(set && get, "Unicode registry value"); RegCloseKey(key); RegDeleteKeyW(HKEY_CURRENT_USER, L"Software\\ExeRunner\\GeneralRuntimeProbe");
    }
    HMODULE library = LoadLibraryW(L"user32.dll");
    check(library && GetProcAddress(library, "CreateWindowExW"), "Windows DLL exports");
    if (library) FreeLibrary(library);
    HDC dc = CreateCompatibleDC(NULL);
    HFONT font = CreateFontW(20, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, DEFAULT_QUALITY, 0, L"Tahoma");
    check(dc && font, "GDI font creation");
    if (dc && font) {
        HGDIOBJ previous = SelectObject(dc, font); SIZE extent = {0};
        check(GetTextExtentPoint32W(dc, L"ExeRunner \x041F\x0440\x043E\x0431\x0430", 15, &extent) && extent.cx > 0 && extent.cy > 0, "Unicode text metrics");
        SelectObject(dc, previous); DeleteObject(font); DeleteDC(dc);
    }
    printf("ARCH %u\n", (unsigned)(sizeof(void *) * 8));
    printf("RESULT %s\n", failed ? "FAIL" : "PASS");
    return failed ? 1 : 0;
}
