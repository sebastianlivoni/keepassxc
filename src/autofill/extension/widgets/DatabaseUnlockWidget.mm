#include "extension/widgets/DatabaseUnlockWidget.h"

#include <QDialogButtonBox>
#include <QFileInfo>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>

#include "core/Config.h"
#include "gui/DatabaseOpenWidget.h"
#include "common/AutoFillBookmarks.h"

DatabaseUnlockWidget::DatabaseUnlockWidget(ASCredentialProviderExtensionContext* extensionContext,
                                           const QString& dbPath,
                                           QWidget* parent)
    : QWidget(parent)
    , m_extensionContext(extensionContext)
    , m_openWidget(nullptr)
{
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);

    // The sandbox only lets us open files KeePassXC shared a bookmark for
    const QString dbUuidHex = config()->getAllDatabaseFilePaths().key(dbPath);
    const QString accessiblePath = AutoFillBookmarks::startAccess(dbUuidHex);
    if (accessiblePath.isEmpty()) {
        showNotSharedYet(dbPath);
        return;
    }

    m_openWidget = new DatabaseOpenWidget(this);
    m_openWidget->load(accessiblePath);
    // Keys saved here would outlive this request; only keep them if the user chose to remember them
    m_openWidget->setQuickUnlockSaveAllowed(config()->get(Config::Security_QuickUnlockRemember).toBool());
    connect(m_openWidget, &DatabaseOpenWidget::dialogFinished, this, &DatabaseUnlockWidget::openWidgetFinished);
    layout->addWidget(m_openWidget);

    // The Quick Unlock "Cancel" button resets the stored key in the main app;
    // in the extension it should cancel the AutoFill request instead
    if (auto* resetButton = m_openWidget->findChild<QPushButton*>("resetQuickUnlockButton")) {
        disconnect(resetButton, nullptr, m_openWidget, nullptr);
        connect(resetButton, &QPushButton::clicked, this, &DatabaseUnlockWidget::cancelRequest);
    }

    // Close on the password form; also reaches us via dialogFinished(false)
    if (auto* buttonBox = m_openWidget->findChild<QDialogButtonBox*>("buttonBox")) {
        connect(buttonBox, &QDialogButtonBox::rejected, this, &DatabaseUnlockWidget::cancelRequest);
    }

    setLayout(layout);
    // DatabaseOpenWidget's designed size (from its .ui)
    resize(m_openWidget->size());
}

DatabaseUnlockWidget::~DatabaseUnlockWidget() {}

// KeePassXC hasn't shared access to this database file with AutoFill yet
void DatabaseUnlockWidget::showNotSharedYet(const QString& dbPath)
{
    auto* message = new QLabel(tr("To use \"%1\" with AutoFill, open and unlock it in KeePassXC once. "
                                  "This allows AutoFill to open the database file.")
                                   .arg(QFileInfo(dbPath).fileName()),
                               this);
    message->setWordWrap(true);
    message->setAlignment(Qt::AlignCenter);

    auto* cancelButton = new QPushButton(tr("Cancel"), this);
    cancelButton->setDefault(true);
    connect(cancelButton, &QPushButton::clicked, this, &DatabaseUnlockWidget::cancelRequest);

    auto* layout = qobject_cast<QVBoxLayout*>(this->layout());
    layout->setContentsMargins(40, 40, 40, 40);
    layout->setSpacing(20);
    layout->addStretch();
    layout->addWidget(message);
    layout->addWidget(cancelButton, 0, Qt::AlignCenter);
    layout->addStretch();
    resize(450, 250);
}

void DatabaseUnlockWidget::openWidgetFinished(bool accepted)
{
    if (!accepted) {
        cancelRequest();
        return;
    }

    m_unlocked = true;
    if (onUnlocked && m_openWidget) {
        onUnlocked(m_openWidget->database());
    }
}

bool DatabaseUnlockWidget::tryQuickUnlock()
{
    if (!m_openWidget || !m_openWidget->canPerformQuickUnlock()) {
        return false;
    }
    // Synchronous: returns once Touch ID succeeded, failed or was cancelled
    m_openWidget->toggleQuickUnlockScreen();
    m_openWidget->triggerQuickUnlock();
    return m_unlocked;
}

void DatabaseUnlockWidget::cancelRequest()
{
    if (!m_extensionContext) {
        return;
    }

    NSError* error = [NSError errorWithDomain:ASExtensionErrorDomain
                                         code:ASExtensionErrorCodeUserCanceled
                                     userInfo:nil];
    [m_extensionContext cancelRequestWithError:error];
    m_extensionContext = nil;
}
