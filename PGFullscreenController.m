/* Copyright © 2007-2009, The Sequential Project
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the the Sequential Project nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE SEQUENTIAL PROJECT ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE SEQUENTIAL PROJECT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "PGFullscreenController.h"
#import <Carbon/Carbon.h>

// Views
#import "PGFullscreenWindow.h"

// Controllers
#import "PGDocumentController.h"
#import "PGPrefController.h"

// Other
#import "PGDelayedPerforming.h"

// Categories
#import "NSObjectAdditions.h"
#import "NSScreenAdditions.h"
#import "NSStringAdditions.h"

@interface PGFullscreenController(Private)

- (void)_hideMenuBar;

@end

@implementation PGFullscreenController

#pragma mark +PGFullscreenController

+ (id)sharedFullscreenController
{
	static PGFullscreenController *sharedFullscreenController = nil;
	if(!sharedFullscreenController) sharedFullscreenController = [[self alloc] init];
	return sharedFullscreenController;
}

#pragma mark -PGFullscreenController

- (void)prepareToExitFullscreen
{
	_isExitingFullscreen = YES;
	SetSystemUIMode(kUIModeNormal, kNilOptions); // For some reason, this moves windows downward slightly (at least on 10.5.3), so make sure it happens before our new windows get put onscreen.
}

#pragma mark -

- (void)displayScreenDidChange:(NSNotification *)aNotif
{
	NSScreen *const screen = [[PGPrefController sharedPrefController] displayScreen];
	[(PGFullscreenWindow *)[self window] moveToScreen:screen];
	if(![[self window] isKeyWindow]) return;
	if([NSScreen AE_mainScreen] == screen) [self _hideMenuBar];
	else SetSystemUIMode(kUIModeNormal, kNilOptions);
}

#pragma mark -PGFullscreenController(Private)

- (void)_hideMenuBar
{
	SetSystemUIMode(kUIModeAllSuppressed, kNilOptions);
}

#pragma mark -PGDisplayController

- (BOOL)setActiveDocument:(PGDocument *)document
        closeIfAppropriate:(BOOL)flag
{
	if(document || _isExitingFullscreen) return [super setActiveDocument:document closeIfAppropriate:NO];
	if(![self activeDocument]) return NO;
	NSMutableArray *const docs = [[[[PGDocumentController sharedDocumentController] documents] mutableCopy] autorelease];
	PGDocument *const nextDoc = [[PGDocumentController sharedDocumentController] next:YES documentBeyond:[self activeDocument]];
	[docs removeObjectIdenticalTo:[self activeDocument]];
	[super setActiveDocument:nextDoc closeIfAppropriate:NO]; // PGDocumentController knows when to close us, so don't close ourselves.
	return NO;
}
- (NSWindow *)windowForSheet
{
	return nil;
}

#pragma mark -NSWindowController

- (BOOL)shouldCascadeWindows
{
	return NO;
}
- (void)windowDidLoad
{
	NSWindow *const window = [[[PGFullscreenWindow alloc] initWithScreen:[[PGPrefController sharedPrefController] displayScreen]] autorelease];
	NSView *const content = [[[[self window] contentView] retain] autorelease];
	[[self window] setContentView:nil];
	[window setContentView:content];
	[window setDelegate:[[self window] delegate]];
	[window setHidesOnDeactivate:[[self window] hidesOnDeactivate]];
	[window registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, NSURLPboardType, nil]];
	[self setWindow:window];

	[super windowDidLoad];
}
- (void)close
{
	if(_isExitingFullscreen) return;
	PGDocument *doc;
	NSEnumerator *const docEnum = [[[PGDocumentController sharedDocumentController] documents] objectEnumerator];
	while((doc = [docEnum nextObject])) [doc close];
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		[[PGPrefController sharedPrefController] AE_addObserver:self selector:@selector(displayScreenDidChange:) name:PGPrefControllerDisplayScreenDidChangeNotification];
	}
	return self;
}
- (void)dealloc
{
	[self PG_cancelPreviousPerformRequests];
	[self AE_removeObserver];
	[_shieldWindows makeObjectsPerformSelector:@selector(close)];
	[_shieldWindows release];
	[super dealloc];
}

#pragma mark -NSObject(NSWindowNotifications)

- (void)windowDidBecomeMain:(NSNotification *)aNotif
{
	[super windowDidBecomeMain:aNotif];
	[NSCursor setHiddenUntilMouseMoves:YES];
}
- (void)windowDidResignMain:(NSNotification *)aNotif
{
	if(!_isExitingFullscreen) [super windowDidResignMain:aNotif];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotif
{
	BOOL const dim = [[NSUserDefaults standardUserDefaults] boolForKey:PGDimOtherScreensKey]; // We shouldn't need to observe this value because our fullscreen window isn't going to be key while the user is adjusting the setting in the prefs window.
	NSScreen *const displayScreen = [[PGPrefController sharedPrefController] displayScreen];

	if(dim || [NSScreen AE_mainScreen] == displayScreen) [self PG_performSelector:@selector(_hideMenuBar) withObject:nil fireDate:nil interval:0.0f options:kNilOptions]; // Prevents the menu bar from messing up when the application unhides on Leopard.

	if(!dim) return;
	[_shieldWindows makeObjectsPerformSelector:@selector(close)];
	[_shieldWindows release];
	_shieldWindows = [[NSMutableArray alloc] init];
	NSScreen *screen;
	NSEnumerator *const screenEnum = [[NSScreen screens] objectEnumerator];
	while((screen = [screenEnum nextObject])) {
		if(displayScreen == screen) continue;
		NSWindow *const w = [[[NSWindow alloc] initWithContentRect:[screen frame] styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES] autorelease]; // Use borderless windows instead of CGSetDisplayTransferByFormula() so that 1. the menu bar remains visible (if it's on a different screen), and 2. the user can't click on things that can't be seen.
		[w setReleasedWhenClosed:NO];
		[w setBackgroundColor:[NSColor blackColor]];
		[w setHasShadow:NO];
		[w setLevel:NSFloatingWindowLevel - 1];
		[w orderFront:self];
		[_shieldWindows addObject:w];
	}
}
- (void)windowDidResignKey:(NSNotification *)aNotif
{
	if([[NSApp keyWindow] delegate] == self || [[PGPrefController sharedPrefController] displayScreen] != [NSScreen AE_mainScreen]) return;
	[self PG_cancelPreviousPerformRequestsWithSelector:@selector(_hideMenuBar) object:nil];
	SetSystemUIMode(kUIModeNormal, kNilOptions);
	[_shieldWindows makeObjectsPerformSelector:@selector(close)];
	[_shieldWindows release];
	_shieldWindows = nil;
}

#pragma mark -NSObject(PGDocumentWindowDelegate)

- (NSDragOperation)window:(PGDocumentWindow *)window
                   dragOperationForInfo:(id<NSDraggingInfo>)info
{
	if(!([info draggingSourceOperationMask] & NSDragOperationGeneric)) return NSDragOperationNone;
	NSPasteboard *const pboard = [info draggingPasteboard];
	NSArray *const types = [pboard types];
	if([types containsObject:NSFilenamesPboardType]) {
		NSArray *const paths = [pboard propertyListForType:NSFilenamesPboardType];
		return [paths count] == 1 ? NSDragOperationGeneric : NSDragOperationNone;
	} else if([types containsObject:NSURLPboardType]) {
		return [NSURL URLFromPasteboard:pboard] ? NSDragOperationGeneric : NSDragOperationNone;
	}
	return NSDragOperationNone;
}
- (BOOL)window:(PGDocumentWindow *)window
        performDragOperation:(id<NSDraggingInfo>)info
{
	NSPasteboard *const pboard = [info draggingPasteboard];
	NSArray *const types = [pboard types];
	if([types containsObject:NSFilenamesPboardType]) return !![[PGDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[[[pboard propertyListForType:NSFilenamesPboardType] lastObject] AE_fileURL] display:YES];
	else if([types containsObject:NSURLPboardType]) return !![[PGDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL URLFromPasteboard:pboard] display:YES];
	return NO;
}

#pragma mark -NSObject(PGFullscreenWindowDelegate)

- (void)closeWindowContent:(PGFullscreenWindow *)sender
{
	[[self activeDocument] close];
}

@end
