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

#include "CxfReader.h"

#include "core/Database.h"
#include "core/Entry.h"
#include "core/Group.h"
#include "core/Totp.h"

#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QScopedPointer>

namespace
{
    // EditableField objects carry their value in "value"; plain strings are used as is
    QString fieldValue(const QJsonValue& field)
    {
        if (field.isObject()) {
            return field.toObject().value("value").toVariant().toString();
        }
        return field.toVariant().toString();
    }

    bool isConcealed(const QJsonValue& field)
    {
        return field.isObject() && field.toObject().value("fieldType").toString() == "concealed-string";
    }

    void setUniqueAttribute(Entry* entry, QString name, const QString& value, bool protect)
    {
        if (value.isEmpty()) {
            return;
        }
        if (EntryAttributes::isDefaultAttribute(name) || entry->attributes()->hasKey(name)) {
            name = QString("%1_%2").arg(name, QUuid::createUuid().toString().mid(1, 5));
        }
        entry->attributes()->set(name, value, protect);
    }

    QString toPem(const QString& base64UrlKey)
    {
        auto key = QByteArray::fromBase64(base64UrlKey.toUtf8(), QByteArray::Base64UrlEncoding).toBase64();
        key.prepend(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_START.toUtf8());
        key.append(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_END.toUtf8());
        return QString::fromUtf8(key);
    }

    void readBasicAuth(Entry* entry, const QJsonObject& credential)
    {
        const auto username = fieldValue(credential.value("username"));
        const auto password = fieldValue(credential.value("password"));
        if (entry->username().isEmpty() && entry->password().isEmpty()) {
            entry->setUsername(username);
            entry->setPassword(password);
        } else {
            // Several logins in one item: keep the extra ones as attributes
            setUniqueAttribute(entry, "username", username, false);
            setUniqueAttribute(entry, "password", password, true);
        }
    }

    void readTotp(Entry* entry, const QJsonObject& credential)
    {
        const auto secret = credential.value("secret").toString();
        if (secret.isEmpty() || entry->hasTotp()) {
            return;
        }

        auto algorithm = Totp::Algorithm::Sha1;
        const auto algorithmName = credential.value("algorithm").toString().toLower();
        if (algorithmName == "sha256") {
            algorithm = Totp::Algorithm::Sha256;
        } else if (algorithmName == "sha512") {
            algorithm = Totp::Algorithm::Sha512;
        }

        entry->setTotp(Totp::createSettings(secret,
                                            credential.value("digits").toInt(Totp::DEFAULT_DIGITS),
                                            credential.value("period").toInt(Totp::DEFAULT_STEP),
                                            Totp::DEFAULT_FORMAT,
                                            {},
                                            algorithm));
    }

