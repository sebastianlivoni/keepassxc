#include "BookmarkFile.h"

#include <Foundation/Foundation.h>
#include <MacTypes.h>
#include <QUrl>
#include <QHash>
#include <QCryptographicHash>

BookmarkFile::BookmarkFile(const QString &fileName) : QFile(fileName) { }

bool BookmarkFile::open(QIODevice::OpenMode mode)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appGroupContainerURL = [fileManager containerURLForSecurityApplicationGroupIdentifier:[NSString stringWithUTF8String:APP_GROUP_IDENTIFIER]];
    if (!appGroupContainerURL) {
        NSLog(@"BOOKMARK: Failed to get App Group container URL");
        return false;
    }

    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithUTF8String:APP_GROUP_IDENTIFIER]];
    NSString *bookmarkUserDefaultsKey = bookmarkKey();

    NSError *error = nil;
    BOOL isStale = NO;

    NSData *bookmark = [userDefaults objectForKey:bookmarkUserDefaultsKey];

    NSURL *fileURL = [NSURL fileURLWithPath:fileName().toNSString() isDirectory:false];
    if (!bookmark) {
        // No bookmark found, create one

        bookmark = [fileURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                     includingResourceValuesForKeys:nil
                                      relativeToURL:appGroupContainerURL
                                              error:&error];
        if (!bookmark) {
            NSLog(@"BOOKMARK: Failed to create bookmark: %@", error);
            return false;
        }

        NSLog(@"BOOKMARK: Creating bookmark");

        // Save bookmark to shared defaults
        [userDefaults setObject:bookmark forKey:bookmarkUserDefaultsKey];
        [userDefaults synchronize];

        // We created bookmark; attempt to open on this call
        // Continue to resolve and open below
    } else {
        NSLog(@"BOOKMARK: Bookmark already existing");
    }

    // Resolve the bookmark to get security scoped URL
    NSURL *resolvedURL = [NSURL URLByResolvingBookmarkData:bookmark
                                                    options:NSURLBookmarkResolutionWithSecurityScope | NSURLBookmarkResolutionWithoutImplicitStartAccessing
                                                    //options:0
                                              relativeToURL:appGroupContainerURL
                                        bookmarkDataIsStale:&isStale
                                                      error:&error];

    if (isStale) {
        NSLog(@"BOOKMARK: Bookmark is stale, removing");
        [userDefaults removeObjectForKey:bookmarkUserDefaultsKey];
        [userDefaults synchronize];
        return false;
    }

    if (!resolvedURL) {
        NSLog(@"BOOKMARK: Failed to resolve bookmark: %@", error);
        return false;
    }

    // Start accessing security-scoped resource
    BOOL accessStarted = [resolvedURL startAccessingSecurityScopedResource];
    if (!accessStarted) {
        NSLog(@"BOOKMARK: Failed to start accessing security-scoped resource");
        return false;
    }

    // Convert NSURL to local file path
    QString resolvedPath = QUrl::fromNSURL(resolvedURL).toLocalFile();

    // Set the file path in your QFile wrapper
    setFileName(resolvedPath);

    NSLog(@"BOOKMARK: Data: %@", bookmark);

    NSLog(@"BOOKMARK: Accessing file at %@", resolvedPath.toNSString());

    // Attempt to open the file now
    bool openSuccess = QFile::open(mode);

    if (!openSuccess) {
        NSLog(@"BOOKMARK: QFile failed to open %@", resolvedPath.toNSString());
        [resolvedURL stopAccessingSecurityScopedResource];
        return false;
    }

    // Store the resolvedURL so you can stop access later
    m_location = resolvedURL;

    return true;
}

NSString* BookmarkFile::bookmarkKey()
{
    QByteArray hash = QCryptographicHash::hash(fileName().toUtf8(), QCryptographicHash::Sha256);
    NSLog(@"BOOKMARK: File name: %@", fileName().toNSString());

    //QString hashString = "bookmark_" + hash.toHex();
    QString hashString = "bookmark";

    return hashString.toNSString();
}

void BookmarkFile::close() {
    if (m_location) {
        NSURL *location = (__bridge_transfer NSURL *)m_location;
        [location stopAccessingSecurityScopedResource];
        m_location = nil;
    }

    QFile::close();
}
