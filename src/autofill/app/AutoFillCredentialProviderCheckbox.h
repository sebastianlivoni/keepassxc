#ifndef KEEPASSXC_AUTOFILLCREDENTIALPROVIDERCHECKBOX_H
#define KEEPASSXC_AUTOFILLCREDENTIALPROVIDERCHECKBOX_H

#include <QCheckBox>
#include <QDateTime>

class AutoFillCredentialProviderCheckbox : public QCheckBox
{
    Q_OBJECT

public:
    explicit AutoFillCredentialProviderCheckbox(QWidget* parent = nullptr);

protected:
    void nextCheckState() override;

private slots:
    void checkCredentialProviderEnabled(Qt::ApplicationState state);

private:
    QDateTime m_lastCredentialRequestTime;
};

#endif // KEEPASSXC_AUTOFILLCREDENTIALPROVIDERCHECKBOX_H
