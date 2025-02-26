#include "AutoFillViewController.h"

#include <QtWidgets/QWidget>
#include <QtWidgets/QPushButton>
#include <QtWidgets/QLabel>
#include <QtWidgets/QVBoxLayout>

#include "ExtensionConfigurationWidget.h"

@implementation AutoFillViewController

- (instancetype)initWithExtensionContext:(ASCredentialProviderExtensionContext *)extensionContext {
    self = [super init];
    if (self) {
        _extensionContext = extensionContext;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    QWidget* widget = new ExtensionConfigurationWidget(self.extensionContext);

    [self embedQWidget:widget];
}

- (void) embedQWidget:(QWidget *)widget {
    NSView* rootView = (__bridge NSView*)reinterpret_cast<void*>(widget->winId());

    [self.view.widthAnchor constraintEqualToConstant:rootView.frame.size.width].active = YES;
    [self.view.heightAnchor constraintEqualToConstant:rootView.frame.size.height].active = YES;

    [self.view addSubview:rootView];
}

- (void)onButtonClicked {
    [self.extensionContext completeExtensionConfigurationRequest];
}

@end