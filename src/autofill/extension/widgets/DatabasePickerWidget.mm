#include "extension/widgets/DatabasePickerWidget.h"

#include <QFileInfo>
#include <QHBoxLayout>
#include <QKeyEvent>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QVBoxLayout>

#include "core/Config.h"
#include "gui/Icons.h"

namespace
{
    const int PathRole = Qt::UserRole;
}

DatabasePickerWidget::DatabasePickerWidget(QWidget* parent)
    : QWidget(parent)
    , m_list(nullptr)
{
    // Styled like the main app's WelcomeWidget (icon, headline, recent databases list)
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(30, 30, 30, 30);
    layout->setSpacing(12);

    auto* iconLabel = new QLabel(this);
    iconLabel->setPixmap(icons()->applicationIcon().pixmap(64));
    iconLabel->setAlignment(Qt::AlignCenter);
    layout->addWidget(iconLabel);

    auto* title = new QLabel(tr("Choose a database to AutoFill from"), this);
    QFont titleFont = title->font();
    titleFont.setBold(true);
    titleFont.setPointSize(titleFont.pointSize() + 4);
    title->setFont(titleFont);
    title->setAlignment(Qt::AlignCenter);
    layout->addWidget(title);

    layout->addSpacing(8);

    m_list = new QListWidget(this);
    m_list->setAccessibleName(tr("Choose a database for AutoFill"));
    const auto databasePaths = config()->getAllDatabaseFilePaths();
    for (auto it = databasePaths.constBegin(); it != databasePaths.constEnd(); ++it) {
        const QString& path = it.value();
        auto* item = new QListWidgetItem(path, m_list);
        item->setToolTip(path);
        item->setData(PathRole, path);
    }
    if (m_list->count() > 0) {
        m_list->setCurrentRow(0);
    }
    connect(m_list, &QListWidget::itemActivated, this, &DatabasePickerWidget::chooseSelected);
    layout->addWidget(m_list);

    auto* buttonLayout = new QHBoxLayout();
    auto* cancelButton = new QPushButton(tr("Cancel"), this);
    auto* chooseButton = new QPushButton(tr("Choose"), this);
    cancelButton->setStyleSheet("text-align:center;");
    chooseButton->setStyleSheet("text-align:center;");
    // Default buttons are green in the KeePassXC styles
    chooseButton->setDefault(true);
    buttonLayout->addStretch();
    buttonLayout->addWidget(cancelButton);
    buttonLayout->addWidget(chooseButton);
    layout->addLayout(buttonLayout);

    connect(cancelButton, &QPushButton::clicked, this, [this]() {
        if (onCancelled) {
            onCancelled();
        }
    });
    connect(chooseButton, &QPushButton::clicked, this, &DatabasePickerWidget::chooseSelected);

    setLayout(layout);
    resize(500, 380);
}

// Return doesn't activate list items on macOS, and default buttons only react
// to it inside a QDialog
void DatabasePickerWidget::keyPressEvent(QKeyEvent* event)
{
    if (event->key() == Qt::Key_Return || event->key() == Qt::Key_Enter) {
        chooseSelected();
    } else if (event->key() == Qt::Key_Escape && onCancelled) {
        onCancelled();
    } else {
        QWidget::keyPressEvent(event);
    }
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
