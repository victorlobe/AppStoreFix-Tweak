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

static NSString *ASFXXMLString(NSString *value) {
    return [[[[[value stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
        stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"]
        stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"]
        stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"]
        stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
}

static NSString *ASFXDecodedQueryValue(NSString *value) {
    NSString *decoded = [value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return decoded ?: value;
}

static NSString *ASFXLoginPropertyList(NSString *query) {
    NSMutableString *plist = [NSMutableString stringWithString:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n<dict>\n"];

    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSRange separator = [pair rangeOfString:@"="];
        if (separator.location == NSNotFound) {
            continue;
        }

        NSString *key = ASFXDecodedQueryValue([pair substringToIndex:separator.location]);
        NSString *value = ASFXDecodedQueryValue([pair substringFromIndex:separator.location + 1]);
        if ([key length] == 0) {
            continue;
        }

        [plist appendFormat:@"<key>%@</key>\n<string>%@</string>\n",
            ASFXXMLString(key), ASFXXMLString(value)];
    }

    [plist appendString:@"</dict>\n</plist>"];
    return plist;
}

NSMutableURLRequest *ASFXPrepareLoginRequest(NSMutableURLRequest *request) {
    if (![request isKindOfClass:[NSMutableURLRequest class]]) {
        return request;
    }

    NSURL *loginURL = [NSURL URLWithString:@"https://auth.itunes.apple.com/auth/v1/native/fast"];
    NSString *query = [[request URL] query];
    if (loginURL == nil || [query length] == 0) {
        return request;
    }

    [request setURL:loginURL];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[ASFXLoginPropertyList(query) dataUsingEncoding:NSUTF8StringEncoding]];

    NSLog(@"[AppStoreFix] login endpoint rewritten to %@", loginURL);
    return request;
}

NSMutableURLRequest *ASFXPrepareStoreRequest(NSMutableURLRequest *request) {
    if (![request isKindOfClass:[NSMutableURLRequest class]]) {
        return request;
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

NSDictionary *ASFXPrepareStoreURLBag(NSDictionary *bag) {
    if (![bag isKindOfClass:[NSDictionary class]]) {
        return bag;
    }

    id certs = [bag objectForKey:@"certs"];
    if ([certs isKindOfClass:[NSArray class]]) {
        NSLog(@"[AppStoreFix] URL bag accepted with %lu server certificates",
              (unsigned long)[certs count]);
    } else if (certs == nil) {
        NSLog(@"[AppStoreFix] URL bag has no certificate list.... using system trust");
    } else {
        NSLog(@"[AppStoreFix] URL bag certificate field has unexpected type: %@",
              [certs class]);
    }

    return [NSDictionary dictionaryWithDictionary:bag];
}
