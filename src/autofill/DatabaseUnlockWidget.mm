#include "DatabaseUnlockWidget.h"

#include <QLabel>
#include <QPushButton>
#include <QStackedWidget>
#include <QTimer>
#include <QVBoxLayout>
#include <os/log.h>

#include "gui/DatabaseOpenWidget.h"
#include "keys/CompositeKey.h"
#include "quickunlock/QuickUnlockInterface.h"

#include <LocalAuthentication/LocalAuthentication.h>
#include <LocalAuthenticationEmbeddedUI/LAAuthenticationView.h>

DatabaseUnlockWidget::DatabaseUnlockWidget(const QString& dbPath, QWidget* parent)
    : QWidget(parent)
    , m_dbPath(dbPath)
    , m_laContext(nil)
    , m_stack(nullptr)
    , m_quickUnlockPage(nullptr)
    , m_openWidget(nullptr)
{
    m_db = QSharedPointer<Database>::create(dbPath);
    QString error;
    m_db->open(nullptr, &error);

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);

    m_stack = new QStackedWidget(this);
    layout->addWidget(m_stack);

    m_openWidget = new DatabaseOpenWidget(m_stack);
    m_openWidget->load(m_dbPath);
    connect(m_openWidget, &DatabaseOpenWidget::dialogFinished, this, &DatabaseUnlockWidget::openWidgetFinished);
    m_stack->addWidget(m_openWidget);

    auto quickUnlock = getQuickUnlock();
    const auto dbUuid = m_db->publicUuid();

    if (quickUnlock->hasKey(dbUuid)) {
        m_quickUnlockPage = new QWidget(m_stack);
        auto* quickUnlockLayout = new QVBoxLayout(m_quickUnlockPage);
        quickUnlockLayout->setAlignment(Qt::AlignCenter);
        quickUnlockLayout->setContentsMargins(40, 40, 40, 40);
        quickUnlockLayout->setSpacing(20);

        auto* label = new QLabel(tr("Unlock KeePassXC database with Touch ID"), m_quickUnlockPage);
        label->setAlignment(Qt::AlignCenter);
        quickUnlockLayout->addWidget(label);

        auto* passwordInsteadButton = new QPushButton(tr("Use Password Instead"), m_quickUnlockPage);
        connect(passwordInsteadButton, &QPushButton::clicked, this, &DatabaseUnlockWidget::showPasswordEntry);
        quickUnlockLayout->addWidget(passwordInsteadButton);

        m_stack->insertWidget(0, m_quickUnlockPage);
        m_stack->setCurrentWidget(m_quickUnlockPage);

        QTimer::singleShot(0, this, &DatabaseUnlockWidget::setupQuickUnlock);
    } else {
        m_stack->setCurrentWidget(m_openWidget);
    }

    setLayout(layout);
    resize(450, 400);
}

DatabaseUnlockWidget::~DatabaseUnlockWidget() {}

void DatabaseUnlockWidget::showPasswordEntry()
{
    m_stack->setCurrentWidget(m_openWidget);
}

void DatabaseUnlockWidget::setupQuickUnlock()
{
    m_laContext = [[LAContext alloc] init];

    LAAuthenticationView* laView = [[LAAuthenticationView alloc] initWithContext:m_laContext];
    laView.translatesAutoresizingMaskIntoConstraints = NO;
    NSView* rootView = (__bridge NSView*)(void*)winId();
    [rootView addSubview:laView];

    [m_laContext evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                 localizedReason:@"unlock your KeePassXC database"
                           reply:^(BOOL success, NSError* _Nullable error) {
                             dispatch_async(dispatch_get_main_queue(), ^{
                               if (!success || error) {
                                 showPasswordEntry();
                                 return;
                               }

                               auto quickUnlock = getQuickUnlock();
                               const auto dbUuid = m_db->publicUuid();

                               QByteArray keyData;
                               if (!quickUnlock->hasKey(dbUuid) || !quickUnlock->getKey(dbUuid, keyData, m_laContext)) {
                                 showPasswordEntry();
                                 return;
                               }

                               auto compositeKey = QSharedPointer<CompositeKey>::create();
                               compositeKey->setRawKey(keyData);

                               QString openError;
                               if (!m_db->open(compositeKey, &openError)) {
                                 os_log_error(OS_LOG_DEFAULT, "[AutoFill] Quick unlock failed to open database: %{public}@",
                                              openError.toNSString());
                                 showPasswordEntry();
                                 return;
                               }

                               if (onUnlocked) {
                                 onUnlocked(m_db);
                               }
                             });
                           }];
}

void DatabaseUnlockWidget::openWidgetFinished(bool accepted)
{
    if (!accepted) {
        if (onCancelled) {
            onCancelled();
        }
        return;
    }

    if (onUnlocked) {
        onUnlocked(m_openWidget->database());
    }
}
