#include <QDialog>
#include <QSortFilterProxyModel>
#include <QStandardItemModel>

#include "core/Database.h"
#include "core/Entry.h"
#include "core/Group.h"
#include "core/Totp.h"

namespace Ui
{
    class OTPAuthDialog;
}

class EntrySearcher;

class OTPAuthDialog : public QDialog
{
    Q_OBJECT

public:
    explicit OTPAuthDialog(QWidget* parent = nullptr);

    ~OTPAuthDialog() override;

    void load(QList<QSharedPointer<Database>> dbs);
    void setTotp(QSharedPointer<Totp::Settings> totp);

private:
    QScopedPointer<Ui::OTPAuthDialog> m_ui;

    QScopedPointer<QStandardItemModel> m_referencesModel;
    QScopedPointer<QSortFilterProxyModel> m_modelProxy;
    QSharedPointer<Database> m_db;
    QList<QPair<Group*, Entry*>> m_rowToEntry;

    QSharedPointer<Totp::Settings> m_totp;

    QScopedPointer<EntrySearcher> m_entrySearcher;

private slots:
    void select();
    void close();

    void search(const QString& searchtext);
    void resetFixedColumns();

signals:
    void entrySelected(Entry* entry, QSharedPointer<Totp::Settings> totp);
};
