#include "ConfirmationWidget.h"

#include "quickunlock/TouchID.h"

#include <QVBoxLayout>
#include <QWindow>

ConfirmationWidget::ConfirmationWidget(ASCredentialProviderExtensionContext* extensionContext,
    ASPasskeyCredentialRequest* credentialRequest,
    NSView* laView,
    LAContext* laContext,
    QWidget *parent) : QWidget(parent),
      m_extensionContext(extensionContext),
      m_credentialRequest((ASPasskeyCredentialRequest *)CFBridgingRetain(credentialRequest)),
      m_laView(laView),
      m_laContext(laContext) {
  m_db = QSharedPointer<Database>::create();
  const QString dbPath = "/Users/seb/Downloads/Adgangskoder.kdbx"; // TODO: Get the dbpath somehow
  m_db->setFilePath(dbPath);

  // UI
  auto *layout = new QVBoxLayout(this);
  setLayout(layout);

  m_passwordInput = new QLineEdit(this);
  m_passwordInput->setEchoMode(QLineEdit::Password);
  m_passwordInput->setPlaceholderText(tr("Enter KeePassXC password"));

  m_submitButton = new QPushButton(tr("Submit"), this);
  m_cancel = new QPushButton(tr("Cancel"), this);

  QWindow *nativeWindow = QWindow::fromWinId(reinterpret_cast<WId>(m_laView));
  QWidget *m_nativeWidget = QWidget::createWindowContainer(nativeWindow, this);

  m_nativeWidget->setFixedSize(50, 50);

  layout->addWidget(m_nativeWidget);
  layout->addWidget(m_passwordInput);
  layout->addWidget(m_cancel);
  layout->addWidget(m_submitButton);

  connect(m_cancel, &QPushButton::clicked, this, &ConfirmationWidget::exitCancelRequest);
  connect(m_submitButton, &QPushButton::clicked, this, &ConfirmationWidget::authenticateWithKey);

  QTimer::singleShot(0, this, &ConfirmationWidget::setupQuickUnlock);

  show();
}

void ConfirmationWidget::setupQuickUnlock() {
  [m_laContext evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
        localizedReason:@"Authenticate to unlock keychain item"
                  reply:^(BOOL success, NSError * _Nullable error) {
      if (!success) {
        return;
      }

      auto quickUnlock = new TouchID();
      const auto dbUuid = m_db->publicUuid();

      QByteArray keyData;
      if (!quickUnlock->hasKey(dbUuid) || !quickUnlock->getKey(dbUuid, keyData, m_laContext)) {
        exitCancelRequest();
        return;
      }

      auto compositeKey = QSharedPointer<CompositeKey>::create();
      compositeKey->setRawKey(keyData);

      if (!unlockDatabase(compositeKey)) {
        exitCancelRequest();
        return;
      }

      completeRequest();
  }];
}

void ConfirmationWidget::authenticateWithKey() {
  QString password = m_passwordInput->text();
  if (password.isEmpty()) return;

  auto compositeKey = QSharedPointer<CompositeKey>::create();
  compositeKey->addKey(QSharedPointer<PasswordKey>::create(password));

  if (!unlockDatabase(compositeKey)) {
    exitCancelRequest();
    return;
  }

  completeRequest();
}

bool ConfirmationWidget::unlockDatabase(QSharedPointer<CompositeKey> compositeKey) {
  QString error;
  bool result = m_db->open(compositeKey, &error);

  if (!result) {
    NSLog(@"Failed to open database: %@", error.toNSString());
  }
  
  return result;
}

void ConfirmationWidget::exitCancelRequest() {
  NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                       code:ASExtensionErrorCodeFailed
                                   userInfo:nil];
  [m_extensionContext cancelRequestWithError:error];
}

ConfirmationWidget::~ConfirmationWidget() {
    if (m_credentialRequest) {
        CFRelease(m_credentialRequest);
        m_credentialRequest = nullptr;
    }
}