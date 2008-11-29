/* Copyright © 2007-2008, The Sequential Project
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

THIS SOFTWARE IS PROVIDED BY THE Sequential Project ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE Sequential Project BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "PGResourceIdentifier.h"

// Models
#import "PGSubscription.h"

// Other
#import "PGAttachments.h"

// Categories
#import "NSObjectAdditions.h"
#import "NSStringAdditions.h"
#import "NSURLAdditions.h"

NSString *const PGDisplayableIdentifierIconDidChangeNotification = @"PGDisplayableIdentifierIconDidChange";
NSString *const PGDisplayableIdentifierDisplayNameDidChangeNotification = @"PGDisplayableIdentifierDisplayNameDidChange";

@interface PGDisplayableIdentifier (Private)

- (id)_initWithIdentifier:(PGResourceIdentifier *)ident;

@end

@interface PGAliasIdentifier : PGResourceIdentifier <NSCoding>
{
	@private
	AliasHandle _alias;
	BOOL _hasValidRef;
	FSRef _ref;
}

- (id)initWithURL:(NSURL *)URL; // Must be a file URL.
- (id)initWithAliasData:(const uint8_t *)data length:(unsigned)length;
- (BOOL)setAliasWithData:(const uint8_t *)data length:(unsigned)length;
- (BOOL)getRef:(out FSRef *)outRef byFollowingAliases:(BOOL)follow validate:(BOOL)validate;

@end

@interface PGURLIdentifier : PGResourceIdentifier <NSCoding>
{
	@private
	NSURL *_URL;
}

- (id)initWithURL:(NSURL *)URL; // Must not be a file URL.

@end

@interface PGIndexIdentifier : PGResourceIdentifier <NSCoding>
{
	@private
	PGResourceIdentifier *_superidentifier;
	int _index;
}

- (id)initWithSuperidentifier:(PGResourceIdentifier *)identifier index:(int)index;

@end

@implementation PGResourceIdentifier

#pragma mark Class Methods

+ (id)resourceIdentifierWithURL:(NSURL *)URL
{
	return [[[([URL isFileURL] ? [PGAliasIdentifier class] : [PGURLIdentifier class]) alloc] initWithURL:URL] autorelease];
}
+ (id)resourceIdentifierWithAliasData:(const uint8_t *)data
      length:(unsigned)length
{
	return [[[PGAliasIdentifier alloc] initWithAliasData:data length:length] autorelease];
}

#pragma mark NSKeyedUnarchiverObjectSubstitution Protocol

+ (Class)classForKeyedUnarchiver
{
	return [PGDisplayableIdentifier class];
}

#pragma mark Instance Methods

- (PGResourceIdentifier *)identifier
{
	return self;
}
- (PGDisplayableIdentifier *)displayableIdentifier
{
	return [[[PGDisplayableIdentifier alloc] _initWithIdentifier:self] autorelease];
}

#pragma mark -

- (PGResourceIdentifier *)subidentifierWithIndex:(int)index
{
	return [[[PGIndexIdentifier alloc] initWithSuperidentifier:self index:index] autorelease];
}
- (PGResourceIdentifier *)superidentifier
{
	return nil;
}
- (PGResourceIdentifier *)rootIdentifier
{
	return [self superidentifier] ? [[self superidentifier] rootIdentifier] : self;
}

#pragma mark -

- (NSURL *)superURLByFollowingAliases:(BOOL)flag
{
	NSURL *const URL = [self URLByFollowingAliases:flag];
	return URL ? URL : [[self superidentifier] superURLByFollowingAliases:flag];
}
- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
	return nil;
}
- (NSURL *)URL
{
	return [self URLByFollowingAliases:NO];
}
- (BOOL)getRef:(out FSRef *)outRef
        byFollowingAliases:(BOOL)flag
{
	return NO;
}
- (int)index
{
	return NSNotFound;
}

#pragma mark -

- (BOOL)hasTarget
{
	return NO;
}
- (BOOL)isFileIdentifier
{
	return NO;
}

#pragma mark -

- (PGSubscription *)subscriptionWithDescendents:(BOOL)flag
{
	return [self isFileIdentifier] ? [PGSubscription subscriptionWithPath:[[self URL] path] descendents:flag] : nil;
}

#pragma mark NSCoding Protocol

- (id)initWithCoder:(NSCoder *)aCoder
{
	return [self init];
}
- (void)encodeWithCoder:(NSCoder *)aCoder {}

#pragma mark NSKeyedArchiverObjectSubstitution Protocol

- (Class)classForKeyedArchiver
{
	return [PGResourceIdentifier class];
}

#pragma mark NSObject Protocol

- (unsigned)hash
{
	return [[self class] hash] ^ (unsigned)[self index];
}
- (BOOL)isEqual:(id)obj
{
	if(obj == self) return YES;
	if([obj isKindOfClass:[PGDisplayableIdentifier class]]) return [self isEqual:[obj identifier]];
	return [obj isKindOfClass:[self class]] && [(PGResourceIdentifier *)obj index] == [self index] && [[self superidentifier] isEqual:[obj superidentifier]];
}

#pragma mark -

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@:%d", [self URL], [self index]];
}

@end

@implementation PGDisplayableIdentifier

#pragma mark PGResourceIdentifier

+ (id)resourceIdentifierWithURL:(NSURL *)URL
{
	return [[[self alloc] _initWithIdentifier:[super resourceIdentifierWithURL:URL]] autorelease];
}
+ (id)resourceIdentifierWithAliasData:(const uint8_t *)data
      length:(unsigned)length
{
	return [[[self alloc] _initWithIdentifier:[super resourceIdentifierWithAliasData:data length:length]] autorelease];
}

#pragma mark Instance Methods

- (NSImage *)icon
{
	return _icon ? [[_icon retain] autorelease] : [[self URL] AE_icon];
}
- (void)setIcon:(NSImage *)icon
        notify:(BOOL)flag
{
	if(icon == _icon) return;
	[_icon release];
	_icon = [icon retain];
	if(flag) [self AE_postNotificationName:PGDisplayableIdentifierIconDidChangeNotification];
}

#pragma mark -

- (NSString *)displayName
{
	return _customDisplayName ? [[_customDisplayName retain] autorelease] : [self naturalDisplayName];
}
- (NSString *)naturalDisplayName
{
	if(!_naturalDisplayName) [self updateNaturalDisplayNameNotify:YES];
	if(_naturalDisplayName) return [[_naturalDisplayName retain] autorelease];
	return @"";
}
- (void)setNaturalDisplayName:(NSString *)aString
        notify:(BOOL)flag
{
	if(!aString || aString == _naturalDisplayName || [aString isEqualToString:_naturalDisplayName]) return;
	[_naturalDisplayName release];
	_naturalDisplayName = [aString copy];
	if(flag && !_customDisplayName) [self AE_postNotificationName:PGDisplayableIdentifierDisplayNameDidChangeNotification];
}
- (void)setCustomDisplayName:(NSString *)aString
        notify:(BOOL)flag
{
	NSString *const string = [@"" isEqualToString:aString] ? nil : aString;
	if(string == _customDisplayName || [string isEqualToString:_customDisplayName]) return;
	[_customDisplayName release];
	_customDisplayName = [string copy];
	if(flag) [self AE_postNotificationName:PGDisplayableIdentifierDisplayNameDidChangeNotification];
}
- (void)updateNaturalDisplayNameNotify:(BOOL)flag
{
	NSString *name = nil;
	NSURL *const URL = [self URL];
	if(URL) {
		if(LSCopyDisplayNameForURL((CFURLRef)URL, (CFStringRef *)&name) == noErr && name) [name autorelease];
		else {
			NSString *const path = [URL path];
			name = [@"/" isEqualToString:path] ? [URL absoluteString] : [path lastPathComponent];
		}
	}
	[self setNaturalDisplayName:name notify:flag];
}

#pragma mark -

- (NSAttributedString *)attributedStringWithWithAncestory:(BOOL)flag
{
	NSMutableAttributedString *const result = [NSMutableAttributedString PG_attributedStringWithFileIcon:[self icon] name:[self displayName]];
	if(!flag) return result;
	NSURL *const URL = [self URL];
	if(!URL) return result;
	NSString *const parent = [URL isFileURL] ? [[URL path] stringByDeletingLastPathComponent] : [URL absoluteString];
	NSString *const parentName = [URL isFileURL] ? [parent lastPathComponent] : parent;
	if(!parentName || [parentName isEqual:@""]) return result;
	[[result mutableString] appendString:[NSString stringWithFormat:@" %C ", 0x2014]];
	[result appendAttributedString:[NSAttributedString PG_attributedStringWithFileIcon:([URL isFileURL] ? [[parent AE_fileURL] AE_icon] : nil) name:parentName]];
	return result;
}
- (PGLabelColor)labelColor
{
	FSRef ref;
	FSCatalogInfo catalogInfo;
	if(![self getRef:&ref byFollowingAliases:NO] || FSGetCatalogInfo(&ref, kFSCatInfoFinderInfo | kFSCatInfoNodeFlags, &catalogInfo, NULL, NULL, NULL) != noErr) return PGLabelNone;
	UInt16 finderFlags;
	if(catalogInfo.nodeFlags & kFSNodeIsDirectoryMask) finderFlags = ((FolderInfo *)&catalogInfo.finderInfo)->finderFlags;
	else finderFlags = ((FileInfo *)&catalogInfo.finderInfo)->finderFlags;
	return (finderFlags & 0x0E) >> 1;
}

#pragma mark Private Protocol

- (id)_initWithIdentifier:(PGResourceIdentifier *)ident
{
	if((self = [super init])) {
		NSParameterAssert(![ident isKindOfClass:[PGDisplayableIdentifier class]]);
		_identifier = [ident retain];
	}
	return self;
}

#pragma mark NSCoding Protocol

- (id)initWithCoder:(NSCoder *)aCoder
{
	Class const class = NSClassFromString([aCoder decodeObjectForKey:@"ClassName"]);
	if(!class) {
		[self release];
		return nil;
	}
	id ident = nil;
	if([self class] == class) {
		ident = [[[PGAliasIdentifier alloc] initWithCoder:aCoder] autorelease];
		if(!ident) ident = [[[PGURLIdentifier alloc] initWithCoder:aCoder] autorelease];
		if(!ident) ident = [[[PGIndexIdentifier alloc] initWithCoder:aCoder] autorelease];
	} else ident = [[[class alloc] initWithCoder:aCoder] autorelease];
	if(!(self = [self _initWithIdentifier:ident])) return nil;
	[self setIcon:[aCoder decodeObjectForKey:@"Icon"] notify:NO];
	[self setCustomDisplayName:[aCoder decodeObjectForKey:@"DisplayName"] notify:NO];
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[_identifier encodeWithCoder:aCoder]; // For backward compatibility, we can't use encodeObject:forKey:, so encode it directly.
	[aCoder encodeObject:NSStringFromClass([_identifier class]) forKey:@"ClassName"];
	[aCoder encodeObject:_icon forKey:@"Icon"];
	[aCoder encodeObject:_customDisplayName forKey:@"DisplayName"];
}

#pragma mark NSObject Protocol

- (unsigned)hash
{
	return [_identifier hash];
}
- (BOOL)isEqual:(id)obj
{
	return [_identifier isEqual:obj];
}

#pragma mark -

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: %@:%d (\"%@\")>", [self class], self, [self URL], [self index], [self displayName]];
}

#pragma mark PGResourceIdentifier

- (PGResourceIdentifier *)identifier
{
	return [_identifier identifier];
}
- (PGDisplayableIdentifier *)displayableIdentifier
{
	return self;
}

#pragma mark -

- (PGResourceIdentifier *)subidentifierWithIndex:(int)index
{
	return [_identifier subidentifierWithIndex:index];
}
- (PGResourceIdentifier *)superidentifier
{
	return [_identifier superidentifier];
}
- (PGResourceIdentifier *)rootIdentifier
{
	return [_identifier rootIdentifier];
}

#pragma mark -

- (NSURL *)superURLByFollowingAliases:(BOOL)flag
{
	return [_identifier superURLByFollowingAliases:flag];
}
- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
	return [_identifier URLByFollowingAliases:flag];
}
- (NSURL *)URL
{
	return [_identifier URL];
}
- (BOOL)getRef:(out FSRef *)outRef
        byFollowingAliases:(BOOL)flag
{
	return [_identifier getRef:outRef byFollowingAliases:flag];
}
- (int)index
{
	return [_identifier index];
}

#pragma mark -

- (BOOL)hasTarget
{
	return [_identifier hasTarget];
}
- (BOOL)isFileIdentifier
{
	return [_identifier isFileIdentifier];
}

#pragma mark -

- (PGSubscription *)subscriptionWithDescendents:(BOOL)flag
{
	return [_identifier subscriptionWithDescendents:flag];
}

#pragma mark NSObject

- (void)dealloc
{
	[_identifier release];
	[_icon release];
	[_naturalDisplayName release];
	[_customDisplayName release];
	[super dealloc];
}

@end

@implementation PGAliasIdentifier

#pragma mark Instance Methods

- (id)initWithURL:(NSURL *)URL
{
	NSParameterAssert([URL isFileURL]);
	if((self = [super init])) {
		if(!CFURLGetFSRef((CFURLRef)URL, &_ref) || FSNewAliasMinimal(&_ref, &_alias) != noErr) {
			[self release];
			return [[PGURLIdentifier alloc] initWithURL:URL];
		}
		_hasValidRef = YES;
	}
	return self;
}
- (id)initWithAliasData:(const uint8_t *)data
      length:(unsigned)length
{
	if((self = [super init])) {
		if(![self setAliasWithData:data length:length]) {
			[self release];
			return nil;
		}
	}
	return self;
}
- (BOOL)setAliasWithData:(const uint8_t *)data
        length:(unsigned)length
{
	if(!data || !length) return NO;
	_alias = (AliasHandle)NewHandle(length);
	if(!_alias) return NO;
	memcpy(*_alias, data, length);
	return YES;
}
- (BOOL)getRef:(out FSRef *)outRef
        byFollowingAliases:(BOOL)follow
        validate:(BOOL)validate
{
	NSParameterAssert(outRef);
	Boolean dontCare1, dontCare2;
	if(validate && _hasValidRef && !follow) _hasValidRef = FSIsFSRefValid(&_ref);
	if(!_hasValidRef && FSResolveAliasWithMountFlags(NULL, _alias, &_ref, &dontCare1, kResolveAliasFileNoUI) != noErr) return NO;
	_hasValidRef = YES;
	*outRef = _ref;
	return follow ? FSResolveAliasFileWithMountFlags(outRef, true, &dontCare1, &dontCare2, kResolveAliasFileNoUI) == noErr : YES;
}

#pragma mark NSCoding Protocol

- (id)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super initWithCoder:aCoder])) {
		unsigned length;
		uint8_t const *const data = [aCoder decodeBytesForKey:@"Alias" returnedLength:&length];
		if(![self setAliasWithData:data length:length]) {
			[self release];
			return nil;
		}
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	if(_alias) [aCoder encodeBytes:(uint8_t const *)*_alias length:GetHandleSize((Handle)_alias) forKey:@"Alias"];
}

#pragma mark NSObject Protocol

- (unsigned)hash
{
	return [[self class] hash];
}
- (BOOL)isEqual:(id)obj
{
	if(obj == self) return YES;
	if(![obj isKindOfClass:[PGAliasIdentifier class]]) return [super isEqual:obj];
	FSRef ourRef, theirRef;
	if(![self getRef:&ourRef byFollowingAliases:NO validate:NO] || ![obj getRef:&theirRef byFollowingAliases:NO validate:NO]) return NO;
	return FSCompareFSRefs(&ourRef, &theirRef) == noErr;
}

#pragma mark PGResourceIdentifier

- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
	FSRef ref;
	if(![self getRef:&ref byFollowingAliases:flag]) return nil;
	return [(NSURL *)CFURLCreateFromFSRef(kCFAllocatorDefault, &ref) autorelease];
}
- (BOOL)getRef:(out FSRef *)outRef
        byFollowingAliases:(BOOL)flag
{
	return [self getRef:outRef byFollowingAliases:flag validate:YES];
}
- (BOOL)hasTarget
{
	FSRef ref;
	return [self getRef:&ref byFollowingAliases:NO validate:YES];
}
- (BOOL)isFileIdentifier
{
	return YES;
}

#pragma mark NSObject

- (void)dealloc
{
	if(_alias) DisposeHandle((Handle)_alias);
	[super dealloc];
}

@end

@implementation PGURLIdentifier

#pragma mark Instance Methods

- (id)initWithURL:(NSURL *)URL
{
	if((self = [super init])) {
		_URL = [URL retain];
	}
	return self;
}

#pragma mark NSCoding Protocol

- (id)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super initWithCoder:aCoder])) {
		_URL = [[aCoder decodeObjectForKey:@"URL"] retain];
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_URL forKey:@"URL"];
}

#pragma mark PGResourceIdentifier

- (NSURL *)URLByFollowingAliases:(BOOL)flag
{
	return [[_URL retain] autorelease];
}
- (BOOL)hasTarget
{
	return YES;
}
- (BOOL)isFileIdentifier
{
	return [_URL isFileURL];
}

#pragma mark NSObject

- (void)dealloc
{
	[_URL release];
	[super dealloc];
}

@end

@implementation PGIndexIdentifier

#pragma mark Instance Methods

- (id)initWithSuperidentifier:(PGResourceIdentifier *)identifier
      index:(int)index
{
	if((self = [super init])) {
		_superidentifier = [identifier retain];
		_index = index;
	}
	return self;
}

#pragma mark NSCoding Protocol

- (id)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super initWithCoder:aCoder])) {
		_superidentifier = [[aCoder decodeObjectForKey:@"Superidentifier"] retain];
		_index = [aCoder decodeIntForKey:@"Index"];
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_superidentifier forKey:@"Superidentifier"];
	[aCoder encodeInt:_index forKey:@"Index"];
}

#pragma mark PGResourceIdentifier

- (PGResourceIdentifier *)superidentifier
{
	return [[_superidentifier retain] autorelease];
}
- (int)index
{
	return _index;
}
- (BOOL)hasTarget
{
	return NSNotFound != _index && [_superidentifier hasTarget];
}
- (BOOL)isFileIdentifier
{
	return [_superidentifier isFileIdentifier];
}

#pragma mark NSObject

- (void)dealloc
{
	[_superidentifier release];
	[super dealloc];
}

@end

@implementation NSURL (PGResourceIdentifierCreation)

- (PGResourceIdentifier *)PG_resourceIdentifier
{
	return [PGResourceIdentifier resourceIdentifierWithURL:self];
}
- (PGDisplayableIdentifier *)PG_displayableIdentifier
{
	return [[[PGDisplayableIdentifier alloc] _initWithIdentifier:[self PG_resourceIdentifier]] autorelease];
}

@end
