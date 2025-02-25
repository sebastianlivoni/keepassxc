#include "BookmarkFile.h"

#include <Foundation/Foundation.h>
#include <QUrl>
#include <QHash>
#include <QCryptographicHash>

BookmarkFile::BookmarkFile(const QString &fileName) : QFile(fileName) { }

bool BookmarkFile::open(QIODevice::OpenMode mode)
{
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:QString::fromUtf8(APP_GROUP_IDENTIFIER).toNSString()];

    BOOL isStale = NO;
    NSError *error = nil;

    NSString *fileNameKey = bookmarkKey();

    NSData *bookmark = [userDefaults objectForKey:fileNameKey];

    if (bookmark == nil) {
        NSURL *fileURL = [NSURL fileURLWithPath:fileName().toNSString()];

        bookmark = [fileURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:0 relativeToURL:0 error:&error];

        [userDefaults setObject:bookmark forKey:fileNameKey];
        [userDefaults synchronize];
    }

    NSURL *location = [NSURL URLByResolvingBookmarkData:bookmark
                                                options:NSURLBookmarkResolutionWithSecurityScope
                                          relativeToURL:0
                                    bookmarkDataIsStale:&isStale
                                                  error:&error];

    if (isStale) {
        [userDefaults setObject:nil forKey:fileNameKey];
        [userDefaults synchronize];
        return false;
    }

    if (location == nil) {
        // If resolving bookmark fails, return failure.
        return false;
    }

    [location startAccessingSecurityScopedResource];

    QString securityScopedURL = QUrl::fromNSURL(location).toLocalFile();

    setFileName(securityScopedURL);

    NSLog(@"Successfully created security scoped URL %@", securityScopedURL.toNSString());

    return QFile::open(mode);
}

NSString* BookmarkFile::bookmarkKey()
{
    QByteArray hash = QCryptographicHash::hash(fileName().toUtf8(), QCryptographicHash::Sha256);

    QString hashString = "bookmark_" + hash.toHex();
    
    return hashString.toNSString();
}

void BookmarkFile::close() {
    /*NSLog(@"Stop accessing: close");
    NSURL *bookmarkURL = [NSURL fileURLWithPath:fileName().toNSString()];

    [bookmarkURL stopAccessingSecurityScopedResource];*/
}