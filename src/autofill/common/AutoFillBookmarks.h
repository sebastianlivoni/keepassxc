#ifndef KEEPASSXC_AUTOFILLBOOKMARKS_H
#define KEEPASSXC_AUTOFILLBOOKMARKS_H

#import <Foundation/Foundation.h>

#include <QString>

// Lets the sandboxed extension open database and key files: KeePassXC stores security-scoped
// bookmarks for them, relative to a host file in the shared app group container
namespace AutoFillBookmarks
{
    namespace Detail
    {
        inline NSURL* groupContainer()
        {
            return
                [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:@APP_GROUP_IDENTIFIER];
        }

        // Same directory as the KeePassXC config (see Config.cpp)
        inline NSURL* storageDir()
        {
            return [groupContainer() URLByAppendingPathComponent:@"Library/Application Support/KeePassXC"
                                                     isDirectory:YES];
        }

        inline NSURL* hostDocument()
        {
            return [storageDir() URLByAppendingPathComponent:@"AutoFillBookmarkHost"];
        }

        inline NSURL* storeURL()
        {
            return [storageDir() URLByAppendingPathComponent:@"AutoFillBookmarks.plist"];
        }

        inline NSMutableDictionary* loadStore()
        {
            return [[NSDictionary dictionaryWithContentsOfURL:storeURL()] mutableCopy]
                       ?: [NSMutableDictionary dictionary];
        }

        inline NSData* createBookmark(const QString& path)
        {
            if (path.isEmpty()) {
                return nil;
            }
            NSError* error = nil;
            NSData* bookmark = [[NSURL fileURLWithPath:path.toNSString()]
                       bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                includingResourceValuesForKeys:nil
                                 relativeToURL:hostDocument()
                                         error:&error];
            if (!bookmark) {
                NSLog(@"AutoFill: failed to create bookmark for %@: %@", path.toNSString(), error);
            }
            return bookmark;
        }

        // Resolves and starts access; access is kept for the rest of the (short-lived) extension process
        inline QString resolveAndStartAccess(NSData* bookmark)
        {
            if (!bookmark) {
                return {};
            }
            BOOL stale = NO;
            NSError* error = nil;
            NSURL* url = [NSURL URLByResolvingBookmarkData:bookmark
                                                   options:NSURLBookmarkResolutionWithSecurityScope
                                             relativeToURL:hostDocument()
                                       bookmarkDataIsStale:&stale
                                                     error:&error];
            if (!url || ![url startAccessingSecurityScopedResource]) {
                NSLog(@"AutoFill: failed to resolve bookmark: %@", error);
                return {};
            }
            return QString::fromNSString(url.path);
        }
    } // namespace Detail

    // KeePassXC: remember access to an AutoFill database and its key file (if any)
    inline void save(const QString& dbUuidHex, const QString& databasePath, const QString& keyFilePath)
    {
        if (!Detail::groupContainer() || dbUuidHex.isEmpty()) {
            return;
        }
        [NSFileManager.defaultManager createDirectoryAtURL:Detail::storageDir()
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:nil];
        NSURL* host = Detail::hostDocument();
        if (![NSFileManager.defaultManager fileExistsAtPath:host.path]) {
            [[NSData data] writeToURL:host atomically:YES];
        }

        NSData* database = Detail::createBookmark(databasePath);
        if (!database) {
            return;
        }
        NSMutableDictionary* entry = [NSMutableDictionary dictionaryWithObject:database forKey:@"database"];
        if (NSData* keyFile = Detail::createBookmark(keyFilePath)) {
            entry[@"keyFile"] = keyFile;
        }

        NSMutableDictionary* store = Detail::loadStore();
        store[dbUuidHex.toNSString()] = entry;
        [store writeToURL:Detail::storeURL() atomically:YES];
    }

    // KeePassXC: forget a database (e.g. excluded from AutoFill)
    inline void remove(const QString& dbUuidHex)
    {
        NSMutableDictionary* store = Detail::loadStore();
        if (store[dbUuidHex.toNSString()]) {
            [store removeObjectForKey:dbUuidHex.toNSString()];
            [store writeToURL:Detail::storeURL() atomically:YES];
        }
    }

    // Extension: open access to a database; returns its current path (empty if KeePassXC
    // has not shared it yet) and, if remembered, the accessible key file path
    inline QString startAccess(const QString& dbUuidHex, QString* keyFilePath = nullptr)
    {
        NSDictionary* entry = [NSDictionary dictionaryWithContentsOfURL:Detail::storeURL()][dbUuidHex.toNSString()];
        const QString databasePath = Detail::resolveAndStartAccess(entry[@"database"]);
        if (keyFilePath && !databasePath.isEmpty()) {
            *keyFilePath = Detail::resolveAndStartAccess(entry[@"keyFile"]);
        }
        return databasePath;
    }
} // namespace AutoFillBookmarks

#endif // KEEPASSXC_AUTOFILLBOOKMARKS_H
