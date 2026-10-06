#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSURL *ASFXStoreURLForRequest(NSURL *url);
FOUNDATION_EXPORT NSMutableURLRequest *ASFXPrepareLoginRequest(NSMutableURLRequest *request);
FOUNDATION_EXPORT BOOL ASFXIsLoginURL(NSURL *url);
FOUNDATION_EXPORT NSString *ASFXRepairStoreFront(NSString *storeFront);
FOUNDATION_EXPORT NSURLResponse *ASFXPrepareLoginResponse(NSURLResponse *response);
FOUNDATION_EXPORT NSMutableURLRequest *ASFXPrepareStoreRequest(NSMutableURLRequest *request);
FOUNDATION_EXPORT NSDictionary *ASFXPrepareStoreSectionsDictionary(NSDictionary *dictionary);
FOUNDATION_EXPORT BOOL ASFXLooksLikeStoreURLBagData(id data);
FOUNDATION_EXPORT NSDictionary *ASFXPrepareStoreURLBag(NSDictionary *bag);
