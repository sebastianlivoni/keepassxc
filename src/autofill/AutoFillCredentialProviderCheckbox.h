#include <QCheckBox>
#include <QMouseEvent>
#include <QPainter>
#include <QDateTime>

class AutoFillCredentialProviderCheckbox : public QCheckBox
{
    Q_OBJECT

public:
    explicit AutoFillCredentialProviderCheckbox(QWidget *parent = nullptr);

protected:
    void mousePressEvent(QMouseEvent *e) override;

private slots:
    void checkCredentialProviderEnabled(Qt::ApplicationState state);

private:
    QDateTime m_lastCredentialRequestTime;
};
