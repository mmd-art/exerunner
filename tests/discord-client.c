/* discord-client: a Discord RPC client inside a bottle, to test the bridge. It opens the pipe the
 * bridge serves, sends the handshake frame (opcode 0, then a JSON body; both ends frame messages
 * with two little-endian 32-bit words, opcode and length) and prints the frame that comes back.
 *
 * build: x86_64-w64-mingw32-gcc -O2 -o discord-client.exe discord-client.c
 * run:   wine discord-client.exe        (with the bridge running in the same bottle)
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    const char *body = "{\"v\":1,\"client_id\":\"1000000000000000001\"}";
    unsigned int header[2] = { 0, (unsigned int)strlen(body) };
    char reply[4096];
    DWORD done;
    HANDLE pipe = CreateFileA("\\\\.\\pipe\\discord-ipc-0", GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);

    if (pipe == INVALID_HANDLE_VALUE) { printf("no pipe: %lu\n", GetLastError()); return 1; }
    if (!WriteFile(pipe, header, sizeof(header), &done, NULL) || !WriteFile(pipe, body, header[1], &done, NULL)) {
        printf("write failed: %lu\n", GetLastError());
        return 1;
    }
    if (!ReadFile(pipe, header, sizeof(header), &done, NULL) || done != sizeof(header) || header[1] >= sizeof(reply)) {
        printf("no reply header: %lu\n", GetLastError());
        return 1;
    }
    if (!ReadFile(pipe, reply, header[1], &done, NULL)) { printf("no reply body: %lu\n", GetLastError()); return 1; }
    reply[done] = 0;
    printf("reply opcode %u: %s\n", header[0], reply);
    CloseHandle(pipe);
    return 0;
}
