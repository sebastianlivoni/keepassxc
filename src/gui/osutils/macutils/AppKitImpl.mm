/*
 *  Copyright (C) 2024 KeePassXC Team <team@keepassxc.org>
 *  Copyright (C) 2016 Lennart Glauer <mail@lennart-glauer.de>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 2 or (at your option)
 *  version 3 of the License.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#import "AppKitImpl.h"
#include <AppKit/AppKit.h>
#import <QWindow>
#import <QMenu>
#import <QMenuBar>
#import <Cocoa/Cocoa.h>
#if __clang_major__ >= 13 && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_VERSION_12_3
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#endif

@implementation AppKitImpl

- (id) initWithObject:(AppKit*)appkit
{
    self = [super init];

    if (self) {
        m_appkit = appkit;
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(didDeactivateApplicationObserver:)
                                                               name:NSWorkspaceDidDeactivateApplicationNotification
                                                             object:nil];

        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                            selector:@selector(userSwitchHandler:)
                                                                name:NSWorkspaceSessionDidResignActiveNotification
                                                                object:nil];

        [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:NSKeyValueObservingOptionNew context:nil];
    }
    return self;
}

//
// Update last active application property
//
- (void) didDeactivateApplicationObserver:(NSNotification*) notification
{
    NSDictionary* userInfo = notification.userInfo;
    NSRunningApplication* app = [userInfo objectForKey:NSWorkspaceApplicationKey];

    if (app.processIdentifier != [self ownProcessId]) {
        self.lastActiveApplication = app;
    }
}

- (void) observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    Q_UNUSED(object)
    Q_UNUSED(change)
    Q_UNUSED(context)
    if ([keyPath isEqualToString:@"effectiveAppearance"]) {
        if (m_appkit) {

            void (^emitBlock)(void) = ^{
                emit m_appkit->interfaceThemeChanged();
            };

            if(@available(macOS 11.0, *)) {
                // Not sure why exactly this call is needed, but Apple sample code uses it so it's best to use it here too
                [NSApp.effectiveAppearance performAsCurrentDrawingAppearance:emitBlock];
            }
            else {
                emitBlock();
            }
        }
    }
}


//
// Get process id of frontmost application (-> keyboard input)
//
- (pid_t) activeProcessId
{
    return [NSWorkspace sharedWorkspace].frontmostApplication.processIdentifier;
}

//
// Get process id of own process
//
- (pid_t) ownProcessId
{
    return [NSProcessInfo processInfo].processIdentifier;
}

//
// Activate application by process id
//
- (bool) activateProcess:(pid_t) pid
{
    NSRunningApplication* app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    return [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

//
// Hide application by process id
//
- (bool) hideProcess:(pid_t) pid
{
    NSRunningApplication* app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    return [app hide];
}

//
// Get application hidden state by process id
//
- (bool) isHidden:(pid_t) pid
{
    NSRunningApplication* app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    return [app isHidden];
}

//
// Get state of macOS Dark Mode color scheme
//
- (bool) isDarkMode
{
    return [NSApp.effectiveAppearance.name isEqualToString:NSAppearanceNameDarkAqua];
}


//
// Get global menu bar theme state
//
- (bool) isStatusBarDark
{
#if __clang_major__ >= 9 && MAC_OS_X_VERSION_MIN_REQUIRED >= 101000
    if (@available(macOS 10.17, *)) {
        // This is an ugly hack, but I couldn't find a way to access QTrayIcon's NSStatusItem.
        NSStatusItem* dummy = [[NSStatusBar systemStatusBar] statusItemWithLength:0];
        NSString* appearance = [dummy.button.effectiveAppearance.name lowercaseString];
        [[NSStatusBar systemStatusBar] removeStatusItem:dummy];
        return [appearance containsString:@"dark"];
    }
#endif

    return [self isDarkMode];
}

//
// Notification for user switch
//
- (void) userSwitchHandler:(NSNotification*) notification
{
    if ([[notification name] isEqualToString:NSWorkspaceSessionDidResignActiveNotification] && m_appkit)
    {
        emit m_appkit->userSwitched();
    }
}

//
// Check if accessibility is enabled, may show an popup asking for permissions
//
- (bool) enableAccessibility
{
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
    // Request accessibility permissions for Auto-Type type on behalf of the user
    NSDictionary* opts = @{static_cast<id>(kAXTrustedCheckOptionPrompt): @YES};
    return AXIsProcessTrustedWithOptions(static_cast<CFDictionaryRef>(opts));
#else
    return YES;
#endif
}

//
// Check if screen recording is enabled, may show an popup asking for permissions
//
- (bool) enableScreenRecording
{
#if __clang_major__ >= 13 && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_VERSION_12_3
    if (@available(macOS 12.3, *)) {
        __block BOOL hasPermission = NO;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);

        // Attempt to use SCShareableContent to check for screen recording permission
        [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent * _Nullable content,
                                                                        NSError * _Nullable error) {
            Q_UNUSED(error);
            if (content) {
                // Successfully obtained content, indicating permission is granted
                hasPermission = YES;
            } else {
                // No permission or other error occurred
                hasPermission = NO;
            }
            // Notify the semaphore that the asynchronous task is complete
            dispatch_semaphore_signal(sema);
        }];

        // Wait for the asynchronous callback to complete
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
        dispatch_semaphore_wait(sema, timeout);

        // Return the final result
        return hasPermission;
    }
#endif
    return YES; // Return YES for macOS versions that do not support ScreenCaptureKit
}

- (void) toggleForegroundApp:(bool) foreground
{
    if (foreground) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    } else {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    }
}

- (void) setWindowSecurity:(NSWindow*) window state:(bool) state
{
    [window setSharingType: state ? NSWindowSharingNone : NSWindowSharingReadOnly];
}

- (void) configureWindowAndHelpMenus:(QMainWindow*) mainWindow helpMenu:(QMenu*) helpMenu
{
    QMenu *qtWindowMenu = new QMenu(AppKit::tr("Window"));
    NSMenu *nsWindowMenu = qtWindowMenu->toNSMenu();

    QString minimizeStr = AppKit::tr("Minimize");
    [nsWindowMenu addItemWithTitle:minimizeStr.toNSString() action:@selector(performMiniaturize:) keyEquivalent:@""];
    QString zoomStr = AppKit::tr("Zoom");
    [nsWindowMenu addItemWithTitle:zoomStr.toNSString() action:@selector(performZoom:) keyEquivalent:@""];
    [nsWindowMenu addItem:[NSMenuItem separatorItem]];
    QString bringAllToFrontStr = AppKit::tr("Bring All to Front");
    [nsWindowMenu addItemWithTitle:bringAllToFrontStr.toNSString() action:@selector(arrangeInFront:) keyEquivalent:@""];

    NSApp.windowsMenu = nsWindowMenu;

    mainWindow->menuBar()->insertMenu(helpMenu->menuAction(), qtWindowMenu);

    NSApp.helpMenu = helpMenu->toNSMenu();
}

@end


//
// ------------------------- C++ Trampolines -------------------------
//

AppKit::AppKit(QObject* parent)
    : QObject(parent)
{
    self = [[AppKitImpl alloc] initWithObject:this];
}

AppKit::~AppKit()
{
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:static_cast<id>(self)];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:static_cast<id>(self)];
    [NSApp removeObserver:static_cast<id>(self) forKeyPath:@"effectiveAppearance"];
    [static_cast<id>(self) dealloc];
}

pid_t AppKit::lastActiveProcessId()
{
    return [static_cast<id>(self) lastActiveApplication].processIdentifier;
}

pid_t AppKit::activeProcessId()
{
    return [static_cast<id>(self) activeProcessId];
}

pid_t AppKit::ownProcessId()
{
    return [static_cast<id>(self) ownProcessId];
}

bool AppKit::activateProcess(pid_t pid)
{
    return [static_cast<id>(self) activateProcess:pid];
}

bool AppKit::hideProcess(pid_t pid)
{
    return [static_cast<id>(self) hideProcess:pid];
}

bool AppKit::isHidden(pid_t pid)
{
    return [static_cast<id>(self) isHidden:pid];
}

bool AppKit::isDarkMode()
{
    return [static_cast<id>(self) isDarkMode];
}

bool AppKit::isStatusBarDark()
{
    return [static_cast<id>(self) isStatusBarDark];
}


bool AppKit::enableAccessibility()
{
    return [static_cast<id>(self) enableAccessibility];
}

bool AppKit::enableScreenRecording()
{
    return [static_cast<id>(self) enableScreenRecording];
}

void AppKit::toggleForegroundApp(bool foreground)
{
    [static_cast<id>(self) toggleForegroundApp:foreground];
}

void AppKit::setWindowSecurity(QWindow* window, bool state)
{
    auto view = reinterpret_cast<NSView*>(window->winId());
    [static_cast<id>(self) setWindowSecurity:view.window state:state];
}

void AppKit::configureWindowAndHelpMenus(QMainWindow* window, QMenu* helpMenu)
{
    [static_cast<id>(self) configureWindowAndHelpMenus:window helpMenu:helpMenu];
}

QIcon AppKit::iconFromSfSymbol(const QString &symbolName, double pointSize = 36.0) {
    // 1. Convert QString to NSString
    NSString *nsSymbolName = [NSString stringWithUTF8String:symbolName.toUtf8().constData()];
    if (!nsSymbolName) return QIcon();

    // 2. Load SF Symbol
    NSImage *symbolImage = [NSImage imageWithSystemSymbolName:nsSymbolName 
                                    accessibilityDescription:nil];
    if (!symbolImage) {
        return QIcon();
    }

    // 3. Configure symbol size and weight
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration 
        configurationWithPointSize:pointSize 
                            weight:NSFontWeightBold];
    symbolImage = [symbolImage imageWithSymbolConfiguration:config];

    // 4. Extract CGImage safely without manual CGBitmapContext allocations
    NSRect imageRect = NSMakeRect(0, 0, symbolImage.size.width, symbolImage.size.height);
    CGImageRef cgImage = [symbolImage CGImageForProposedRect:&imageRect 
                                                     context:nil 
                                                    hints:nil];
    if (!cgImage) {
        return QIcon();
    }

    // 5. Query dimensions while respecting natural aspect ratio
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);

    if (width == 0 || height == 0) return QIcon();

    // 6. Draw CGImage into standard QImage
    // We render into standard ARGB32 format to eliminate segfault risks
    QImage image(static_cast<int>(width), static_cast<int>(height), QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);

    // Render using CGContext directly inside a temporary block to avoid memory leaks
    {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(
            image.bits(),
            width,
            height,
            8,
            image.bytesPerLine(), // Use Qt's safe byte stride line alignment
            colorSpace,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
        );

        if (context) {
            // Draw without stretching aspect ratio
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
            CGContextRelease(context);
        }
        CGColorSpaceRelease(colorSpace);
    }

    // 7. Convert to HiDPI QPixmap
    QPixmap pixmap = QPixmap::fromImage(image);
    
    // Calculate device pixel ratio based on point size vs actual rendered pixel height
    double scaleFactor = static_cast<double>(height) / pointSize;
    if (scaleFactor > 0) {
        pixmap.setDevicePixelRatio(scaleFactor);
    }

    return QIcon(pixmap);
}