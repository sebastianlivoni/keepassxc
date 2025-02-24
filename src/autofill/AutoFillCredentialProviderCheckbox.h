#include <QCheckBox>
#include <QMouseEvent>
#include <QPainter>

class AutoFillCredentialProviderCheckbox : public QCheckBox
{
    Q_OBJECT

public:
    explicit AutoFillCredentialProviderCheckbox(QWidget *parent = nullptr);

protected:
    void mousePressEvent(QMouseEvent *e) override;
    void mouseReleaseEvent(QMouseEvent *e) override;

private slots:
    void checkCredentialProviderEnabled(Qt::ApplicationState state);
};