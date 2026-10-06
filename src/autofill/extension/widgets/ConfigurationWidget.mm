#include "extension/widgets/ConfigurationWidget.h"

#include <QHBoxLayout>
#include <QKeyEvent>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>

#include "gui/Icons.h"

ConfigurationWidget::ConfigurationWidget(QWidget* parent)
    : QWidget(parent)
{
    // Styled like DatabasePickerWidget (icon, headline, text)
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(30, 30, 30, 30);
    layout->setSpacing(12);

    auto* iconLabel = new QLabel(this);
    iconLabel->setPixmap(icons()->applicationIcon().pixmap(64));
    iconLabel->setAlignment(Qt::AlignCenter);
    layout->addWidget(iconLabel);

    auto* title = new QLabel(tr("KeePassXC AutoFill is enabled"), this);
    QFont titleFont = title->font();
    titleFont.setBold(true);
    titleFont.setPointSize(titleFont.pointSize() + 4);
    title->setFont(titleFont);
    title->setAlignment(Qt::AlignCenter);
    layout->addWidget(title);

    auto* howItWorks = new QLabel(tr("When you sign in to a website or app, KeePassXC suggests matching "
                                     "passwords, passkeys and one-time codes. Pick one to fill it in."),
                                  this);
    howItWorks->setWordWrap(true);
    howItWorks->setAlignment(Qt::AlignCenter);
    layout->addWidget(howItWorks);

    layout->addStretch();

    auto* buttonLayout = new QHBoxLayout();
    auto* doneButton = new QPushButton(tr("Done"), this);
    doneButton->setStyleSheet("text-align:center;");
    doneButton->setDefault(true);
    buttonLayout->addStretch();
    buttonLayout->addWidget(doneButton);
    layout->addLayout(buttonLayout);

    connect(doneButton, &QPushButton::clicked, this, &ConfigurationWidget::done);

    setLayout(layout);
    resize(420, 260);
}

// Default buttons only react to Return inside a QDialog
void ConfigurationWidget::keyPressEvent(QKeyEvent* event)
{
    if (event->key() == Qt::Key_Return || event->key() == Qt::Key_Enter || event->key() == Qt::Key_Escape) {
        done();
    } else {
        QWidget::keyPressEvent(event);
    }
}

void ConfigurationWidget::done()
{
    if (onDone) {
        auto callback = onDone;
        // Complete only once, e.g. on a double click
        onDone = nullptr;
        callback();
    }
}
