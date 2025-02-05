#include "core/Entry.h"
#include <QJsonObject>
#include <QLocalSocket>
#include <QString>

class AutoFillAction
{
public:
    explicit AutoFillAction() = default;
    ~AutoFillAction() = default;

    QJsonObject processMessage(QLocalSocket* socket, const QJsonObject& json);

private:
    QJsonObject handleAction(QLocalSocket* socket, const QJsonObject& json);
    QJsonObject handleGetLogin(const QJsonObject& json, const QString& action); // Fixed colon
    QJsonObject handleGetTotp(const QJsonObject& json, const QString& action); // Fixed colon
    QJsonObject handlePasskeysRegister(const QJsonObject& json, const QString& action);
    QJsonObject handlePasskeysGet(const QJsonObject& json, const QString& action);

    QSharedPointer<Database> getDatabase(const QUuid& rootGroupUuid = {});
    QList<QSharedPointer<Database>> getOpenDatabases();
};