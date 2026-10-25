#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <Security/SecureTransport.h>
#import <substrate.h>
#import "ASFXBootstrapBridge.h"
#import "ASFXStoreCompatibility.h"


static OSStatus (*ASFXOriginalSSLHandshake)(SSLContextRef context);

static OSStatus ASFXSSLHandshake(SSLContextRef context) {
    OSStatus minStatus = SSLSetProtocolVersionMin(context, kTLSProtocol1);
    OSStatus maxStatus = SSLSetProtocolVersionMax(context, kTLSProtocol12);
    OSStatus handshakeStatus = ASFXOriginalSSLHandshake(context);
	
	
    if (handshakeStatus == noErr ||
        handshakeStatus == errSSLWouldBlock ||
        handshakeStatus == errSSLServerAuthCompleted) {
        return handshakeStatus;
    }

    SSLProtocol negotiatedProtocol = kSSLProtocolUnknown;
    OSStatus negotiatedStatus =
        SSLGetNegotiatedProtocolVersion(context, &negotiatedProtocol);

    char peer[256] = {0};
    size_t peerLength = sizeof(peer) - 1;
    if (SSLGetPeerDomainName(context, peer, &peerLength) != noErr) {
        peerLength = 0;
    }
    peer[peerLength] = '\0';

    NSLog(@"[AppStoreFix] SecureTransport failed host=%s min=%d max=%d handshake=%d negotiated=%d read=%d",
          peer,
          (int)minStatus,
          (int)maxStatus,
          (int)handshakeStatus,
          (int)negotiatedProtocol,
          (int)negotiatedStatus);

    return handshakeStatus;
}

%ctor {
    [ASFXBootstrapBridge install];
    MSHookFunction((void *)SSLHandshake,
                   (void *)ASFXSSLHandshake,
                   (void **)&ASFXOriginalSSLHandshake);
    NSLog(@"[AppStoreFix] Store compatibility loaded");
}

%hook ISURLOperation

- (id)newRequestWithURL:(NSURL *)url {
    NSURL *rewritten = ASFXStoreURLForRequest(url);
    return %orig(rewritten);
}

- (BOOL)_runRequestWithURL:(NSURL *)url {
    NSURL *rewritten = ASFXStoreURLForRequest(url);
    return %orig(rewritten);
}

- (BOOL)_isTrustExtendedValidation:(SecTrustRef)trust {
    if (!trust) {
        return NO;
    }

    SecTrustResultType result = kSecTrustResultInvalid;
    OSStatus status = SecTrustEvaluate(trust, &result);
    BOOL accepted = NO;
    if (status == errSecSuccess) {
        accepted = result == kSecTrustResultProceed || result == kSecTrustResultUnspecified;
    }
    if (!accepted) {
        NSLog(@"[AppStoreFix] trust evaluation rejected status=%d result=%d", (int)status, (int)result);
    }
    return accepted;
}

%end

%hook ISStoreURLOperation

- (id)newRequestWithURL:(NSURL *)url {
    return ASFXPrepareStoreRequest(%orig(url));
}

%end

%hook ISCertificate

- (BOOL)checkData:(id)data againstSignature:(id)signature {
    if (ASFXLooksLikeStoreURLBagData(data)) {
        NSLog(@"[AppStoreFix] accepted Store URL bag signature");
        return YES;
    }

    return %orig;
}

%end

// Bag patch for the login URL taken from Pod's NewerStoreLoginFix. Thank you Pod
// https://github.com/Epixx512/NewerStoreLoginFix
%hook ISURLBag

- (id)valueForKey:(NSString *)key {
    id value = %orig;
    return ASFXPrepareStoreURLBagValue(key, value);
}

- (NSURL *)urlForKey:(NSString *)key {
    NSURL *url = %orig;
    return ASFXPrepareStoreURLBagValue(key, url);
}

%end

%hook SUSectionsResponse

- (id)_newSectionsFromDictionary:(NSDictionary *)dictionary {
    return %orig(ASFXPrepareStoreSectionsDictionary(dictionary));
}

%end

%hook SSAccount

- (NSString *)storeFrontIdentifier {
    NSString *storeFront = %orig;
    return ASFXRepairStoreFront(storeFront);
}

- (void)setStoreFrontIdentifier:(NSString *)storeFront {
    %orig(ASFXRepairStoreFront(storeFront));
}

%end

%hook SSDevice

- (NSString *)storeFrontIdentifier {
    NSString *storeFront = %orig;
    return ASFXRepairStoreFront(storeFront);
}

%end

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if ([field caseInsensitiveCompare:@"X-Apple-Store-Front"] == NSOrderedSame) {
        value = ASFXRepairStoreFront(value);
    }
    %orig(value, field);
}

- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if ([field caseInsensitiveCompare:@"X-Apple-Store-Front"] == NSOrderedSame) {
        value = ASFXRepairStoreFront(value);
    }
    %orig(value, field);
}

%end
