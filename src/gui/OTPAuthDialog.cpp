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

#include "OTPAuthDialog.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QPointer>
#include <QPushButton>
#include <QUrl>
#include <QUrlQuery>
#include <QVBoxLayout>

#include "core/Config.h"
#include "core/Database.h"
#include "core/Entry.h"
#include "core/EntrySearcher.h"
#include "core/Group.h"
#include "gui/Icons.h"
#include "gui/MessageBox.h"
#include "gui/entry/EntryView.h"

QString OTPAuthDialog::parse(const QUrl& url, Request& request)
{
    if (!url.isValid() || url.scheme().compare("otpauth", Qt::CaseInsensitive) != 0) {
        return tr("The link is not a valid otpauth:// link.");
    }
    // HOTP counters can't be stored, so only time-based codes are accepted
    if (url.host().compare("totp", Qt::CaseInsensitive) != 0) {
        return tr("Only time-based verification codes (TOTP) are supported.");
    }

    // QUrl already lower cases the scheme and host Totp::parseSettings compares against
    auto totp = Totp::parseSettings(url.toString(QUrl::FullyEncoded));
    if (!totp || totp->key.isEmpty()) {
        return tr("The link does not contain a secret key.");
    }
    // Secrets are often shown in groups or lower case; base32 itself has neither
    totp->key = totp->key.remove(' ').remove('-').toUpper();
    const auto error = Totp::checkValidSettings(totp);
    if (!error.isEmpty()) {
        return error;
    }

    // The label is "Issuer:account" or just "account"; the issuer parameter wins
    auto label = url.path(QUrl::FullyDecoded);
    if (label.startsWith('/')) {
        label.remove(0, 1);
    }
    const auto separator = label.indexOf(':');
    request.account = (separator >= 0 ? label.mid(separator + 1) : label).trimmed();
    request.issuer = QUrlQuery(url).queryItemValue("issuer", QUrl::FullyDecoded).trimmed();
    if (request.issuer.isEmpty() && separator >= 0) {
        request.issuer = label.left(separator).trimmed();
    }
    request.totp = totp;
    return {};
}

OTPAuthDialog::OTPAuthDialog(const Request& request,
                             const QList<QSharedPointer<Database>>& databases,
                             QWidget* parent)
    : QDialog(parent)
    , m_request(request)
    , m_databases(databases)
{
    setWindowTitle(tr("Add Verification Code"));
    setAttribute(Qt::WA_DeleteOnClose);

    for (const auto& db : m_databases) {
        for (auto* entry : db->rootGroup()->entriesRecursive()) {
            if (!entry->isRecycled()) {
                m_entries.append(entry);
            }
        }
    }

    // Styled like the AutoFill extension's credential list
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(30, 30, 30, 30);
    layout->setSpacing(12);

    auto* iconLabel = new QLabel(this);
    iconLabel->setPixmap(icons()->applicationIcon().pixmap(64));
    iconLabel->setAlignment(Qt::AlignCenter);
    layout->addWidget(iconLabel);

    QString subject = m_request.issuer;
    if (!m_request.account.isEmpty()) {
        subject = subject.isEmpty() ? m_request.account : tr("%1 (%2)").arg(subject, m_request.account);
    }
    auto* title = new QLabel(subject.isEmpty() ? tr("Add a verification code")
                                               : tr("Add the verification code for %1").arg(subject),
                             this);
    QFont titleFont = title->font();
    titleFont.setBold(true);
    titleFont.setPointSize(titleFont.pointSize() + 4);
    title->setFont(titleFont);
    title->setAlignment(Qt::AlignCenter);
    title->setWordWrap(true);
    layout->addWidget(title);

    auto* hint = new QLabel(tr("Choose the entry to add it to."), this);
    hint->setAlignment(Qt::AlignCenter);
    layout->addWidget(hint);
    layout->addSpacing(8);

    m_searchEdit = new QLineEdit(this);
    m_searchEdit->setPlaceholderText(tr("Search…"));
    m_searchEdit->setClearButtonEnabled(true);
    m_searchEdit->setAccessibleName(tr("Search entries"));
    connect(m_searchEdit, &QLineEdit::textChanged, this, &OTPAuthDialog::search);
    layout->addWidget(m_searchEdit);

    // The main window's entry table, with its column layout for search results if saved
    m_entryView = new EntryView(this);
    m_entryView->setAccessibleName(tr("Entries"));
    m_entryView->setDragEnabled(false);
    connect(m_entryView, &EntryView::entryActivated, this, [this](Entry* entry, EntryModel::ModelColumn) {
        choose(entry);
    });
    layout->addWidget(m_entryView);

    m_emptyLabel = new QLabel(tr("No matching entries found."), this);
    m_emptyLabel->setAlignment(Qt::AlignCenter);
    layout->addWidget(m_emptyLabel);

    auto* buttonLayout = new QHBoxLayout();
    auto* cancelButton = new QPushButton(tr("Cancel"), this);
    m_addButton = new QPushButton(tr("Add Code"), this);
    for (auto* button : {cancelButton, m_addButton}) {
        button->setStyleSheet("text-align:center;");
    }
    // Default buttons are green in the KeePassXC styles
    m_addButton->setDefault(true);
    connect(cancelButton, &QPushButton::clicked, this, &QDialog::reject);
    connect(m_addButton, &QPushButton::clicked, this, &OTPAuthDialog::chooseCurrentEntry);
    buttonLayout->addStretch();
    buttonLayout->addWidget(cancelButton);
    buttonLayout->addWidget(m_addButton);
    layout->addLayout(buttonLayout);

    resize(640, 520);

    // Start with the entries for the issuer when there are any
    if (!m_request.issuer.isEmpty()
        && !EntrySearcher(false).searchEntries(m_request.issuer, m_entries).isEmpty()) {
        m_searchEdit->setText(m_request.issuer);
    } else {
        search({});
    }
    m_searchEdit->setFocus();
}

void OTPAuthDialog::search(const QString& text)
{
    const auto entries = text.trimmed().isEmpty() ? m_entries : EntrySearcher(false).searchEntries(text, m_entries);

    m_entryView->displaySearch(entries);
    const auto viewState = config()->get(Config::GUI_SearchViewState).toByteArray();
    if (!viewState.isEmpty()) {
        m_entryView->setViewState(viewState);
    }
    // Saved widths fit the main window, not this dialog; queued so the view has its size
    QMetaObject::invokeMethod(m_entryView, "fitColumnsToWindow", Qt::QueuedConnection);
    m_entryView->setFirstEntryActive();

    m_entryView->setVisible(!entries.isEmpty());
    m_emptyLabel->setVisible(entries.isEmpty());
    m_addButton->setEnabled(!entries.isEmpty());
}

void OTPAuthDialog::chooseCurrentEntry()
{
    if (m_entryView->isVisible()) {
        choose(m_entryView->currentEntry());
    }
}

void OTPAuthDialog::choose(Entry* entry)
{
    if (!entry) {
        return;
    }

    // The entry could be deleted while the confirmation is open
    QPointer<Entry> guardedEntry(entry);
    if (entry->hasTotp()) {
        auto answer = MessageBox::question(
            this,
            tr("Replace Verification Code?"),
            tr("The entry \"%1\" already has a verification code. Do you want to replace it?")
                .arg(entry->title().toHtmlEscaped()),
            MessageBox::Overwrite | MessageBox::Cancel,
            MessageBox::Cancel);
        if (answer != MessageBox::Overwrite || !guardedEntry) {
            return;
        }
    }

    emit entryChosen(entry, m_request.totp);
    accept();
}
