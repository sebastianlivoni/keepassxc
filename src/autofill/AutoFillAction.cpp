#include "AutoFillAction.h"
#include "browser/BrowserService.h"

static const QString AUTOFILL_REQUEST_GET_LOGIN = QStringLiteral("get-login");
static const QString AUTOFILL_REQUEST_GET_TOTP = QStringLiteral("get-totp");
static const QString AUTOFILL_REQUEST_PASSKEY_REGISTER = QStringLiteral("passkey-register");
static const QString AUTOFILL_REQUEST_PASSKEY_GET = QStringLiteral("passkey-get");

QJsonObject AutoFillAction::processMessage(QLocalSocket* socket, const QJsonObject& json)
{
    if (json.isEmpty()) {
        return QJsonObject();
    }

    if (!browserService()->isDatabaseOpened()) {
        QJsonObject response;
        response["type"] = "database_locked";
        return response;
    }

    return handleAction(socket, json);
}

QJsonObject AutoFillAction::handleAction(QLocalSocket* socket, const QJsonObject& json)
{
    QString action = json.value("action").toString();

    if (action.compare(AUTOFILL_REQUEST_GET_LOGIN) == 0) {
        return handleGetLogin(json, action);
    } else if (action.compare(AUTOFILL_REQUEST_GET_TOTP) == 0) {
        return handleGetTotp(json, action);
    } else if (action.compare(AUTOFILL_REQUEST_PASSKEY_REGISTER) == 0) {
        return handlePasskeysRegister(json, action);
    } else if (action.compare(AUTOFILL_REQUEST_PASSKEY_GET) == 0) {
        return handlePasskeysGet(json, action);
    }

    QJsonObject response;
    response["type"] = "unknown_action";
    return response;
}

QJsonObject AutoFillAction::handleGetLogin(const QJsonObject& json, const QString& action)
{
    QString uuid = json.value("uuid").toString();
    if (uuid.isEmpty()) {
        return QJsonObject();
    }

    auto entry = browserService()->getEntryByUuid(uuid);
    if (!entry) {
        return QJsonObject();
    }

    auto username = entry->username();
    if (username.isEmpty()) {
        return QJsonObject();
    }

    auto password = entry->password();
    if (password.isEmpty()) {
        return QJsonObject();
    }

    QJsonObject response;
    response["type"] = "password_credential";
    response["username"] = username;
    response["password"] = password;

    return response;
}

QJsonObject AutoFillAction::handleGetTotp(const QJsonObject& json, const QString& action)
{
    QString uuid = json.value("uuid").toString();
    if (uuid.isEmpty()) {
        return QJsonObject();
    }

    auto totp = browserService()->getCurrentTotp(uuid);

    QJsonObject response;
    response["type"] = "totp_credential";
    response["otp"] = totp;

    return response;
}

QJsonObject AutoFillAction::handlePasskeysRegister(const QJsonObject& json, const QString& action)
{
    QJsonObject response;
    response["type"] = "password_credential";
    response["username"] = "username";
    response["password"] = "password";

    return response;
}

QJsonObject AutoFillAction::handlePasskeysGet(const QJsonObject& json, const QString& action)
{
    QJsonObject response;
    response["type"] = "password_credential";
    response["username"] = "username";
    response["password"] = "password";

    return response;
}