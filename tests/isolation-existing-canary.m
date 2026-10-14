#import <AppKit/AppKit.h>
#include <stdio.h>
void mark(void){FILE*f=fopen(MARKER,"w");if(f){fputs("Synthetic LaunchServices canary\n",f);fclose(f);}}
@interface Handler : NSObject <NSApplicationDelegate>
@end
@implementation Handler
- (void)applicationDidFinishLaunching:(NSNotification*)n {FILE*f=fopen(READY,"w");if(f){fputs("ready\n",f);fclose(f);}}
- (void)application:(NSApplication*)app openURLs:(NSArray<NSURL*>*)urls {mark();}
- (void)application:(NSApplication*)app openFiles:(NSArray<NSString*>*)files {mark();[app replyToOpenOrPrint:NSApplicationDelegateReplySuccess];}
- (BOOL)applicationShouldHandleReopen:(NSApplication*)app hasVisibleWindows:(BOOL)flag {mark();return NO;}
@end
int main(){@autoreleasepool {NSApplication*app=[NSApplication sharedApplication];Handler*h=[Handler new];app.delegate=h;[app setActivationPolicy:NSApplicationActivationPolicyProhibited];[app run];}return 0;}
