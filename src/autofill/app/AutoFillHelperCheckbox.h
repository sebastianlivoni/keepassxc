#include <QCheckBox>
#include <QMouseEvent>
#include <QPainter>
#include <QDateTime>

class AutoFillHelperCheckbox : public QCheckBox
{
    Q_OBJECT

public:
    explicit AutoFillHelperCheckbox(QWidget *parent = nullptr);

protected:
    void mousePressEvent(QMouseEvent *e) override;

private slots:
    void checkHelperEnabled(Qt::ApplicationState state);

private:
    QDateTime m_lastCredentialRequestTime;
};
