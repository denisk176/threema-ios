//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2015-2025 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

#import "BundleUtil.h"

@implementation BundleUtil

+ (NSBundle *)frameworkBundle {
    NSBundle *frameworkBundle = [NSBundle bundleWithIdentifier:THREEMA_FRAMEWORK_IDENTIFIER];
    return frameworkBundle;
}

+ (NSBundle *)mainBundle {
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *url;
    while (![[bundle.bundleURL pathExtension] isEqualToString:@"app"]) {
        url = [bundle.bundleURL URLByDeletingLastPathComponent];
        if (!url) {
            return nil;
        }
        bundle = [NSBundle bundleWithURL:url];
    }
    return bundle;
}

+ (NSBundle *)shareExtensionBundle {
    NSString *shareExtensionIdentifier = [NSString stringWithFormat:@"%@.ThreemaShareExtension", [BundleUtil threemaAppIdentifier]];
    return [NSBundle bundleWithIdentifier:shareExtensionIdentifier];
}

+ (NSBundle *)notificationExtensionBundle {
    NSString *notificationExtensionIdentifier = [NSString stringWithFormat:@"%@.ThreemaNotificationExtension", [BundleUtil threemaAppIdentifier]];
    return [NSBundle bundleWithIdentifier:notificationExtensionIdentifier];
}

+ (NSString *)threemaAppGroupIdentifier {
    NSAssert([[BundleUtil mainBundle] objectForInfoDictionaryKey:@"ThreemaAppGroupIdentifier"] != nil, @"Bundle ThreemaAppGroupIdentifier not set");
    return [[BundleUtil mainBundle] objectForInfoDictionaryKey:@"ThreemaAppGroupIdentifier"];
}

+ (NSString *)threemaAppIdentifier {
    return [[BundleUtil mainBundle] objectForInfoDictionaryKey:@"ThreemaAppIdentifier"];
}

+ (id)objectForInfoDictionaryKey:(NSString *)key {
    id value = [[self frameworkBundle] objectForInfoDictionaryKey:key];
    if (value == nil) {
        // fall back to main bundle
        value = [[NSBundle mainBundle] objectForInfoDictionaryKey:key];
    }

    return value;
}

+ (NSString *)pathForResource:(NSString *)resource ofType:(NSString *)type {
    NSString *path = [[self frameworkBundle] pathForResource:resource ofType:type];

    if (path == nil) {
        // fall back to main bundle
        path = [[NSBundle mainBundle] pathForResource:resource ofType:type];
    }
    
    return path;
}

+ (NSURL *)URLForResource:(NSString *)resourceName withExtension:(NSString *)extension {
    NSURL *url =  [[self frameworkBundle] URLForResource:resourceName withExtension:extension];
    if (url == nil) {
        // fall back to main bundle
        url = [[NSBundle mainBundle] URLForResource:resourceName withExtension:extension];
    }
    
    return url;
}

+ (UIImage *)imageNamed:(NSString *)imageName {
    NSBundle *frameworkBundle = [self frameworkBundle];
    UIImage *image;
    
    if ([UIImage respondsToSelector:@selector(imageNamed:inBundle:compatibleWithTraitCollection:)])
    {
        image = [UIImage imageNamed:imageName inBundle:frameworkBundle compatibleWithTraitCollection:nil];
    } else {
        image = [UIImage imageNamed:[NSString stringWithFormat:@"ThreemaFramework.bundle/%@", imageName]];
    }

    if (image) {
        return image;
    }
    
    image = [UIImage imageNamed:imageName inBundle:[self mainBundle] compatibleWithTraitCollection:nil];
    
    if (image) {
        return image;
    }

    image = [UIImage imageNamed:imageName];

    if (image) {
        return image;
    }

    NSString *path = [frameworkBundle pathForResource:imageName ofType:nil];
    if ([path length] > 0) {
        image = [UIImage imageWithContentsOfFile:path];
    }
    
    if (image) {
        return image;
    }
    
    // Try loading SF Symbol if we couldn't find the image so far
    image = [UIImage systemImageNamed:imageName];

    return image;
}

+ (NSString *)localizedStringForKey:(NSString *)key {
    NSString *value = NSLocalizedString(key, nil);

    if (value && [value isEqualToString:key] == NO) {
        return value;
    }
    else {
        return [BundleUtil enLocalizedStringForKey:value];
    }
}

/// Get the english localized string for backup
/// If the key can't be found in the english translations, it will return the key itself
/// @param key Key of the localized string
+ (NSString *)enLocalizedStringForKey:(NSString *)key {
    NSString *value = key;

    NSString *enPath = [[self mainBundle] pathForResource:@"en" ofType:@"lproj"];
    if (enPath == nil) {
        return key;
    }

    id enBundle = [NSBundle bundleWithPath:enPath];
    if ((value = NSLocalizedStringFromTableInBundle(key, nil, enBundle, nil)) && ([value isEqualToString:key] == NO)) {
        return value;
    }
    else {
        return key;
    }
}


+ (UIView *)loadXibNamed:(NSString *)name {
    NSBundle *bundle = [NSBundle mainBundle];
    NSArray *nibs =  [bundle loadNibNamed:name owner:self options:nil];
    if (nibs == nil) {
        // fall back to main bundle
        nibs = [[NSBundle mainBundle] loadNibNamed:name owner:self options:nil];
    }

    UIView *view = [nibs objectAtIndex:0];
    
    return view;
}

@end
