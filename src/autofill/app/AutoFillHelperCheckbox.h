#ifndef KEEPASSXC_AUTOFILLHELPERCHECKBOX_H
#define KEEPASSXC_AUTOFILLHELPERCHECKBOX_H

#include <QCheckBox>

class AutoFillHelperCheckbox : public QCheckBox
{
    Q_OBJECT

public:
    explicit AutoFillHelperCheckbox(QWidget* parent = nullptr);

protected:
    void nextCheckState() override;

private slots:
    void checkHelperEnabled(Qt::ApplicationState state);
};

#endif // KEEPASSXC_AUTOFILLHELPERCHECKBOX_H
