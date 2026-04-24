/*
 *  Copyright (C) 2024 KeePassXC Team <team@keepassxc.org>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "BrowserPasskeysConfirmationDialogV2.h"
#include "AutoFillServiceV2.h"
#include "ui_BrowserPasskeysConfirmationDialogV2.h"

#include "core/Entry.h"
#include <QCloseEvent>
#include <QUrl>
#include <QWidget>

#define STEP 1000

BrowserPasskeysConfirmationDialogV2::BrowserPasskeysConfirmationDialogV2(
    ASCredentialProviderExtensionContext *extensionContext,
    ASPasskeyCredentialRequest *credentialRequest,
    AutoFillXPCServiceClient *xpcService, QWidget *parent)
    : QWidget(parent), m_extensionContext(extensionContext),
      m_credentialRequest(static_cast<ASPasskeyCredentialRequest *>(credentialRequest)),
      m_xpcService(xpcService),
      m_ui(new Ui::BrowserPasskeysConfirmationDialogV2()),
      m_passkeyUpdated(false) {
  m_xpcService = xpcService;

  setWindowFlags(windowFlags() | Qt::WindowStaysOnTopHint);

  m_ui->setupUi(this);
  m_ui->verticalLayout->setAlignment(Qt::AlignTop);

  connect(m_ui->confirmButton, &QPushButton::clicked, this,
          [this]() { accept(); });

  connect(m_ui->cancelButton, &QPushButton::clicked, this,
          [this]() { reject(); });

  connect(&m_timer, SIGNAL(timeout()), this, SLOT(updateProgressBar()));
  connect(&m_timer, SIGNAL(timeout()), this, SLOT(updateSeconds()));
}

BrowserPasskeysConfirmationDialogV2::~BrowserPasskeysConfirmationDialogV2() {}

void BrowserPasskeysConfirmationDialogV2::registerCredential(
    const QString &username, const QString &relyingParty,
    const QList<Entry *> &existingEntries, int timeout) {
  m_ui->firstLabel->setText(tr("Do you want to register a passkey for:"));
  m_ui->relyingPartyLabel->setText(tr("Relying Party: %1").arg(relyingParty));
  m_ui->usernameLabel->setText(tr("Username: %1").arg(username));
  m_ui->updateButton->setVisible(true);
  m_ui->secondLabel->setText("");

  if (!existingEntries.isEmpty()) {
    m_ui->firstLabel->setText(tr(
        "Existing passkey found.\nDo you want to register a new passkey for:"));
    m_ui->secondLabel->setText(
        tr("Select the existing passkey and press Update to replace it."));
    m_ui->updateButton->setText(tr("Update"));
    m_ui->confirmButton->setText(tr("Register new"));
    updateEntriesToTable(existingEntries);
  } else {
    m_ui->verticalLayout->setSizeConstraint(QLayout::SetFixedSize);
    m_ui->confirmButton->setText(tr("Register"));
    m_ui->updateButton->setText(tr("Add to existing entry"));
    m_ui->credentialsTable->setVisible(false);
  }

  startCounter(timeout);
}

void BrowserPasskeysConfirmationDialogV2::authenticateCredential(
    const QList<Entry *> &entries, const QString &relyingParty, int timeout) {
  m_ui->firstLabel->setText(tr("Authenticate passkey credentials for:"));
  m_ui->relyingPartyLabel->setText(tr("Relying Party: %1").arg(relyingParty));
  m_ui->usernameLabel->setVisible(false);
  m_ui->updateButton->setVisible(false);
  m_ui->secondLabel->setText("");
  updateEntriesToTable(entries);
  startCounter(timeout);
}

Entry *BrowserPasskeysConfirmationDialogV2::getSelectedEntry() const {
  auto selectedItem = m_ui->credentialsTable->currentItem();
  return selectedItem ? m_entries[selectedItem->row()] : nullptr;
}

bool BrowserPasskeysConfirmationDialogV2::isPasskeyUpdated() const {
  return m_passkeyUpdated;
}

void BrowserPasskeysConfirmationDialogV2::updatePasskey() {
  m_passkeyUpdated = true;
  // emit accept();
}

void BrowserPasskeysConfirmationDialogV2::updateProgressBar() {
  if (m_counter < m_ui->progressBar->maximum()) {
    m_ui->progressBar->setValue(m_ui->progressBar->maximum() - m_counter);
    m_ui->progressBar->update();
  } else {
    // emit reject();
  }
}

void BrowserPasskeysConfirmationDialogV2::updateSeconds() {
  ++m_counter;
  updateTimeoutLabel();
}

void BrowserPasskeysConfirmationDialogV2::startCounter(int timeout) {
  m_counter = 0;
  m_ui->progressBar->setMaximum(timeout / STEP);
  updateProgressBar();
  updateTimeoutLabel();
  m_timer.start(STEP);
}

void BrowserPasskeysConfirmationDialogV2::updateTimeoutLabel() {
  m_ui->timeoutLabel->setText(tr("Timeout in <b>%n</b> seconds...", "",
                                 m_ui->progressBar->maximum() - m_counter));
}

void BrowserPasskeysConfirmationDialogV2::updateEntriesToTable(
    const QList<Entry *> &entries) {
  m_entries = entries;
  m_ui->credentialsTable->setRowCount(entries.count());
  m_ui->credentialsTable->setColumnCount(1);

  int row = 0;
  for (const auto &entry : entries) {
    auto item = new QTableWidgetItem();
    item->setText(entry->title() + " - " + entry->username());
    m_ui->credentialsTable->setItem(row, 0, item);

    if (row == 0) {
      item->setSelected(true);
    }

    ++row;
  }

  m_ui->credentialsTable->resizeColumnsToContents();
  m_ui->credentialsTable->horizontalHeader()->setStretchLastSection(true);
}

void BrowserPasskeysConfirmationDialogV2::accept() {
    NSLog(@"[accept] xpcService: %{public}@", m_xpcService);
        NSLog(@"[accept] connection: %{public}@", m_xpcService.connection);

  id proxy = [m_xpcService.connection remoteObjectProxyWithErrorHandler:^(
                                             NSError *_Nonnull error) {
                                             NSLog(@"XPC error: %@", error);
  }];

  [proxy createPasskeyRegistrationCredential:m_credentialRequest withReply:^(ASPasskeyRegistrationCredential *credential, NSError *error) {
      [m_extensionContext completeRegistrationRequestWithSelectedPasskeyCredential:credential completionHandler:nil];
  }];
}

void BrowserPasskeysConfirmationDialogV2::reject() {
  NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                       code:ASExtensionErrorCodeFailed
                                   userInfo:nil];
  [m_extensionContext cancelRequestWithError:error];
}
