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

#include "DatabaseSettingsWidgetAutoFill.h"

#include "autofill/common/AutoFillDatabaseOptions.h"

#include <QCheckBox>
#include <QLabel>
#include <QVBoxLayout>

DatabaseSettingsWidgetAutoFill::DatabaseSettingsWidgetAutoFill(QWidget* parent)
    : DatabaseSettingsWidget(parent)
    , m_enabledCheckBox(new QCheckBox(tr("Use this database for AutoFill"), this))
{
    auto* description = new QLabel(tr("When disabled, logins, one-time codes, and passkeys from this database are not "
                                      "offered by AutoFill, and the database is not listed in the AutoFill window."),
                                   this);
    description->setWordWrap(true);
    description->setIndent(20);

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->addWidget(m_enabledCheckBox);
    layout->addWidget(description);
    layout->addStretch();
}

DatabaseSettingsWidgetAutoFill::~DatabaseSettingsWidgetAutoFill() = default;

void DatabaseSettingsWidgetAutoFill::initialize()
{
    m_enabledCheckBox->setChecked(AutoFillDatabaseOptions::isEnabled(m_db.data()));
}

void DatabaseSettingsWidgetAutoFill::uninitialize()
{
}

bool DatabaseSettingsWidgetAutoFill::saveSettings()
{
    if (m_enabledCheckBox->isChecked() != AutoFillDatabaseOptions::isEnabled(m_db.data())) {
        AutoFillDatabaseOptions::setEnabled(m_db.data(), m_enabledCheckBox->isChecked());
    }
    return true;
}
