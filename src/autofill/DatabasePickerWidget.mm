#include "DatabasePickerWidget.h"

#include <QFileInfo>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QVBoxLayout>

#include "core/Config.h"

namespace
{
    const int PathRole = Qt::UserRole;
}

DatabasePickerWidget::DatabasePickerWidget(QWidget* parent)
    : QWidget(parent)
    , m_list(nullptr)
{
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(40, 40, 40, 40);
    layout->setSpacing(20);

    auto* title = new QLabel(tr("Choose a database"), this);
    QFont titleFont = title->font();
    titleFont.setPointSize(16);
    titleFont.setBold(true);
    title->setFont(titleFont);
    title->setAlignment(Qt::AlignCenter);
    layout->addWidget(title);

    m_list = new QListWidget(this);
    const auto databasePaths = config()->getAllDatabaseFilePaths();
    for (auto it = databasePaths.constBegin(); it != databasePaths.constEnd(); ++it) {
        const QString& path = it.value();
        auto* item = new QListWidgetItem(QFileInfo(path).fileName(), m_list);
        item->setToolTip(path);
        item->setData(PathRole, path);
    }
    if (m_list->count() > 0) {
        m_list->setCurrentRow(0);
    }
    connect(m_list, &QListWidget::itemDoubleClicked, this, &DatabasePickerWidget::chooseSelected);
    layout->addWidget(m_list);

    auto* buttonLayout = new QHBoxLayout();
    buttonLayout->setSpacing(15);
    auto* cancelButton = new QPushButton(tr("Cancel"), this);
    auto* chooseButton = new QPushButton(tr("Choose"), this);
    buttonLayout->addStretch();
    buttonLayout->addWidget(cancelButton);
    buttonLayout->addWidget(chooseButton);
    buttonLayout->addStretch();
    layout->addLayout(buttonLayout);

    connect(cancelButton, &QPushButton::clicked, this, [this]() {
        if (onCancelled) {
            onCancelled();
        }
    });
    connect(chooseButton, &QPushButton::clicked, this, &DatabasePickerWidget::chooseSelected);

    setLayout(layout);
    resize(450, 350);
}

void DatabasePickerWidget::chooseSelected()
{
    auto* item = m_list->currentItem();
    if (!item) {
        return;
    }

    if (onDatabaseChosen) {
        onDatabaseChosen(item->data(PathRole).toString());
    }
}
