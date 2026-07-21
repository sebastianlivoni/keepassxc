#include <QWidget>
#include <functional>

#ifndef DATABASEPICKERWIDGET_H
#define DATABASEPICKERWIDGET_H

class QListWidget;

// Lets the user pick which registered AutoFill database to use when more
// than one is known to Config::getAllDatabaseFilePaths(). Uses plain
// callbacks rather than Qt signals to match DatabaseUnlockWidget's style.
class DatabasePickerWidget : public QWidget
{
public:
    explicit DatabasePickerWidget(QWidget* parent = nullptr);

    std::function<void(QString)> onDatabaseChosen;
    std::function<void()> onCancelled;

private:
    void chooseSelected();

    QListWidget* m_list;
};

#endif // DATABASEPICKERWIDGET_H
