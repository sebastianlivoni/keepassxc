/*
 *  Copyright (C) 2023 KeePassXC Team <team@keepassxc.org>
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

#ifndef KEEPASSXC_BROWSERPASSKEYSCONFIRMATIONDIALOGV2_H
#define KEEPASSXC_BROWSERPASSKEYSCONFIRMATIONDIALOGV2_H

#include <QDialog>
#include <QTableWidget>
#include <QTimer>

#include "AutoFillXPCServiceClient.h"
#include <AuthenticationServices/AuthenticationServices.h>

class Entry;

namespace Ui
{
    class BrowserPasskeysConfirmationDialogV2;
}

class BrowserPasskeysConfirmationDialogV2 : public QWidget
{

public:
    explicit BrowserPasskeysConfirmationDialogV2(ASCredentialProviderExtensionContext* extensionContext,
                                                 ASPasskeyCredentialRequest* credentialRequest,
                                                 AutoFillXPCServiceClient* xpcService,
                                                 QWidget* parent = nullptr);
    ~BrowserPasskeysConfirmationDialogV2() override;

    void registerCredential(const QString& username,
                            const QString& relyingParty,
                            const QList<Entry*>& existingEntries);
    void authenticateCredential(const QList<Entry*>& entries, const QString& relyingParty);
    Entry* getSelectedEntry() const;
    bool isPasskeyUpdated() const;

private:
    void updateEntriesToTable(const QList<Entry*>& entries);
    void accept();
    void reject();

    ASCredentialProviderExtensionContext* m_extensionContext;
    ASPasskeyCredentialRequest* m_credentialRequest;
    AutoFillXPCServiceClient* m_xpcService;

private:
    QScopedPointer<Ui::BrowserPasskeysConfirmationDialogV2> m_ui;
    QList<Entry*> m_entries;
    QTimer m_timer;
    int m_counter;
    bool m_passkeyUpdated;
};

#endif // KEEPASSXC_BROWSERPASSKEYSCONFIRMATIONDIALOG_H
