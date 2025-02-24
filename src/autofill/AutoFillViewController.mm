#include "AutoFillViewController.h"

#include <QtWidgets/QWidget>
#include <QtWidgets/QPushButton>
#include <QtWidgets/QLabel>
#include <QtWidgets/QVBoxLayout>

@implementation AutoFillViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    QPushButton* btn = new QPushButton("Some Button");
    QLabel* lbl = new QLabel("QTGui");
    QVBoxLayout* layout = new QVBoxLayout();
    layout->addWidget(lbl);
    layout->addWidget(btn);

    QWidget* window = new QWidget();
    window->setLayout(layout);
    window->show();
    window->resize(500, 300);

    NSView* rootView = (__bridge NSView*)reinterpret_cast<void*>(window->winId());

    //NSView *rootView = [[NSView alloc] init];
    
    [self.view addSubview:rootView];
}

@end