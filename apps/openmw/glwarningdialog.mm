#include "glwarningdialog.hpp"

#ifdef __APPLE__

#import <Cocoa/Cocoa.h>

namespace OMW
{
    LegacyOpenGLWarningResult showLegacyOpenGLWarningDialog()
    {
        LegacyOpenGLWarningResult result;

        NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

        NSAlert* alert = [[[NSAlert alloc] init] autorelease];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert setMessageText:@"No OpenGL 2.0 support detected!"];
        [alert setInformativeText:@"Just a heads up, your GPU does not support OpenGL 2.0. We will try to fall back to OpenGL 1.x, but the game will struggle hard!"];
        [alert addButtonWithTitle:@"Quit"];
        [alert addButtonWithTitle:@"Continue"];

        NSButton* checkbox = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 260, 18)] autorelease];
        [checkbox setButtonType:NSSwitchButton];
        [checkbox setTitle:@"Don't remind me again"];
        [checkbox setState:NSOffState];
        [alert setAccessoryView:checkbox];

        const NSInteger response = [alert runModal];
        result.mContinue = (response == NSAlertSecondButtonReturn);
        result.mDontRemindAgain = ([checkbox state] == NSOnState);

        [pool drain];
        return result;
    }
}

#endif
