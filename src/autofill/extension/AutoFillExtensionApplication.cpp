#include "extension/AutoFillExtensionApplication.h"
#include "core/Config.h"
#include "core/Translator.h"
#include "gui/osutils/OSUtils.h"
#include "gui/styles/dark/DarkStyle.h"
#include "gui/styles/light/LightStyle.h"

#include <QDir>
#include <QPixmapCache>

AutoFillExtensionApplication::AutoFillExtensionApplication(int& argc, char** argv) : QApplication(argc, argv) {
    applyTheme();
    connect(osUtils, &OSUtilsBase::interfaceThemeChanged, this, &AutoFillExtensionApplication::applyTheme);

    // Translations ship in the containing app:
    // KeePassXC.app/Contents/PlugIns/<extension>.appex/Contents/MacOS -> KeePassXC.app/Contents/Resources
    const auto translationsPath =
        QDir(applicationDirPath() + QStringLiteral("/../../../../Resources/translations")).canonicalPath();
    Translator::installTranslators(config()->get(Config::GUI_Language).toString(), translationsPath);
}

// Mirrors Application::applyTheme(); classic falls back to following the system
void AutoFillExtensionApplication::applyTheme()
{
    auto appTheme = config()->get(Config::GUI_ApplicationTheme).toString();
    if (appTheme != "light" && appTheme != "dark") {
        appTheme = osUtils->isDarkMode() ? "dark" : "light";
    }

    QPixmapCache::clear();
    QStyle* s = appTheme == "dark" ? static_cast<QStyle*>(new DarkStyle) : new LightStyle;
    setPalette(s->standardPalette());
    // macOS gives item views their own palette (accent-coloured selection); use ours
    setPalette(s->standardPalette(), "QAbstractItemView");
    setStyle(s);
}
