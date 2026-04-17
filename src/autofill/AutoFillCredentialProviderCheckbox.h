#include <QCheckBox>
#include <QMouseEvent>
#include <QPainter>
#include <QDateTime>

#ifdef __OBJC__
#include "rendezvous/AutoFillXPCService.h"
#endif

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

    #ifdef __OBJC__
    __strong AutoFillXPCService *m_xpcService;
    #endif
};
