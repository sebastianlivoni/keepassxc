#include <QWidget>
#include <functional>

#ifndef DATABASEPICKERWIDGET_H
#define DATABASEPICKERWIDGET_H

class QListWidget;

// Lets the user pick a database when several are registered for AutoFill;
// uses plain callbacks rather than signals, like DatabaseUnlockWidget
class DatabasePickerWidget : public QWidget
{
public:
    explicit DatabasePickerWidget(QWidget* parent = nullptr);

    std::function<void(QString)> onDatabaseChosen;
    std::function<void()> onCancelled;

protected:
    void keyPressEvent(QKeyEvent* event) override;

private:
    void chooseSelected();

    QListWidget* m_list;
};

#endif // DATABASEPICKERWIDGET_H
