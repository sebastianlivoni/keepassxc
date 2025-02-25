#include <QFile>

class BookmarkFile : public QFile
{

public:
    BookmarkFile(const QString &fileName);
    bool open(QIODevice::OpenMode mode) override;
    void close() override;
private:
    NSString* bookmarkKey();
};