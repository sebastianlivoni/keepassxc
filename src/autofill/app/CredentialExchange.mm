#include "app/CredentialExchange.h"

#include <AppKit/AppKit.h>
#include <QWidget>
#include <objc/runtime.h>
#include <os/log.h>

#ifdef WITH_XC_CREDENTIAL_EXCHANGE
// Implemented in CredentialExchangeBridge.swift
API_AVAILABLE(macos(26.0))
@interface KPXCCredentialExchangeBridge : NSObject
+ (BOOL)isCredentialExchangeActivity:(NSUserActivity *)activity;
+ (void)importCredentialsFromActivity:(NSUserActivity *)activity
                           completion:(void (^)(NSData *data, NSError *error))completion;
+ (void)exportCredentials:(NSData *)json
    extensionBundleIdentifier:(NSString *)extensionBundleIdentifier
                       window:(NSWindow *)window
               completion:(void (^)(NSError *error))completion;
@end
#endif

// Returns true if the activity was a credential import
static bool handleUserActivity(NSUserActivity *activity) {
#ifdef WITH_XC_CREDENTIAL_EXCHANGE
  if (@available(macOS 26.0, *)) {
    if (![KPXCCredentialExchangeBridge isCredentialExchangeActivity:activity]) {
      return false;
    }
    [KPXCCredentialExchangeBridge
        importCredentialsFromActivity:activity
                           completion:^(NSData *data, NSError *error) {
                             dispatch_async(dispatch_get_main_queue(), ^{
                               if (!data) {
                                 os_log_error(OS_LOG_DEFAULT, "[CredentialExchange] Import failed: %{public}@",
                                              error);
                                 return;
                               }
                               credentialExchange()->addImport(QByteArray::fromNSData(data));
                             });
                           }];
    return true;
  }
#else
  Q_UNUSED(activity);
#endif
  return false;
}

CredentialExchange *CredentialExchange::instance() {
  static CredentialExchange *s_instance = new CredentialExchange();
  return s_instance;
}

void CredentialExchange::start() {
  id delegate = NSApp.delegate;
  if (m_started || !delegate) {
    return;
  }
  m_started = true;

  // Qt owns the app delegate, so add (or wrap) its user activity handler
  Class delegateClass = object_getClass(delegate);
  SEL selector = @selector(application:continueUserActivity:restorationHandler:);
  Method existing = class_getInstanceMethod(delegateClass, selector);
  IMP original = existing ? method_getImplementation(existing) : nullptr;

  using Handler = BOOL (*)(id, SEL, NSApplication *, NSUserActivity *, id);
  IMP replacement = imp_implementationWithBlock(
      ^BOOL(id self, NSApplication *application, NSUserActivity *activity, id restorationHandler) {
        if (handleUserActivity(activity)) {
          return YES;
        }
        return original ? reinterpret_cast<Handler>(original)(self, selector, application, activity,
                                                              restorationHandler)
                        : NO;
      });

  const char *types =
      protocol_getMethodDescription(@protocol(NSApplicationDelegate), selector, NO, YES).types;
  if (!class_addMethod(delegateClass, selector, replacement, types)) {
    method_setImplementation(existing, replacement);
  }
}

QList<QByteArray> CredentialExchange::takePendingImports() {
  QList<QByteArray> imports;
  imports.swap(m_pendingImports);
  return imports;
}

void CredentialExchange::addImport(const QByteArray &cxfJson) {
  m_pendingImports.append(cxfJson);
  emit importReceived();
}

bool CredentialExchange::isExportSupported() const {
#ifdef WITH_XC_CREDENTIAL_EXCHANGE
  if (@available(macOS 26.0, *)) {
    return true;
  }
#endif
  return false;
}

void CredentialExchange::exportCredentials(const QByteArray &cxfJson, QWidget *window,
                                           const std::function<void(const QString &error)> &done) {
#ifdef WITH_XC_CREDENTIAL_EXCHANGE
  if (@available(macOS 26.0, *)) {
    NSView *view = (__bridge NSView *)reinterpret_cast<void *>(window->window()->winId());
    auto callback = done;
    [KPXCCredentialExchangeBridge exportCredentials:cxfJson.toNSData()
                          extensionBundleIdentifier:@AUTOFILL_EXTENSION_IDENTIFIER
                                             window:view.window
                                         completion:^(NSError *error) {
                                           dispatch_async(dispatch_get_main_queue(), ^{
                                             callback(error ? QString::fromNSString(error.localizedDescription)
                                                            : QString());
                                           });
                                         }];
    return;
  }
#else
  Q_UNUSED(cxfJson);
  Q_UNUSED(window);
#endif
  done(QObject::tr("Credential Exchange requires macOS 26 or later."));
}
