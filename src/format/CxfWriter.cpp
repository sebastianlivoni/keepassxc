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

#include "CxfWriter.h"

#include "core/Database.h"
#include "core/Entry.h"
#include "core/Group.h"
#include "core/Metadata.h"
#include "core/Totp.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace
{
    // CXF ids are base64url encoded bytes
    QString cxfId(const QUuid& uuid)
    {
        return QString::fromLatin1(
            uuid.toRfc4122().toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
    }

    // Stored values may be base64 or base64url, padded or not; CXF wants unpadded base64url.
    // A value that isn't base64 at all is taken as the raw bytes.
    QString toBase64Url(const QString& value)
    {
        const auto encoded = value.trimmed().toLatin1();
        auto decoded = QByteArray::fromBase64Encoding(
            encoded, QByteArray::Base64UrlEncoding | QByteArray::AbortOnBase64DecodingErrors);
        if (!decoded) {
            decoded = QByteArray::fromBase64Encoding(encoded, QByteArray::AbortOnBase64DecodingErrors);
        }
        const auto bytes = decoded ? *decoded : value.toUtf8();
        return QString::fromLatin1(bytes.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
    }

    QJsonObject editableField(const QString& value, bool concealed = false)
    {
        return {{"fieldType", concealed ? "concealed-string" : "string"}, {"value", value}};
    }

    // Attributes already exported as their own credential, or KeePassXC internals
    bool isExportedElsewhere(const QString& key)
    {
        static const QStringList totpKeys = {"otp", "TOTP Seed", "TOTP Settings"};
        return totpKeys.contains(key) || key.startsWith("TimeOtp-") || key.startsWith("KPEX_")
               || key.startsWith("KPXC_") || key.startsWith(EntryAttributes::AdditionalUrlAttribute);
    }

    QJsonObject totpCredential(const Entry* entry)
    {
        const auto settings = entry->totpSettings();
        // Steam and other custom encoders don't fit CXF's TOTP
        if (!settings || !settings->encoder.shortName.isEmpty()) {
            return {};
        }

        QString algorithm = "sha1";
        if (settings->algorithm == Totp::Algorithm::Sha256) {
            algorithm = "sha256";
        } else if (settings->algorithm == Totp::Algorithm::Sha512) {
            algorithm = "sha512";
        }

        return {{"type", "totp"},
                {"secret", settings->key},
                {"period", static_cast<int>(settings->step)},
                {"digits", static_cast<int>(settings->digits)},
                {"algorithm", algorithm},
                {"username", entry->username()},
                {"issuer", entry->title()}};
    }

    QJsonObject passkeyCredential(const Entry* entry)
    {
        const auto attributes = entry->attributes();
        // PEM to the base64url encoded PKCS#8 DER CXF expects
        auto pem = attributes->value(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_PEM);
        pem.remove(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_START).remove(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_END);
        const auto key = QByteArray::fromBase64(pem.simplified().remove(' ').toLatin1())
                             .toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals);

        const auto username = attributes->value(EntryAttributes::KPEX_PASSKEY_USERNAME);
        return {{"type", "passkey"},
                {"credentialId", toBase64Url(attributes->value(EntryAttributes::KPEX_PASSKEY_CREDENTIAL_ID))},
                {"rpId", attributes->value(EntryAttributes::KPEX_PASSKEY_RELYING_PARTY)},
                {"username", username},
                {"userDisplayName", username},
                {"userHandle", toBase64Url(attributes->value(EntryAttributes::KPEX_PASSKEY_USER_HANDLE))},
                {"key", QString::fromLatin1(key)}};
    }

    QJsonObject writeItem(const Entry* entry)
    {
        QJsonArray credentials;
        if (!entry->username().isEmpty() || !entry->password().isEmpty()) {
            credentials.append(QJsonObject{{"type", "basic-auth"},
                                           {"username", editableField(entry->username())},
                                           {"password", editableField(entry->password(), true)}});
        }
        if (entry->hasTotp()) {
            const auto totp = totpCredential(entry);
            if (!totp.isEmpty()) {
                credentials.append(totp);
            }
        }
        if (entry->hasPasskey()) {
            credentials.append(passkeyCredential(entry));
        }
        if (!entry->notes().isEmpty()) {
            credentials.append(QJsonObject{{"type", "note"}, {"content", editableField(entry->notes())}});
        }

        QJsonArray fields;
        const auto attributes = entry->attributes();
        for (const auto& key : attributes->customKeys()) {
            if (!isExportedElsewhere(key)) {
                auto field = editableField(attributes->value(key), attributes->isProtected(key));
                field.insert("label", key);
                fields.append(field);
            }
        }
        if (!fields.isEmpty()) {
            credentials.append(QJsonObject{{"type", "custom-fields"}, {"fields", fields}});
        }

        QJsonArray urls;
        if (!entry->url().isEmpty()) {
            urls.append(entry->url());
        }
        for (const auto& key : attributes->keys()) {
            if (key.startsWith(EntryAttributes::AdditionalUrlAttribute)) {
                urls.append(attributes->value(key));
            }
        }

        return {{"id", cxfId(entry->uuid())},
                {"creationAt", entry->timeInfo().creationTime().toSecsSinceEpoch()},
                {"modifiedAt", entry->timeInfo().lastModificationTime().toSecsSinceEpoch()},
                {"title", entry->title()},
                {"scope", QJsonObject{{"urls", urls}, {"androidApps", QJsonArray()}}},
                {"tags", QJsonArray::fromStringList(entry->tagList())},
                {"credentials", credentials}};
    }

    QJsonObject writeCollection(const Group* group, const QString& accountId, const Group* recycleBin)
    {
        QJsonArray items;
        for (const auto entry : group->entries()) {
            items.append(QJsonObject{{"item", cxfId(entry->uuid())}, {"account", accountId}});
        }

        QJsonArray subCollections;
        for (const auto child : group->children()) {
            if (child != recycleBin) {
                subCollections.append(writeCollection(child, accountId, recycleBin));
            }
        }

        return {{"id", cxfId(group->uuid())},
                {"title", group->name()},
                {"subtitle", group->notes()},
                {"items", items},
                {"subCollections", subCollections}};
    }
} // namespace

QByteArray CxfWriter::write(const QSharedPointer<const Database>& db)
{
    const auto root = db->rootGroup();
    const auto recycleBin = db->metadata()->recycleBin();
    const auto accountId = cxfId(db->uuid());

    QJsonArray items;
    for (const auto entry : root->entriesRecursive()) {
        if (!entry->isRecycled()) {
            items.append(writeItem(entry));
        }
    }

    // Entries directly in the root group belong to the account without a collection
    QJsonArray collections;
    for (const auto child : root->children()) {
        if (child != recycleBin) {
            collections.append(writeCollection(child, accountId, recycleBin));
        }
    }

    const QJsonObject account{{"id", accountId},
                              {"username", db->metadata()->name()},
                              {"email", QString()},
                              {"collections", collections},
                              {"items", items}};

    const QJsonObject header{{"version", QJsonObject{{"major", 1}, {"minor", 0}}},
                             {"exporterRpId", "keepassxc.org"},
                             {"exporterDisplayName", "KeePassXC"},
                             {"timestamp", QDateTime::currentSecsSinceEpoch()},
                             {"accounts", QJsonArray{account}}};

    return QJsonDocument(header).toJson(QJsonDocument::Compact);
}
