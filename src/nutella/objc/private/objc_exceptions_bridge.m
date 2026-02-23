#include <stdbool.h>
#include <objc/objc.h>
#include <objc/objc-exception.h>
#include <objc/message.h>
#include <objc/runtime.h>

typedef void (*nutella_objc_try_body_t)(void *ctx);

static id nutella_retain(id obj) {
  if (obj == nil) {
    return nil;
  }
  return ((id (*)(id, SEL))objc_msgSend)(obj, sel_registerName("retain"));
}

bool nutella_objc_try_catch(
    nutella_objc_try_body_t body, void *ctx, id *caughtException) {
  if (caughtException != NULL) {
    *caughtException = nil;
  }

  @try {
    if (body != NULL) {
      body(ctx);
    }
    return false;
  } @catch (id exceptionObject) {
    if (caughtException != NULL) {
      *caughtException = nutella_retain(exceptionObject);
    }
    return true;
  }
}

void nutella_objc_throw(id exceptionObject) {
  objc_exception_throw(exceptionObject);
}

id nutella_objc_build_exception(
    const char *name, const char *reason, const char *fallbackPayload) {
  if (name == NULL) {
    name = "NimException";
  }
  if (reason == NULL) {
    reason = "";
  }
  if (fallbackPayload == NULL) {
    fallbackPayload = reason;
  }

  Class nsExceptionClass = objc_getClass("NSException");
  SEL exceptionCtorSel = sel_registerName("exceptionWithName:reason:userInfo:");
  Class stringClass = objc_getClass("NSString");
  SEL utf8CtorSel = sel_registerName("stringWithUTF8String:");
  if (nsExceptionClass != Nil && stringClass != Nil &&
      class_respondsToSelector(object_getClass(nsExceptionClass), exceptionCtorSel) &&
      class_respondsToSelector(object_getClass(stringClass), utf8CtorSel)) {
    id nameString = ((id (*)(id, SEL, const char *))objc_msgSend)(
        stringClass, utf8CtorSel, name);
    id reasonString = ((id (*)(id, SEL, const char *))objc_msgSend)(
        stringClass, utf8CtorSel, reason);
    if (nameString != nil && reasonString != nil) {
      id nsException = ((id (*)(id, SEL, id, id, id))objc_msgSend)(
          nsExceptionClass, exceptionCtorSel, nameString, reasonString, nil);
      if (nsException != nil) {
        return nutella_retain(nsException);
      }
    }
  }

  Class nxStringClass = objc_getClass("NXString");
  if (nxStringClass != Nil) {
    id payload = ((id (*)(id, SEL))objc_msgSend)(nxStringClass, sel_registerName("alloc"));
    if (payload != nil) {
      payload = ((id (*)(id, SEL))objc_msgSend)(payload, sel_registerName("init"));
      if (payload != nil &&
          ((bool (*)(id, SEL, SEL))objc_msgSend)(
              payload, sel_registerName("respondsToSelector:"),
              sel_registerName("setStringValue:"))) {
        ((void (*)(id, SEL, const char *))objc_msgSend)(
            payload, sel_registerName("setStringValue:"), fallbackPayload);
      }
      return payload;
    }
  }

  Class nsObjectClass = objc_getClass("NSObject");
  if (nsObjectClass != Nil) {
    id fallbackObject =
        ((id (*)(id, SEL))objc_msgSend)(nsObjectClass, sel_registerName("new"));
    if (fallbackObject != nil) {
      return fallbackObject;
    }
  }

  return nil;
}
