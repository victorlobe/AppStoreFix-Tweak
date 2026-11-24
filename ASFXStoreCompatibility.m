#import "ASFXStoreCompatibility.h"

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
        return url;
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

// no storefront when signed out results in empty pages, so just use the one from the bag
static NSString *ASFXBagStoreFrontID;

void ASFXRememberBagStoreFront(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        value = [value stringValue];
    }
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
        return;
    }

    @synchronized([NSString class]) {
        if ([value isEqualToString:ASFXBagStoreFrontID]) {
            return;
        }
        ASFXBagStoreFrontID = [value copy];
    }
    NSLog(@"[AppStoreFix] default storefront from URL bag: %@", value);
}

NSString *ASFXDefaultStoreFront(void) {
    NSString *storeFrontID;
    @synchronized([NSString class]) {
        storeFrontID = ASFXBagStoreFrontID;
    }
    return storeFrontID ? [storeFrontID stringByAppendingString:ASFXNativeStoreFrontPlatform()] : nil;
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

    // 6.1+ adds the signature later, so only rewrite the old (6.0 and older) requests here
    NSString *contentType = [request valueForHTTPHeaderField:@"Content-Type"];
    if ([[request HTTPMethod] isEqualToString:@"GET"] || [contentType hasPrefix:@"multipart/form-data"]) {
        return ASFXRewriteAuthenticateRequest(request);
    }
    return request;
}

static NSString *ASFXFormDecode(NSString *str) {
    str = [str stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    NSString *decoded = [str stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return decoded ?: str;
}

static NSData *ASFXPlistDataFromQuery(NSString *query) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        if ([pair length] == 0) continue;
        NSRange eq = [pair rangeOfString:@"="];
        NSString *k = (eq.location == NSNotFound) ? pair : [pair substringToIndex:eq.location];
        NSString *v = (eq.location == NSNotFound) ? @"" : [pair substringFromIndex:NSMaxRange(eq)];
        k = ASFXFormDecode(k);
        v = ASFXFormDecode(v);
        if ([k length] != 0) [dict setObject:v forKey:k];
    }
    NSString *error = nil;
    return [NSPropertyListSerialization dataFromPropertyList:dict format:NSPropertyListXMLFormat_v1_0 errorDescription:&error];
}


static NSData *ASFXPlistDataFromMultipart(NSData *body, NSString *contentType) {
    NSRange boundaryRange = [contentType rangeOfString:@"boundary="];
    if (boundaryRange.location == NSNotFound) {
        return nil;
    }

    NSString *boundary = [contentType substringFromIndex:NSMaxRange(boundaryRange)];
    boundary = [boundary stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\" "]];
    NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    if ([boundary length] == 0 || text == nil) {
        return nil;
    }

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSString *separator = [@"--" stringByAppendingString:boundary];
    for (NSString *part in [text componentsSeparatedByString:separator]) {
        NSRange headerEnd = [part rangeOfString:@"\r\n\r\n"];
        NSRange nameStart = [part rangeOfString:@"name=\""];
        if (headerEnd.location == NSNotFound || nameStart.location == NSNotFound || nameStart.location > headerEnd.location) {
            continue;
        }

        NSUInteger start = NSMaxRange(nameStart);
        NSRange nameEnd = [part rangeOfString:@"\"" options:0 range:NSMakeRange(start, headerEnd.location - start)];
        if (nameEnd.location == NSNotFound) {
            continue;
        }

        NSString *name = [part substringWithRange:NSMakeRange(start, nameEnd.location - start)];
        NSString *value = [part substringFromIndex:NSMaxRange(headerEnd)];
        if ([value hasSuffix:@"\r\n"]) {
            value = [value substringToIndex:[value length] - 2];
        }
        if ([name length] != 0) {
            [dict setObject:value forKey:name];
        }
    }
    if ([dict count] == 0) {
        return nil;
    }

    NSString *error = nil;
    return [NSPropertyListSerialization dataFromPropertyList:dict format:NSPropertyListXMLFormat_v1_0 errorDescription:&error];
}

NSMutableURLRequest *ASFXRewriteAuthenticateRequest(NSMutableURLRequest *request) {
    if (![request isKindOfClass:[NSMutableURLRequest class]]) return request;
    NSURL *url = [request URL];
    if ([[url path] rangeOfString:@"/WebObjects/MZFinance.woa/wa/authenticate"].location == NSNotFound) return request;
    if ([request valueForHTTPHeaderField:@"X-Apple-ActionSignature"] != nil) return request;
    NSString *method = [request HTTPMethod];
    NSString *query = [url query];
    NSString *contentType = [request valueForHTTPHeaderField:@"Content-Type"];
    [request setURL:[NSURL URLWithString:@"https://auth.itunes.apple.com/auth/v1/native/fast"]];
    if ([method isEqualToString:@"GET"]) {
        [request setHTTPMethod:@"POST"];
        [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        [request setHTTPBody:ASFXPlistDataFromQuery(query)];
    } else if ([contentType hasPrefix:@"multipart/form-data"]) {
        NSData *plist = ASFXPlistDataFromMultipart([request HTTPBody], contentType);
        if (plist != nil) {
            [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
            [request setHTTPBody:plist];
        }
    }
    NSLog(@"[AppStoreFix] authenticate rewritten to %@ (method=%@ bodyLen=%lu)", [request URL], [request HTTPMethod], (unsigned long)[[request HTTPBody] length]);
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
