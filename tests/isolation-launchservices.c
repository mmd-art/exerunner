#include <CoreServices/CoreServices.h>
#include <stdio.h>
#include <string.h>
#ifndef CANARY_MARKER
#error Define the diagnostic marker path
#endif
int main(int argc, char **argv) {
    if (argc == 1) {
        FILE *f = fopen(CANARY_MARKER, "w");
        if (!f) return 3;
        fputs("Synthetic LaunchServices canary\n", f);
        fclose(f);
        return 0;
    }
    if (argc != 3) return 2;
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)argv[2], strlen(argv[2]), true);
    CFURLRef opened = NULL;
    OSStatus status;
    if (!strcmp(argv[1], "spec")) {
        LSLaunchURLSpec spec = {0};
        spec.appURL = url;
        spec.launchFlags = kLSLaunchNewInstance | kLSLaunchDontSwitch | kLSLaunchDontAddToRecents;
        status = LSOpenFromURLSpec(&spec, &opened);
    } else status = LSOpenCFURLRef(url, &opened);
    printf("LS_%s_STATUS=%d\n", argv[1], (int)status);
    if (opened) CFRelease(opened);
    CFRelease(url);
    return status ? 1 : 0;
}
