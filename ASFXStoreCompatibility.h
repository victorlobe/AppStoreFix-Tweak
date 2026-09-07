#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSURL *ASFXStoreURLForRequest(NSURL *url);
FOUNDATION_EXPORT NSMutableURLRequest *ASFXPrepareLoginRequest(NSMutableURLRequest *request);
FOUNDATION_EXPORT NSMutableURLRequest *ASFXPrepareStoreRequest(NSMutableURLRequest *request);
FOUNDATION_EXPORT BOOL ASFXLooksLikeStoreURLBagData(id data);
FOUNDATION_EXPORT NSDictionary *ASFXPrepareStoreURLBag(NSDictionary *bag);
