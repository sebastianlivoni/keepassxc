#ifndef KEEPASSXC_AUTOFILLEXTENSIONAPPLICATION_H
#define KEEPASSXC_AUTOFILLEXTENSIONAPPLICATION_H

#include <QApplication>

class AutoFillExtensionApplication : public QApplication
{
    Q_OBJECT

public:
    AutoFillExtensionApplication(int& argc, char** argv);

private:
    void applyTheme();
};

#endif // KEEPASSXC_AUTOFILLEXTENSIONAPPLICATION_H
