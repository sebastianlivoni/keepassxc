/*
 *  Copyright (C) 2026 KeePassXC Team <team@keepassxc.org>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 2 or (at your option)
 *  version 3 of the License.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef KEEPASSXC_OTPAUTHDIALOG_H
#define KEEPASSXC_OTPAUTHDIALOG_H

#include <QDialog>
#include <QList>
#include <QSharedPointer>

#include "core/Totp.h"

class Database;
class Entry;
class EntryView;
class QLabel;
class QLineEdit;
class QPushButton;

// Picks the entry an otpauth:// link (e.g. from a QR code scanner) adds its verification code to
class OTPAuthDialog : public QDialog
{
    Q_OBJECT

public:
    struct Request
    {
        QSharedPointer<Totp::Settings> totp;
        QString issuer;
        QString account;
    };

    // Returns an error message if KeePassXC can't use the link
    static QString parse(const QUrl& url, Request& request);

    explicit OTPAuthDialog(const Request& request,
                           const QList<QSharedPointer<Database>>& databases,
                           QWidget* parent = nullptr);

signals:
    void entryChosen(Entry* entry, QSharedPointer<Totp::Settings> totp);

private:
    void search(const QString& text);
    void chooseCurrentEntry();
    void choose(Entry* entry);

    Request m_request;
    // Keeps the databases alive while their entries are listed
    QList<QSharedPointer<Database>> m_databases;
    QList<Entry*> m_entries;

    QLineEdit* m_searchEdit;
    EntryView* m_entryView;
    QLabel* m_emptyLabel;
    QPushButton* m_addButton;
};

#endif // KEEPASSXC_OTPAUTHDIALOG_H
