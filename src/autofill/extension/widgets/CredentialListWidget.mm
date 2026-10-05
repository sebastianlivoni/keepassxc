#include "extension/widgets/CredentialListWidget.h"

#include <QCheckBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QStackedWidget>
#include <QUrl>
#include <QVBoxLayout>

#include "common/AutoFillCredentials.h"
#include "core/Config.h"
#include "core/Entry.h"
#include "extension/widgets/DatabasePickerWidget.h"
#include "extension/widgets/DatabaseUnlockWidget.h"
#include "gui/Icons.h"
#include "gui/entry/EntryView.h"

CredentialListWidget::CredentialListWidget(ASCredentialProviderExtensionContext* extensionContext,
                                           NSArray<ASCredentialServiceIdentifier*>* serviceIdentifiers,
                                           Mode mode,
                                           QWidget* parent)
    : QWidget(parent)
    , m_extensionContext(extensionContext)
    , m_passkeyRequestParameters(nil)
    , m_mode(mode)
    , m_stack(nullptr)
    , m_entryPage(nullptr)
    , m_entryView(nullptr)
    , m_emptyLabel(nullptr)
{
    // Domain identifiers come without a scheme; URL matching needs one
    for (ASCredentialServiceIdentifier* serviceIdentifier in serviceIdentifiers) {
        QString url = QString::fromNSString(serviceIdentifier.identifier);
        if (!url.contains("://")) {
            url.prepend("https://");
        }
        m_siteUrls << url;
    }
    m_siteName = m_siteUrls.isEmpty() ? QString() : QUrl(m_siteUrls.first()).host();

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    m_stack = new QStackedWidget(this);
    layout->addWidget(m_stack);
    setLayout(layout);
    resize(640, 460);

    resolveDatabase();
}

CredentialListWidget::CredentialListWidget(ASCredentialProviderExtensionContext* extensionContext,
                                           ASPasskeyCredentialRequestParameters* passkeyRequestParameters,
                                           QWidget* parent)
    : QWidget(parent)
    , m_extensionContext(extensionContext)
    , m_passkeyRequestParameters(passkeyRequestParameters)
    , m_mode(Mode::PasskeyAssertion)
    , m_stack(nullptr)
    , m_entryPage(nullptr)
    , m_entryView(nullptr)
    , m_emptyLabel(nullptr)
{
    m_siteName = QString::fromNSString(passkeyRequestParameters.relyingPartyIdentifier);
    m_siteUrls << m_siteName;

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    m_stack = new QStackedWidget(this);
    layout->addWidget(m_stack);
    setLayout(layout);
    resize(640, 460);

    resolveDatabase();
}

void CredentialListWidget::resolveDatabase()
{
    const auto databasePaths = config()->getAllDatabaseFilePaths();

    if (databasePaths.isEmpty()) {
        auto* page = new QWidget(m_stack);
        auto* pageLayout = new QVBoxLayout(page);
        pageLayout->setAlignment(Qt::AlignCenter);
        pageLayout->setContentsMargins(40, 40, 40, 40);
        pageLayout->setSpacing(20);

        auto* label = new QLabel(tr("No KeePassXC database is registered for AutoFill."), page);
        label->setWordWrap(true);
        label->setAlignment(Qt::AlignCenter);
        pageLayout->addWidget(label);

        auto* cancelButton = new QPushButton(tr("Cancel"), page);
        connect(cancelButton, &QPushButton::clicked, this, &CredentialListWidget::exitCancelRequest);
        pageLayout->addWidget(cancelButton);

        m_stack->addWidget(page);
        m_stack->setCurrentWidget(page);
        return;
    }

    if (databasePaths.size() == 1) {
        useDatabasePath(databasePaths.constBegin().value());
        return;
    }

    auto* picker = new DatabasePickerWidget(m_stack);
    picker->onDatabaseChosen = [this](QString dbPath) { useDatabasePath(dbPath); };
    picker->onCancelled = [this]() { exitCancelRequest(); };
    m_stack->addWidget(picker);
    m_stack->setCurrentWidget(picker);
}

void CredentialListWidget::useDatabasePath(const QString& dbPath)
{
    auto* unlockWidget = new DatabaseUnlockWidget(m_extensionContext, dbPath, m_stack);
    unlockWidget->onUnlocked = [this](QSharedPointer<Database> db) {
        m_db = db;
        showEntryList();
    };
    m_stack->addWidget(unlockWidget);
    m_stack->setCurrentWidget(unlockWidget);

    const QSize unlockSize = size().expandedTo(unlockWidget->size());
    if (onResizeRequested) {
        onResizeRequested(unlockSize);
    } else {
        // Not embedded yet; the extension view picks up this size when embedded
        resize(unlockSize);
    }
}

