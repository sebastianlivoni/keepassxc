#include "ConfirmationWidget.h"

#include "AutoFillService.h"
#include "DatabaseUnlockWidget.h"

#include <QFile>
#include <QVBoxLayout>
#include <os/log.h>

#include "core/Config.h"
#include "core/Tools.h"

ConfirmationWidget::ConfirmationWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    id<ASCredentialRequest> credentialRequest, QWidget *parent)
    : QWidget(parent), m_extensionContext(extensionContext),
      m_credentialRequest(credentialRequest), m_unlockWidget(nullptr) {

  NSString *recordIdentifier =
      m_credentialRequest.credentialIdentity.recordIdentifier;

  if (!recordIdentifier || recordIdentifier.length == 0) {
    NSLog(@"[AutoFill] Record identifier is nil or empty!");
    return;
  }

  QUuid dbUuid;
  QUuid entryUuid;
  autoFillService()->parseRecordIdentifier(recordIdentifier, dbUuid,
                                           entryUuid);

  QString dbPath = config()->getDatabaseFilePath(Tools::uuidToHex(dbUuid));
  os_log(OS_LOG_DEFAULT, "Path: %{public}@", dbPath.toNSString());

  if (dbPath.isEmpty() || !QFile::exists(dbPath)) {
    os_log(OS_LOG_DEFAULT,
           "Database path is invalid or file does not exist: %{public}s",
           [dbPath.toNSString() UTF8String]);
    return;
  }

  auto *mainLayout = new QVBoxLayout(this);
  mainLayout->setContentsMargins(0, 0, 0, 0);

  m_unlockWidget = new DatabaseUnlockWidget(dbPath, this);
  m_unlockWidget->onUnlocked = [this](QSharedPointer<Database> db) {
    m_db = db;
    completeRequest();
  };
  m_unlockWidget->onCancelled = [this]() { exitCancelRequest(); };
  mainLayout->addWidget(m_unlockWidget);

  setLayout(mainLayout);
  resize(450, 400);
  setWindowTitle(tr("Confirm Access"));
  show();
}

void ConfirmationWidget::exitCancelRequest() {
  NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                       code:ASExtensionErrorCodeFailed
                                   userInfo:nil];
  [m_extensionContext cancelRequestWithError:error];
}

ConfirmationWidget::~ConfirmationWidget() {
  if (m_credentialRequest) {
    m_credentialRequest = nullptr;
  }
}
