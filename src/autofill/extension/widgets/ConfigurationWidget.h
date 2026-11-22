#include <QWidget>
#include <functional>

#ifndef CONFIGURATIONWIDGET_H
#define CONFIGURATIONWIDGET_H

// Shown once after KeePassXC is enabled as AutoFill provider in System Settings
class ConfigurationWidget : public QWidget
{
public:
    explicit ConfigurationWidget(QWidget* parent = nullptr);

    std::function<void()> onDone;

protected:
    void keyPressEvent(QKeyEvent* event) override;

private:
    void done();
};

#endif // CONFIGURATIONWIDGET_H
