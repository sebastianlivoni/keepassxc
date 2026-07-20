/*
 *  Copyright (C) 2024 KeePassXC Team <team@keepassxc.org>
 *  Copyright (C) 2018 Sami Vänttinen <sami.vanttinen@protonmail.com>
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

#include "DatabaseSettingsWidgetAutoFill.h"
#include "ui_DatabaseSettingsWidgetAutoFill.h"

#include <QProgressDialog>

#include "browser/BrowserService.h"
#include "browser/BrowserSettings.h"
#include "core/Group.h"
#include "core/Metadata.h"
#include "gui/MessageBox.h"

DatabaseSettingsWidgetAutoFill::DatabaseSettingsWidgetAutoFill(QWidget* parent)
    : DatabaseSettingsWidget(parent)
    , m_ui(new Ui::DatabaseSettingsWidgetAutoFill())
    , m_customData(new CustomData(this))
    , m_customDataModel(new QStandardItemModel(this))
{
    m_ui->setupUi(this);
    
}

DatabaseSettingsWidgetAutoFill::~DatabaseSettingsWidgetAutoFill()
{
}

CustomData* DatabaseSettingsWidgetAutoFill::customData() const
{
    // Returns the current database customData from metadata. Otherwise return an empty customData member.
    if (m_db) {
        return m_db->metadata()->customData();
    }
    return m_customData;
}

void DatabaseSettingsWidgetAutoFill::initialize()
{
    updateModel();
    settingsWarning();
}

void DatabaseSettingsWidgetAutoFill::uninitialize()
{
}

void DatabaseSettingsWidgetAutoFill::showEvent(QShowEvent* event)
{
    QWidget::showEvent(event);
}

bool DatabaseSettingsWidgetAutoFill::saveSettings()
{
    return true;
}

void DatabaseSettingsWidgetAutoFill::removeSelectedKey()
{
    if (MessageBox::Yes
        != MessageBox::question(this,
                                tr("Delete the selected key?"),
                                tr("Do you really want to delete the selected key?\n"
                                   "This may prevent connection to the browser plugin."),
                                MessageBox::Yes | MessageBox::Cancel,
                                MessageBox::Cancel)) {
        return;
    }


}

void DatabaseSettingsWidgetAutoFill::toggleRemoveButton(const QItemSelection& selected)
{
}

void DatabaseSettingsWidgetAutoFill::updateModel()
{
    m_customDataModel->clear();
    m_customDataModel->setHorizontalHeaderLabels({tr("Key"), tr("Value"), tr("Created")});

    for (const QString& key : customData()->keys()) {
        if (key.startsWith(CustomData::BrowserKeyPrefix)) {
            QString strippedKey = key;
            strippedKey.remove(CustomData::BrowserKeyPrefix);
            auto created = customData()->value(CustomData::getKeyWithPrefix(CustomData::Created, strippedKey));
            auto createdItem = new QStandardItem(created);
            createdItem->setEditable(false);
            m_customDataModel->appendRow(QList<QStandardItem*>()
                                         << new QStandardItem(strippedKey)
                                         << new QStandardItem(customData()->value(key)) << createdItem);
        }
    }

}

void DatabaseSettingsWidgetAutoFill::settingsWarning()
{
    
}

void DatabaseSettingsWidgetAutoFill::removeSharedEncryptionKeys()
{
    if (MessageBox::Yes
        != MessageBox::question(this,
                                tr("Disconnect all browsers"),
                                tr("Do you really want to disconnect all browsers?\n"
                                   "This may prevent connection to the browser plugin."),
                                MessageBox::Yes | MessageBox::Cancel,
                                MessageBox::Cancel)) {
        return;
    }

    QStringList keysToRemove;
    for (const QString& key : m_db->metadata()->customData()->keys()) {
        if (key.startsWith(CustomData::BrowserKeyPrefix)) {
            keysToRemove << key;
        }
    }

    if (keysToRemove.isEmpty()) {
        MessageBox::information(
            this, tr("No keys found"), tr("No shared encryption keys found in KeePassXC settings."), MessageBox::Ok);
        return;
    }

    for (const QString& key : keysToRemove) {
        m_db->metadata()->customData()->remove(key);
    }

    const int count = keysToRemove.count();
    MessageBox::information(this,
                            tr("Removed keys from database"),
                            tr("Successfully removed %n encryption key(s) from KeePassXC settings.", "", count),
                            MessageBox::Ok);
}

void DatabaseSettingsWidgetAutoFill::removeStoredPermissions()
{
    if (MessageBox::Yes
        != MessageBox::question(this,
                                tr("Forget all site-specific settings on entries"),
                                tr("Do you really want forget all site-specific settings on every entry?\n"
                                   "Permissions to access entries will be revoked."),
                                MessageBox::Yes | MessageBox::Cancel,
                                MessageBox::Cancel)) {
        return;
    }

    QList<Entry*> entries = m_db->rootGroup()->entriesRecursive();

    QProgressDialog progress(tr("Removing stored permissions…"), tr("Abort"), 0, entries.count());
    progress.setWindowModality(Qt::WindowModal);

    uint counter = 0;
    for (Entry* entry : entries) {
        if (progress.wasCanceled()) {
            return;
        }

        if (entry->customData()->contains(BrowserService::KEEPASSXCBROWSER_NAME)) {
            browserService()->removePluginData(entry);
            ++counter;
        }
        progress.setValue(progress.value() + 1);
    }
    progress.reset();

    if (counter > 0) {
        MessageBox::information(this,
                                tr("Removed permissions"),
                                tr("Successfully removed permissions from %n entry(s).", "", counter),
                                MessageBox::Ok);
    } else {
        MessageBox::information(this,
                                tr("No entry with permissions found!"),
                                tr("The active database does not contain an entry with permissions."),
                                MessageBox::Ok);
    }
}

void DatabaseSettingsWidgetAutoFill::refreshDatabaseID()
{
    if (MessageBox::Yes
        != MessageBox::question(this,
                                tr("Refresh database ID"),
                                tr("Do you really want refresh the database ID?\n"
                                   "This is only necessary if your database is a copy of another and the "
                                   "browser extension cannot connect."),
                                MessageBox::Yes | MessageBox::Cancel,
                                MessageBox::Cancel)) {
        return;
    }

    m_db->rootGroup()->setUuid(QUuid::createUuid());
}

void DatabaseSettingsWidgetAutoFill::editIndex(const QModelIndex& index)
{
    Q_ASSERT(index.isValid());
    if (!index.isValid()) {
        return;
    }

    m_valueInEdit = index.data().toString();
}

void DatabaseSettingsWidgetAutoFill::editFinished(QStandardItem* item)
{

}

// Updates the shared key list after the list is cleared
void DatabaseSettingsWidgetAutoFill::updateSharedKeyList()
{
    updateModel();
}

// Replaces a key and the created timestamp for it
void DatabaseSettingsWidgetAutoFill::replaceKey(const QString& prefix,
                                               const QString& oldName,
                                               const QString& newName) const
{
    const auto oldKey = CustomData::getKeyWithPrefix(prefix, oldName);
    const auto newKey = CustomData::getKeyWithPrefix(prefix, newName);
    const auto tempValue = customData()->value(oldKey);
    m_db->metadata()->customData()->remove(oldKey);
    m_db->metadata()->customData()->set(newKey, tempValue);
}