void CredentialListWidget::showEntryList()
{
    // Styled like the main app's WelcomeWidget and the database picker
    m_entryPage = new QWidget(m_stack);
    auto* pageLayout = new QVBoxLayout(m_entryPage);
    pageLayout->setContentsMargins(30, 30, 30, 30);
    pageLayout->setSpacing(12);

    auto* iconLabel = new QLabel(m_entryPage);
    iconLabel->setPixmap(icons()->applicationIcon().pixmap(64));
    iconLabel->setAlignment(Qt::AlignCenter);
    pageLayout->addWidget(iconLabel);

    auto* title =
        new QLabel(m_siteName.isEmpty() ? tr("Choose a credential") : tr("Choose a credential for %1").arg(m_siteName),
                   m_entryPage);
    QFont titleFont = title->font();
    titleFont.setBold(true);
    titleFont.setPointSize(titleFont.pointSize() + 4);
    title->setFont(titleFont);
    title->setAlignment(Qt::AlignCenter);
    title->setWordWrap(true);
    pageLayout->addWidget(title);
    pageLayout->addSpacing(8);

    // The main app's entry view, with its column layout for search results if saved
    m_entryView = new EntryView(m_entryPage);
    m_entryView->setAccessibleName(tr("Choose a credential"));
    m_entryView->setDragEnabled(false);
    connect(m_entryView, &EntryView::entryActivated, this, [this](Entry* entry, EntryModel::ModelColumn) {
        completeWithEntry(entry);
    });
    pageLayout->addWidget(m_entryView);

    m_emptyLabel = new QLabel(tr("No matching credentials found."), m_entryPage);
    m_emptyLabel->setAlignment(Qt::AlignCenter);
    pageLayout->addWidget(m_emptyLabel);

    auto* buttonLayout = new QHBoxLayout();
    // Switches between the matching and all entries
    auto* showAllCheckBox = new QCheckBox(tr("Show All Entries"), m_entryPage);
    connect(showAllCheckBox, &QCheckBox::toggled, this, &CredentialListWidget::showEntries);
    auto* cancelButton = new QPushButton(tr("Cancel"), m_entryPage);
    auto* confirmButton = new QPushButton(tr("Use"), m_entryPage);
    for (auto* button : {cancelButton, confirmButton}) {
        button->setStyleSheet("text-align:center;");
    }
    // Default buttons are green in the KeePassXC styles
    confirmButton->setDefault(true);
    connect(cancelButton, &QPushButton::clicked, this, &CredentialListWidget::exitCancelRequest);
    connect(confirmButton, &QPushButton::clicked, this, &CredentialListWidget::confirmSelection);
    buttonLayout->addWidget(showAllCheckBox);
    buttonLayout->addStretch();
    buttonLayout->addWidget(cancelButton);
    buttonLayout->addWidget(confirmButton);
    pageLayout->addLayout(buttonLayout);

    m_stack->addWidget(m_entryPage);
    m_stack->setCurrentWidget(m_entryPage);

    showEntries(false);
}

void CredentialListWidget::populateEntries(const QList<Entry*>& entries)
{
    m_entryView->displaySearch(entries);
    const auto viewState = config()->get(Config::GUI_SearchViewState).toByteArray();
    if (!viewState.isEmpty()) {
        m_entryView->setViewState(viewState);
    }
    // Keep the best-match order instead of displaySearch's sort by group
    m_entryView->sortByColumn(-1, Qt::AscendingOrder);
    // Saved widths fit the main window, not this sheet; queued so the view has its size
    QMetaObject::invokeMethod(m_entryView, "fitColumnsToWindow", Qt::QueuedConnection);
    m_entryView->setFirstEntryActive();

    m_entryView->setVisible(!entries.isEmpty());
    m_emptyLabel->setVisible(entries.isEmpty());
}

void CredentialListWidget::showEntries(bool all)
{
    const bool passkeyOnly = (m_mode == Mode::PasskeyAssertion);
    const bool totpOnly = (m_mode == Mode::TOTP);
    populateEntries(all ? AutoFillCredentials::allEntries(m_db, passkeyOnly, totpOnly)
                        : AutoFillCredentials::searchEntries(m_db, m_siteUrls, passkeyOnly, totpOnly));
}

void CredentialListWidget::confirmSelection()
{
    if (auto* entry = m_entryView->currentEntry()) {
        completeWithEntry(entry);
    }
}

void CredentialListWidget::completeWithEntry(Entry* entry)
{
    switch (m_mode) {
    case Mode::Password: {
        ASPasswordCredential* credential = AutoFillCredentials::getPasswordCredentialFromEntry(entry);
        if (!credential) {
            exitCancelRequest();
            return;
        }
        [m_extensionContext completeRequestWithSelectedCredential:credential completionHandler:nil];
        break;
    }
    case Mode::TOTP: {
        ASOneTimeCodeCredential* credential = AutoFillCredentials::getOneTimeCodeCredentialFromEntry(entry);
        if (!credential) {
            exitCancelRequest();
            return;
        }
        [m_extensionContext completeOneTimeCodeRequestWithSelectedCredential:credential completionHandler:nil];
        break;
    }
    case Mode::PasskeyAssertion: {
        ASPasskeyAssertionCredential* credential = AutoFillCredentials::getPasskeyCredentialFromEntry(
            entry, m_passkeyRequestParameters.clientDataHash, m_passkeyRequestParameters);
        if (!credential) {
            exitCancelRequest();
            return;
        }
        [m_extensionContext completeAssertionRequestWithSelectedPasskeyCredential:credential completionHandler:nil];
        break;
    }
    }
}

void CredentialListWidget::exitCancelRequest()
{
    NSError* error = [NSError errorWithDomain:ASExtensionErrorDomain
                                         code:ASExtensionErrorCodeUserCanceled
                                     userInfo:nil];
    [m_extensionContext cancelRequestWithError:error];
}
