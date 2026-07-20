#include "ConfirmationWidget.h"

#include "LocalAuthentication/LocalAuthentication.h"

#include <QLabel>
#include <QVBoxLayout>
#include <QWindow>
#include <cstddef>

#include "quickunlock/QuickUnlockInterface.h"

ConfirmationWidget::ConfirmationWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    id<ASCredentialRequest> credentialRequest, NSView *laView,
    LAContext *laContext, QWidget *parent)
    : QWidget(parent), m_extensionContext(extensionContext),
      m_credentialRequest(credentialRequest), m_laView(laView),
      m_laContext(laContext) {

  m_db = QSharedPointer<Database>::create("/Users/seb/Developer/Adgangskoder.kdbx"); // TODO: Make dynamic

  QString error;  
  m_db->open(nullptr, &error);

  // Overall layout
  auto *mainLayout = new QVBoxLayout(this);
  mainLayout->setAlignment(Qt::AlignCenter);
  mainLayout->setContentsMargins(40, 40, 40, 40);
  mainLayout->setSpacing(20);

  // Title
  auto quickUnlock = getQuickUnlock();
  const auto dbUuid = m_db->publicUuid();

  QByteArray keyData;
  if (!quickUnlock->hasKey(dbUuid)) {
    QLabel *titleLabel = new QLabel(tr("fedt2"), this);
    QFont titleFont = titleLabel->font();
    titleFont.setPointSize(16);
    titleFont.setBold(true);
    titleLabel->setFont(titleFont);
    titleLabel->setAlignment(Qt::AlignCenter);

    mainLayout->addWidget(titleLabel);

  } else {
    QLabel *titleLabel = new QLabel(tr("hej2"), this);
    QFont titleFont = titleLabel->font();
    titleFont.setPointSize(16);
    titleFont.setBold(true);
    titleLabel->setFont(titleFont);
    titleLabel->setAlignment(Qt::AlignCenter);

    mainLayout->addWidget(titleLabel);
  }

  // Password input
  m_passwordInput = new QLineEdit(this);
  m_passwordInput->setEchoMode(QLineEdit::Password);
  m_passwordInput->setPlaceholderText(tr("Enter your master password"));
  m_passwordInput->setMinimumHeight(30);
  m_passwordInput->setStyleSheet("padding: 6px; font-size: 14px;");

  mainLayout->addWidget(m_passwordInput);

  // Button row
  auto *buttonLayout = new QHBoxLayout();
  buttonLayout->setSpacing(15);
  m_submitButton = new QPushButton(tr("Unlock"), this);
  m_cancel = new QPushButton(tr("Cancel"), this);

  buttonLayout->addStretch();
  buttonLayout->addWidget(m_cancel);
  buttonLayout->addWidget(m_submitButton);
  buttonLayout->addStretch();

  mainLayout->addLayout(buttonLayout);

  // Connect signals
  connect(m_cancel, &QPushButton::clicked, this,
          &ConfirmationWidget::exitCancelRequest);
  connect(m_submitButton, &QPushButton::clicked, this,
          &ConfirmationWidget::authenticateWithKey);

  // Initialize unlock logic
  QTimer::singleShot(0, this, &ConfirmationWidget::setupQuickUnlock);

  setLayout(mainLayout);
  resize(450, 220);
  setWindowTitle(tr("Confirm Access"));
  show();
}

void ConfirmationWidget::setupQuickUnlock() {
  [m_laContext
       evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
      localizedReason:@"låse din database op"
                reply:^(BOOL success, NSError *_Nullable error) {
                  if (!success || error) {
                    return;
                  }

                  auto quickUnlock = getQuickUnlock();
                  const auto dbUuid = m_db->publicUuid();

                  QByteArray keyData;
                  if (!quickUnlock->hasKey(dbUuid) ||
                      !quickUnlock->getKey(dbUuid, keyData, m_laContext)) {
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
  if (password.isEmpty())
    return;

  auto compositeKey = QSharedPointer<CompositeKey>::create();
  compositeKey->addKey(QSharedPointer<PasswordKey>::create(password));

  if (!unlockDatabase(compositeKey)) {
    exitCancelRequest();
    return;
  }

  completeRequest();
}

bool ConfirmationWidget::unlockDatabase(
    QSharedPointer<CompositeKey> compositeKey) {
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
    m_credentialRequest = nullptr;
  }
}
