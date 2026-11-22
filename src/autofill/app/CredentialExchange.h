#ifndef KEEPASSXC_CREDENTIALEXCHANGE_H
#define KEEPASSXC_CREDENTIALEXCHANGE_H

#include <QByteArray>
#include <QList>
#include <QObject>
#include <functional>

class QWidget;

// Credential Exchange with other apps (macOS 26): receives imports and starts exports
class CredentialExchange : public QObject {
  Q_OBJECT

public:
  static CredentialExchange *instance();

  // Hooks Qt's app delegate; call once the QApplication exists, before its event loop runs
  void start();

  // Received exports as CXF JSON, including those that arrived before anyone listened
  QList<QByteArray> takePendingImports();
  void addImport(const QByteArray &cxfJson);

  // macOS 26 and built with the Swift bridge
  bool isExportSupported() const;
  // Shows the system export UI over window; done gets an empty string on success
  void exportCredentials(const QByteArray &cxfJson, QWidget *window,
                         const std::function<void(const QString &error)> &done);

signals:
  void importReceived();

private:
  QList<QByteArray> m_pendingImports;
  bool m_started{false};
};

static inline CredentialExchange *credentialExchange() {
  return CredentialExchange::instance();
}

#endif // KEEPASSXC_CREDENTIALEXCHANGE_H