    void readPasskey(Entry* entry, const QJsonObject& credential)
    {
        // Credential ID and user handle are already base64url like KeePassXC stores them
        const auto username = credential.value("username").toString();
        entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_USERNAME, username);
        entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_RELYING_PARTY, credential.value("rpId").toString());
        entry->attributes()->set(
            EntryAttributes::KPEX_PASSKEY_CREDENTIAL_ID, credential.value("credentialId").toString(), true);
        entry->attributes()->set(
            EntryAttributes::KPEX_PASSKEY_USER_HANDLE, credential.value("userHandle").toString(), true);
        entry->attributes()->set(
            EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_PEM, toPem(credential.value("key").toString()), true);
        if (entry->username().isEmpty()) {
            entry->setUsername(username);
        }
        entry->addTag(QObject::tr("Passkey"));
    }

    void readNote(Entry* entry, const QJsonObject& credential)
    {
        const auto content = fieldValue(credential.value("content"));
        entry->setNotes(entry->notes().isEmpty() ? content : entry->notes() + "\n\n" + content);
    }

    void readCustomFields(Entry* entry, const QJsonObject& credential)
    {
        for (const auto& field : credential.value("fields").toArray()) {
            const auto fieldObj = field.toObject();
            auto name = fieldObj.value("label").toString();
            if (name.isEmpty()) {
                name = fieldObj.value("id").toString();
            }
            setUniqueAttribute(entry, name, fieldValue(field), isConcealed(field));
        }
    }

    // Credit cards, Wi-Fi, SSH and API keys and other types: one attribute per field
    void readOtherCredential(Entry* entry, const QString& type, const QJsonObject& credential)
    {
        for (auto it = credential.constBegin(); it != credential.constEnd(); ++it) {
            if (it.key() == "type" || it.value().isArray()) {
                continue;
            }
            setUniqueAttribute(entry, QString("%1_%2").arg(type, it.key()), fieldValue(it.value()), isConcealed(it.value()));
        }
    }

    Entry* readItem(const QJsonObject& item)
    {
        QScopedPointer<Entry> entry(new Entry());
        entry->setUuid(QUuid::createUuid());
        entry->setTitle(item.value("title").toString());

        if (item.value("favorite").toBool()) {
            entry->addTag(QObject::tr("Favorite", "Tag for favorite entries"));
        }
        for (const auto& tag : item.value("tags").toArray()) {
            entry->addTag(tag.toString());
        }

        int i = 1;
        for (const auto& url : item.value("scope").toObject().value("urls").toArray()) {
            if (entry->url().isEmpty()) {
                entry->setUrl(url.toString());
            } else {
                entry->attributes()->set(
                    QString("%1_%2").arg(EntryAttributes::AdditionalUrlAttribute, QString::number(i++)), url.toString());
            }
        }

        for (const auto& credentialValue : item.value("credentials").toArray()) {
            const auto credential = credentialValue.toObject();
            const auto type = credential.value("type").toString();
            if (type == "basic-auth") {
                readBasicAuth(entry.data(), credential);
            } else if (type == "totp") {
                readTotp(entry.data(), credential);
            } else if (type == "passkey") {
                readPasskey(entry.data(), credential);
            } else if (type == "note") {
                readNote(entry.data(), credential);
            } else if (type == "custom-fields") {
                readCustomFields(entry.data(), credential);
            } else {
                readOtherCredential(entry.data(), type, credential);
            }
        }

        auto timeInfo = entry->timeInfo();
        if (item.contains("creationAt")) {
            timeInfo.setCreationTime(
                QDateTime::fromSecsSinceEpoch(item.value("creationAt").toVariant().toLongLong(), Qt::UTC));
        }
        if (item.contains("modifiedAt")) {
            const auto modified =
                QDateTime::fromSecsSinceEpoch(item.value("modifiedAt").toVariant().toLongLong(), Qt::UTC);
            timeInfo.setLastModificationTime(modified);
            timeInfo.setLastAccessTime(modified);
        }
        entry->setTimeInfo(timeInfo);

        return entry.take();
    }

    // Collections become groups; an item linked from several only goes into the first
    void readCollections(const QJsonArray& collections, Group* parent, QHash<QString, Entry*>& unplacedEntries)
    {
        for (const auto& collectionValue : collections) {
            const auto collection = collectionValue.toObject();
            auto group = new Group();
            group->setUuid(QUuid::createUuid());
            group->setName(collection.value("title").toString());
            group->setNotes(collection.value("subtitle").toString());
            group->setParent(parent);

            for (const auto& link : collection.value("items").toArray()) {
                if (auto entry = unplacedEntries.take(link.toObject().value("item").toString())) {
                    entry->setGroup(group, false);
                }
            }

            readCollections(collection.value("subCollections").toArray(), group, unplacedEntries);
        }
    }

    void readAccount(const QJsonObject& account, Group* group)
    {
        QHash<QString, Entry*> entries;
        for (const auto& item : account.value("items").toArray()) {
            entries.insert(item.toObject().value("id").toString(), readItem(item.toObject()));
        }

        readCollections(account.value("collections").toArray(), group, entries);
        for (auto entry : entries) {
            entry->setGroup(group, false);
        }
    }
} // namespace

bool CxfReader::hasError()
{
    return !m_error.isEmpty();
}

QString CxfReader::errorString()
{
    return m_error;
}

QString CxfReader::exporterName() const
{
    return m_exporterName;
}

QSharedPointer<Database> CxfReader::convert(const QByteArray& json)
{
    m_error.clear();
    m_exporterName.clear();

    QJsonParseError error;
    const auto header = QJsonDocument::fromJson(json, &error).object();
    if (error.error != QJsonParseError::NoError) {
        m_error = QObject::tr("Cannot parse credentials: %1 at position %2")
                      .arg(error.errorString(), QString::number(error.offset));
        return {};
    }

    const auto major = header.value("version").toObject().value("major").toInt(1);
    if (major != 1) {
        m_error = QObject::tr("Unsupported Credential Exchange Format version %1.").arg(major);
        return {};
    }

    auto db = QSharedPointer<Database>::create();
    m_exporterName = header.value("exporterDisplayName").toString();
    db->rootGroup()->setName(m_exporterName.isEmpty() ? QObject::tr("Credential Exchange Import")
                                                      : QObject::tr("%1 Import").arg(m_exporterName));

    const auto accounts = header.value("accounts").toArray();
    for (const auto& accountValue : accounts) {
        const auto account = accountValue.toObject();
        auto group = db->rootGroup();
        // Only separate accounts into groups when there are several
        if (accounts.size() > 1) {
            group = new Group();
            group->setUuid(QUuid::createUuid());
            auto name = account.value("fullName").toString();
            if (name.isEmpty()) {
                name = account.value("username").toString();
            }
            if (name.isEmpty()) {
                name = account.value("email").toString();
            }
            group->setName(name);
            group->setParent(db->rootGroup());
        }
        readAccount(account, group);
    }

    return db;
}
