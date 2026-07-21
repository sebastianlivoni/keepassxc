#include "CredentialListWidget.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QStackedWidget>
#include <QVBoxLayout>

#include "AutoFillService.h"
#include "DatabasePickerWidget.h"
#include "DatabaseUnlockWidget.h"
#include "core/Config.h"
#include "core/Entry.h"

CredentialListWidget::CredentialListWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    NSArray<ASCredentialServiceIdentifier *> *serviceIdentifiers, Mode mode,
    QWidget *parent)
    : QWidget(parent), m_extensionContext(extensionContext),
      m_passkeyRequestParameters(nil), m_mode(mode), m_stack(nullptr),
      m_entryPage(nullptr), m_entryListView(nullptr) {
  ASCredentialServiceIdentifier *first = serviceIdentifiers.firstObject;
  m_siteUrl = first ? QString::fromNSString(first.identifier) : QString();

  auto *layout = new QVBoxLayout(this);
  layout->setContentsMargins(0, 0, 0, 0);
  m_stack = new QStackedWidget(this);
  layout->addWidget(m_stack);
  setLayout(layout);
  resize(480, 420);

  resolveDatabase();
}

CredentialListWidget::CredentialListWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    NSArray<ASCredentialServiceIdentifier *> *serviceIdentifiers,
    ASPasskeyCredentialRequestParameters *passkeyRequestParameters,
    QWidget *parent)
    : QWidget(parent), m_extensionContext(extensionContext),
      m_passkeyRequestParameters(passkeyRequestParameters),
      m_mode(Mode::PasskeyAssertion), m_stack(nullptr), m_entryPage(nullptr),
      m_entryListView(nullptr) {
  m_siteUrl =
      QString::fromNSString(passkeyRequestParameters.relyingPartyIdentifier);

  auto *layout = new QVBoxLayout(this);
  layout->setContentsMargins(0, 0, 0, 0);
  m_stack = new QStackedWidget(this);
  layout->addWidget(m_stack);
  setLayout(layout);
  resize(480, 420);

  resolveDatabase();
}

void CredentialListWidget::resolveDatabase() {
  const auto databasePaths = config()->getAllDatabaseFilePaths();

  if (databasePaths.isEmpty()) {
    auto *page = new QWidget(m_stack);
    auto *pageLayout = new QVBoxLayout(page);
    pageLayout->setAlignment(Qt::AlignCenter);
    pageLayout->setContentsMargins(40, 40, 40, 40);
    pageLayout->setSpacing(20);

    auto *label = new QLabel(
        tr("No KeePassXC database is registered for AutoFill."), page);
    label->setWordWrap(true);
    label->setAlignment(Qt::AlignCenter);
    pageLayout->addWidget(label);

    auto *cancelButton = new QPushButton(tr("Cancel"), page);
    connect(cancelButton, &QPushButton::clicked, this,
            &CredentialListWidget::exitCancelRequest);
    pageLayout->addWidget(cancelButton);

    m_stack->addWidget(page);
    m_stack->setCurrentWidget(page);
    return;
  }

  if (databasePaths.size() == 1) {
    useDatabasePath(databasePaths.constBegin().value());
    return;
  }

  auto *picker = new DatabasePickerWidget(m_stack);
  picker->onDatabaseChosen = [this](QString dbPath) {
    useDatabasePath(dbPath);
  };
  picker->onCancelled = [this]() { exitCancelRequest(); };
  m_stack->addWidget(picker);
  m_stack->setCurrentWidget(picker);
}

void CredentialListWidget::useDatabasePath(const QString &dbPath) {
  auto *unlockWidget = new DatabaseUnlockWidget(dbPath, m_stack);
  unlockWidget->onUnlocked = [this](QSharedPointer<Database> db) {
    m_db = db;
    showEntryList();
  };
  unlockWidget->onCancelled = [this]() { exitCancelRequest(); };
  m_stack->addWidget(unlockWidget);
  m_stack->setCurrentWidget(unlockWidget);
}

