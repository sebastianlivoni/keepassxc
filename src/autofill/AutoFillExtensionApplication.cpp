#include "AutoFillExtensionApplication.h"
#include "gui/styles/light/LightStyle.h"

AutoFillExtensionApplication::AutoFillExtensionApplication(int& argc, char** argv) : QApplication(argc, argv) {
    auto* s = new LightStyle;
    setPalette(s->standardPalette());
    setStyle(s);
}
