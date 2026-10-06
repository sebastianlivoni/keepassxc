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

#ifndef CXF_READER_H
#define CXF_READER_H

#include <QSharedPointer>

class Database;

/*!
 * Imports credentials in the FIDO Credential Exchange Format (CXF) 1.0 JSON:
 * https://fidoalliance.org/specs/cx/cxf-v1.0-ps-20250814.html
 */
class CxfReader
{
public:
    explicit CxfReader() = default;
    ~CxfReader() = default;

    QSharedPointer<Database> convert(const QByteArray& json);

    bool hasError();
    QString errorString();
    // Name of the app the credentials came from, if the export named it
    QString exporterName() const;

private:
    QString m_error;
    QString m_exporterName;
};

#endif // CXF_READER_H