void CredentialListWidget::showEntryList() {
  m_entryPage = new QWidget(m_stack);
  auto *pageLayout = new QVBoxLayout(m_entryPage);
  pageLayout->setContentsMargins(30, 30, 30, 30);
  pageLayout->setSpacing(15);

  auto *title =
      new QLabel(tr("Choose a credential for %1").arg(m_siteUrl), m_entryPage);
  QFont titleFont = title->font();
  titleFont.setPointSize(14);
  titleFont.setBold(true);
  title->setFont(titleFont);
  title->setWordWrap(true);
  pageLayout->addWidget(title);

  m_entryListView = new QListWidget(m_entryPage);
  connect(m_entryListView, &QListWidget::itemDoubleClicked, this,
          &CredentialListWidget::confirmSelection);
  pageLayout->addWidget(m_entryListView);

  auto *showAllButton = new QPushButton(tr("Show All Entries"), m_entryPage);
  connect(showAllButton, &QPushButton::clicked, this,
          &CredentialListWidget::showAllEntries);
  pageLayout->addWidget(showAllButton);

  auto *buttonLayout = new QHBoxLayout();
  buttonLayout->setSpacing(15);
  auto *cancelButton = new QPushButton(tr("Cancel"), m_entryPage);
  auto *confirmButton = new QPushButton(tr("Use"), m_entryPage);
  connect(cancelButton, &QPushButton::clicked, this,
          &CredentialListWidget::exitCancelRequest);
  connect(confirmButton, &QPushButton::clicked, this,
          &CredentialListWidget::confirmSelection);
  buttonLayout->addStretch();
  buttonLayout->addWidget(cancelButton);
  buttonLayout->addWidget(confirmButton);
  pageLayout->addLayout(buttonLayout);

  m_stack->addWidget(m_entryPage);
  m_stack->setCurrentWidget(m_entryPage);

  bool passkeyOnly = (m_mode == Mode::PasskeyAssertion);
  bool totpOnly = (m_mode == Mode::TOTP);
  populateEntries(
      autoFillService()->searchEntries(m_db, m_siteUrl, passkeyOnly, totpOnly));
}

void CredentialListWidget::populateEntries(const QList<Entry *> &entries) {
  m_entries = entries;
  m_entryListView->clear();

  if (entries.isEmpty()) {
    auto *item =
        new QListWidgetItem(tr("No matching credentials found."));
    item->setFlags(item->flags() & ~Qt::ItemIsSelectable);
    m_entryListView->addItem(item);
    return;
  }

  for (auto *entry : entries) {
    new QListWidgetItem(entry->title() + " - " + entry->username(),
                        m_entryListView);
  }
  m_entryListView->setCurrentRow(0);
}

void CredentialListWidget::showAllEntries() {
  bool passkeyOnly = (m_mode == Mode::PasskeyAssertion);
  bool totpOnly = (m_mode == Mode::TOTP);
  populateEntries(autoFillService()->allEntries(m_db, passkeyOnly, totpOnly));
}

void CredentialListWidget::confirmSelection() {
  int row = m_entryListView->currentRow();
  if (row < 0 || row >= m_entries.size()) {
    return;
  }

  completeWithEntry(m_entries[row]);
}

void CredentialListWidget::completeWithEntry(Entry *entry) {
  switch (m_mode) {
  case Mode::Password: {
    ASPasswordCredential *credential =
        autoFillService()->getPasswordCredentialFromEntry(entry);
    if (!credential) {
      exitCancelRequest();
      return;
    }
    [m_extensionContext completeRequestWithSelectedCredential:credential
                                            completionHandler:nil];
    break;
  }
  case Mode::TOTP: {
    ASOneTimeCodeCredential *credential =
        autoFillService()->getOneTimeCodeCredentialFromEntry(entry);
    if (!credential) {
      exitCancelRequest();
      return;
    }
    [m_extensionContext
        completeOneTimeCodeRequestWithSelectedCredential:credential
                                       completionHandler:nil];
    break;
  }
  case Mode::PasskeyAssertion: {
    ASPasskeyAssertionCredential *credential =
        autoFillService()->getPasskeyCredentialFromEntry(
            entry, m_passkeyRequestParameters.clientDataHash,
            m_passkeyRequestParameters);
    if (!credential) {
      exitCancelRequest();
      return;
    }
    [m_extensionContext
        completeAssertionRequestWithSelectedPasskeyCredential:credential
                                            completionHandler:nil];
    break;
  }
  }
}

void CredentialListWidget::exitCancelRequest() {
  NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                       code:ASExtensionErrorCodeUserCanceled
                                   userInfo:nil];
  [m_extensionContext cancelRequestWithError:error];
}
