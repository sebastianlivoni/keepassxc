#include <QCheckBox>
#include <QMouseEvent>
#include <QPainter>
#include <QDateTime>

class AutoFillLaunchAgentCheckbox : public QCheckBox
{
    Q_OBJECT

public:
    explicit AutoFillLaunchAgentCheckbox(QWidget *parent = nullptr);

protected:
    void mousePressEvent(QMouseEvent *e) override;

private slots:
    void checkCredentialProviderEnabled(Qt::ApplicationState state);

private:
    QDateTime m_lastCredentialRequestTime;
};
