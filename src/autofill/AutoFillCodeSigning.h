// AutoFillCodeSigning.h

#include <Foundation/Foundation.h>

static inline NSString *CodeSigningRequirement(NSString *identifier) {
    return [NSString stringWithFormat:
        @"anchor apple generic and identifier \"%@\" %s",
        identifier, DESIGNATED_REQUIREMENT];
}

static inline NSString *CodeSigningRequirementForIdentifiers(NSArray<NSString *> *identifiers) {
    NSString *joined = [identifiers componentsJoinedByString:@"\" or identifier \""];
    return [NSString stringWithFormat:
        @"anchor apple generic and (identifier \"%@\") %s",
        joined, DESIGNATED_REQUIREMENT];
}
