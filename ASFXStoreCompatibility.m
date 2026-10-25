#import "ASFXStoreCompatibility.h"

static NSURL *ASFXAuthenticateURL(NSURL *url);



static BOOL ASFXIsHistoricalStoreHost(NSString *host) {
    if ([host isEqualToString:@"ax.init.itunes.apple.com"])
        return YES;
    return [host isEqualToString:@"phobos.apple.com"];
}

static BOOL ASFXIsStoreSessionPath(NSString *path) {
    if ([path length] == 0) {
        return NO;
    }

    return [path rangeOfString:@"/bag.xml" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [path rangeOfString:@"/WebObjects/MZInit.woa/" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

NSURL *ASFXStoreURLForRequest(NSURL *url) {
    if (url == nil) {
        return nil;
    }

    NSString *host = [[url host] lowercaseString];
    NSString *path = [url path];
    if (!ASFXIsHistoricalStoreHost(host) || !ASFXIsStoreSessionPath(path)) {
        return ASFXAuthenticateURL(url);
    }



    NSString *scheme = [[url scheme] lowercaseString];
    if ([scheme isEqualToString:@"http"]) {
        return url;
    }

    NSMutableString *rewritten = [NSMutableString stringWithString:@"https://init.itunes.apple.com"];
    [rewritten appendString:path ?: @"/"];

    NSString *query = [url query];
    if ([query length] != 0) {
        [rewritten appendFormat:@"?%@", query];
    }

    NSURL *result = [NSURL URLWithString:rewritten];
    if (result != nil) {
        NSLog(@"[AppStoreFix] URL bag endpoint: %@ -> %@", url, result);
        return result;
    }

    return url;
}

static NSString *const ASFXAuthenticatePath = @"/WebObjects/MZFinance.woa/wa/authenticate";


// Discovered by Pod, see NewerStoreLoginFix. Thank you Pod
static NSURL *ASFXAuthenticateURL(NSURL *url) {
    if (![[[url host] lowercaseString] hasSuffix:@"buy.itunes.apple.com"]) {
        return url;
    }


    NSString *absolute = [url absoluteString];
    NSRange path = [absolute rangeOfString:ASFXAuthenticatePath];
    if (path.location == NSNotFound) {
        return url;
    }

    NSUInteger end = NSMaxRange(path);
    if (end < [absolute length] && [absolute characterAtIndex:end] != '?') {
        return url;
    }

    NSString *rewritten = [absolute stringByReplacingCharactersInRange:NSMakeRange(end, 0) withString:@"/"];
    NSURL *result = [NSURL URLWithString:rewritten];
    if (result == nil) {
        return url;
    }

    NSLog(@"[AppStoreFix] authenticate endpoint: %@ -> %@", url, result);
    return result;
}

// Same bag key NewerStoreLoginFix patches. Thank you again Pod.
id ASFXPrepareStoreURLBagValue(NSString *key, id value) {
    if (![key isEqualToString:@"authenticateAccount"]) {
        return value;
    }

    if ([value isKindOfClass:[NSURL class]]) {
        return ASFXAuthenticateURL(value);
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSURL *url = [NSURL URLWithString:value];
        NSURL *rewritten = ASFXAuthenticateURL(url);
        return rewritten != url ? [rewritten absoluteString] : value;
    }
    return value;
}

static const double ASFXCoreFoundationVersionIOS4 = 550.32;
static const double ASFXCoreFoundationVersionIOS6 = 793.00;


static NSString *ASFXNativeStoreFrontPlatform(void) {
    if (kCFCoreFoundationVersionNumber >= ASFXCoreFoundationVersionIOS6) {
        return @",16";
    }
    if (kCFCoreFoundationVersionNumber >= ASFXCoreFoundationVersionIOS4) {
        return @",2";
    }
    return @",4";
}



NSString *ASFXRepairStoreFront(NSString *storeFront) {
    NSRange platform = [storeFront rangeOfString:@",22"];
    if (platform.location == NSNotFound) {
        return storeFront;
    }

    NSUInteger end = NSMaxRange(platform);
    if (end < [storeFront length] &&
        [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[storeFront characterAtIndex:end]]) {
        return storeFront;
    }

    return [storeFront stringByReplacingCharactersInRange:platform withString:ASFXNativeStoreFrontPlatform()];
}

NSMutableURLRequest *ASFXPrepareStoreRequest(NSMutableURLRequest *request) {
    if (![request isKindOfClass:[NSMutableURLRequest class]]) {
        return request;
    }

    NSString *requestStoreFront = [request valueForHTTPHeaderField:@"X-Apple-Store-Front"];
    NSString *repairedStoreFront = ASFXRepairStoreFront(requestStoreFront);
    if (requestStoreFront != nil && ![repairedStoreFront isEqualToString:requestStoreFront]) {
        [request setValue:repairedStoreFront forHTTPHeaderField:@"X-Apple-Store-Front"];
    }

    NSURL *url = [request URL];
    NSString *absolute = [url absoluteString];
    if ([absolute rangeOfString:@"/WebObjects/MZStore.woa/wa/search"].location != NSNotFound) {
        NSString *rewritten = [absolute stringByReplacingOccurrencesOfString:@"MZStore.woa"
                                                                    withString:@"MZSearch.woa"];
        NSString *storeFront = [request valueForHTTPHeaderField:@"X-Apple-Store-Front"];
        if ([storeFront hasSuffix:@",4"]) {
            storeFront = [storeFront stringByReplacingOccurrencesOfString:@",4" withString:@",2"];
            [request setValue:storeFront forHTTPHeaderField:@"X-Apple-Store-Front"];
            if ([rewritten rangeOfString:@"submit=edit&clientApplication=Software"].location != NSNotFound &&
                [rewritten rangeOfString:@"media=software"].location == NSNotFound) {
                rewritten = [rewritten stringByAppendingString:@"&media=software"];
            }
        }

        NSURL *searchURL = [NSURL URLWithString:rewritten];
        if (searchURL != nil) {
            [request setURL:searchURL];
            NSLog(@"[AppStoreFix] search endpoint rewritten: %@ -> %@", url, searchURL);
        }
    } else if ([absolute rangeOfString:@"/WebObjects/MZBuy.woa/wa/buyProduct"].location != NSNotFound &&
               [[request HTTPMethod] isEqualToString:@"POST"] &&
               [request valueForHTTPHeaderField:@"Content-Type"] == nil) {
        [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    }

    return request;
}

static BOOL ASFXPreferenceEnabled(NSString *key) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.victorlobe.appstorefix.plist"];
    return [[prefs objectForKey:key] boolValue];
}

static BOOL ASFXIsGeniusTab(id tab) {
    if (![tab isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    return [[tab objectForKey:@"canonical-name"] isEqual:@"genius"] ||
        [[tab objectForKey:@"url-bag-key"] isEqual:@"p2-panda-appRecommendations"];
}


// For Genius
static NSArray *ASFXSectionIdentifiers(NSDictionary *dictionary) {
    id tabs = [dictionary objectForKey:@"tabs"];
    if ([tabs isKindOfClass:[NSDictionary class]]) {
        return ASFXSectionIdentifiers(tabs);
    }
    if (![tabs isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSMutableArray *identifiers = [NSMutableArray array];
    for (id tab in tabs) {
        id identifier = [tab isKindOfClass:[NSDictionary class]] ? [tab objectForKey:@"canonical-name"] : nil;
        if ([identifier isKindOfClass:[NSString class]]) {
            [identifiers addObject:identifier];
        }
    }
    return identifiers;
}


static void ASFXResetStaleTabOrdering(NSDictionary *dictionary) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *ordering = [defaults arrayForKey:@"SURootSections"];
    NSArray *identifiers = ASFXSectionIdentifiers(dictionary);
    if (ordering == nil || [identifiers count] == 0 || [ordering isEqualToArray:identifiers]) {
        return;
    }
    if (![ordering containsObject:@"genius"] && ![identifiers containsObject:@"genius"]) {
        return;
    }

    [defaults removeObjectForKey:@"SURootSections"];
    [defaults synchronize];
    NSLog(@"[AppStoreFix] tab ordering reset: %@ -> %@",
          [ordering componentsJoinedByString:@","], [identifiers componentsJoinedByString:@","]);
}



static void ASFXResetGeniusNavigationPath(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *path = [defaults dataForKey:@"SUSectionNavigationPath"];
    NSData *genius = [@"p2-panda-appRecommendations" dataUsingEncoding:NSUTF8StringEncoding];
    if (path == nil || [path rangeOfData:genius options:0 range:NSMakeRange(0, [path length])].location == NSNotFound) {
        return;
    }
    
    
    [defaults removeObjectForKey:@"SUSectionNavigationPath"];
    [defaults synchronize];
    NSLog(@"[AppStoreFix] saved Genius page dropped");
}

NSDictionary *ASFXPrepareStoreSectionsDictionary(NSDictionary *dictionary) {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return dictionary;
    }
    if (!ASFXPreferenceEnabled(@"HideGeniusTab")) {
        ASFXResetStaleTabOrdering(dictionary);
        return dictionary;
    }
    
    id tabs = [dictionary objectForKey:@"tabs"];
    id filteredTabs = tabs;
    if ([tabs isKindOfClass:[NSDictionary class]]) {
        filteredTabs = ASFXPrepareStoreSectionsDictionary(tabs);
    } else if ([tabs isKindOfClass:[NSArray class]]) {
        NSIndexSet *genius = [tabs indexesOfObjectsPassingTest:^BOOL(id tab, NSUInteger index, BOOL *stop) {
            return ASFXIsGeniusTab(tab);
        }];
        if ([genius count] != 0) {
            NSMutableArray *remaining = [tabs mutableCopy];
            [remaining removeObjectsAtIndexes:genius];
            filteredTabs = remaining;
            NSLog(@"[AppStoreFix] Genius tab hidden");
        }
    }

    if (filteredTabs == tabs) {
        return dictionary;
    }

    NSMutableDictionary *filtered = [dictionary mutableCopy];
    [filtered setObject:filteredTabs forKey:@"tabs"];
    ASFXResetStaleTabOrdering(filtered);
    ASFXResetGeniusNavigationPath();
    return filtered;
}

static BOOL ASFXDictionaryLooksLikeStoreBag(NSDictionary *dictionary) {
    if (dictionary == nil) {
        return NO;
    }

    NSArray *markers = @[
        @"certs",
        @"protocols",
        @"urls",
        @"storefront",
        @"storefront-version",
        @"country-code"
    ];
    for (NSString *key in markers) {
        if ([dictionary objectForKey:key] != nil) {
            return YES;
        }
    }
    
    return NO;
}

BOOL ASFXLooksLikeStoreURLBagData(id data) {
    if ([data isKindOfClass:[NSDictionary class]]) {
        return ASFXDictionaryLooksLikeStoreBag((NSDictionary *)data);
    }

    if (![data isKindOfClass:[NSData class]]) {
        return NO;
    }

    NSData *bytes = (NSData *)data;
    if (!bytes.length) {
        return NO;
    }

    NSString *error = nil;
    id propertyList = [NSPropertyListSerialization propertyListFromData:bytes
                                                         mutabilityOption:NSPropertyListImmutable
                                                                   format:NULL
                                                         errorDescription:&error];
    if ([propertyList isKindOfClass:[NSDictionary class]] && ASFXDictionaryLooksLikeStoreBag(propertyList)) {
        return YES;
    }
    

    NSString *text = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
    BOOL hasAppleURL = [text rangeOfString:@"itunes.apple.com"
                                   options:NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasBagField = [text rangeOfString:@"storefront"
                                   options:NSCaseInsensitiveSearch].location != NSNotFound ||
                       [text rangeOfString:@"certs"
                                   options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (hasAppleURL && hasBagField) {
        return YES;
    }

    return NO;
}
