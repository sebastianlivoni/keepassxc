#ifndef KEEPASSX_APPLICATION_H
#define KEEPASSX_APPLICATION_H

#include <QApplication>

class AutoFillExtensionApplication : public QApplication
{
    Q_OBJECT

public:
    AutoFillExtensionApplication(int& argc, char** argv);

private:
    void applyTheme();
};

#endif // KEEPASSX_APPLICATION_H
