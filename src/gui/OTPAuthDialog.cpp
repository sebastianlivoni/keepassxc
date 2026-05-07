#include "OTPAuthDialog.h"
#include "ui_OTPAuthDialog.h"

#include <QLabel>
#include <QVBoxLayout>
#include <QSortFilterProxyModel>
#include <QStandardItemModel>
#include <QPointer>
#include <QSharedPointer>
#include <QDebug>

#include "core/AsyncTask.h"
#include "gui/Icons.h"
#include "core/EntrySearcher.h"

namespace
{
    class OTPList
    {
    public:
        struct Item
        {
            QPointer<Group> group;
            QPointer<Entry> entry;

            Item(Group* g, Entry* e)
                : group(g)
                , entry(e)
            {
            }
        };

        explicit OTPList(const QSharedPointer<Database>&);

        const QList<QSharedPointer<Item>>& items() const
        {
            return m_items;
        }
    private:
        QSharedPointer<Database> m_db;
        QList<QSharedPointer<Item>> m_items;
    };
}

OTPList::OTPList (const QSharedPointer<Database>& db) : m_db(db)
{
    for (auto group : db->rootGroup()->groupsRecursive(true)) {
        // Skip recycle bin
        if (group->isRecycled()) {
            continue;
        }

        for (auto entry : group->entries()) {
            if (entry->isRecycled()/* || entry->attributes()->contains(Totp::ATTRIBUTE_OTP)*/) {
                continue;
            }

            const auto item = QSharedPointer<Item>(new Item(group, entry));
            m_items.append(item);
        }
    }
}

OTPAuthDialog::OTPAuthDialog(QWidget* parent)
    : QDialog(parent)
    , m_ui(new Ui::OTPAuthDialog())
    , m_referencesModel(new QStandardItemModel(this))
    , m_modelProxy(new QSortFilterProxyModel(this))
    , m_entrySearcher(new EntrySearcher(false))
{
    m_ui->setupUi(this);

    connect(m_ui->buttonBox, SIGNAL(rejected()), SLOT(close()));
    connect(m_ui->buttonBox, SIGNAL(accepted()), SLOT(select()));

    m_modelProxy->setSourceModel(m_referencesModel.data());
    m_modelProxy->setSortLocaleAware(true);

    m_ui->otpTableView->setModel(m_modelProxy.data());
    m_ui->otpTableView->setSelectionBehavior(QAbstractItemView::SelectRows);

    m_ui->otpTableView->setSortingEnabled(true);
    m_modelProxy->setSortCaseSensitivity(Qt::CaseInsensitive);
    m_modelProxy->setDynamicSortFilter(true);
    m_modelProxy->setSortRole(Qt::UserRole);

    connect(m_ui->searchWidget, SIGNAL(search(QString)), SLOT(search(QString)));

    connect(m_ui->otpTableView->horizontalHeader(), &QHeaderView::sortIndicatorChanged, this, &OTPAuthDialog::resetFixedColumns);

    /*m_searchWidget = new SearchWidget();
    m_ui->verticalLayout->addWidget(m_searchWidget);*/
}

void OTPAuthDialog::setTotp(QSharedPointer<Totp::Settings> totp)
{
    m_totp = totp;
}

void OTPAuthDialog::select()
{
    QItemSelectionModel *selectionModel = m_ui->otpTableView->selectionModel();

    if (selectionModel) {
        QModelIndexList selectedIndexes = selectionModel->selectedRows();

        if (!selectedIndexes.isEmpty()) {
            // Map from proxy index back to source model index
            QModelIndex sourceIndex = m_modelProxy->mapToSource(selectedIndexes.first());
            int selectedRow = sourceIndex.row();

            if (selectedRow >= 0 && selectedRow < m_rowToEntry.size()) {
                auto groupEntryPair = m_rowToEntry[selectedRow];
                QPointer<Entry> selectedEntry = groupEntryPair.second;

                //selectedEntry->setTotp(m_totp);
                //hide();
                emit entrySelected(selectedEntry, m_totp);
            }
        }
    }
}

void OTPAuthDialog::close()
{
    hide();
}

void OTPAuthDialog::load(QList<QSharedPointer<Database>> dbs)
{
    m_referencesModel->clear();
    m_rowToEntry.clear();

    m_referencesModel->setHorizontalHeaderLabels(QStringList() << tr("") << tr("Title"));

    m_referencesModel->horizontalHeaderItem(0)->setIcon(icons()->icon("totp"));
    m_referencesModel->horizontalHeaderItem(1)->setText("Title");

    resetFixedColumns();
    m_modelProxy->sort(0, Qt::AscendingOrder);
    m_ui->otpTableView->horizontalHeader()->setSortIndicator(0, Qt::AscendingOrder);

    for (const auto& db : dbs) {
        const QScopedPointer<OTPList> otpList(
            AsyncTask::runAndWaitForFuture([db] {
                return new OTPList(db);
            }));

        for (const auto& item : otpList->items()) {
            auto row = QList<QStandardItem*>();

            auto group = item->group;
            auto entry = item->entry;

            auto title = entry->title();

            auto iconItem = new QStandardItem("");
            iconItem->setData(0, Qt::UserRole);

            auto titleItem = new QStandardItem(Icons::entryIconPixmap(entry), title);
            titleItem->setData(title, Qt::UserRole);

            if (entry->attributes()->contains(Totp::ATTRIBUTE_OTP)) {
                iconItem = new QStandardItem(icons()->icon("totp"), "");
                iconItem->setData(1, Qt::UserRole);
                iconItem->setToolTip(tr("This entry already has a TOTP configured"));
                titleItem->setToolTip(tr("This entry already has a TOTP configured"));

                // Gray out like a disabled item
                iconItem->setForeground(QApplication::palette().color(QPalette::Disabled, QPalette::Text));
                titleItem->setForeground(QApplication::palette().color(QPalette::Disabled, QPalette::Text));

                iconItem->setFlags(iconItem->flags() & ~Qt::ItemIsEnabled & ~Qt::ItemIsSelectable);
                titleItem->setFlags(titleItem->flags() & ~Qt::ItemIsEnabled & ~Qt::ItemIsSelectable);
            }

            row << iconItem;
            row << titleItem;

            m_referencesModel->appendRow(row);
            m_rowToEntry.append({group, entry});
        }
    }
}

void OTPAuthDialog::search(const QString& searchtext) {
    /*QList<QSharedPointer<Entry>> entries;

    for (const auto& pair : m_rowToEntry) {
        entries.append(pair.second);
    }*/

    qDebug() << searchtext;

    //auto results = m_entrySearcher->searchEntries(searchtext, entries);
}

void OTPAuthDialog::resetFixedColumns()
{
    auto header = m_ui->otpTableView->horizontalHeader();
    header->setMinimumSectionSize(1);
    header->setSectionResizeMode(0, QHeaderView::Fixed);
    header->setSectionResizeMode(1, QHeaderView::Stretch);

    int width = 26;
    if (header->sortIndicatorSection() == 0
        && config()->get(Config::GUI_ApplicationTheme).toString() != "classic") {
        width += 18;
    }
    header->resizeSection(0, width);
}

OTPAuthDialog::~OTPAuthDialog() = default;
