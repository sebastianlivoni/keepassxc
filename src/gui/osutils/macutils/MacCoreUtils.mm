#import <Foundation/Foundation.h>
#include <QString>

namespace MacCoreUtils {
QString getAppGroupContainerPath(const QString& appGroupId)
{
    @autoreleasepool {
        NSString *groupId = appGroupId.toNSString();
        NSURL *containerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupId];
        if (containerURL) {
            return QString::fromNSString([containerURL path]);
        }
    }
    return QString();
}
}