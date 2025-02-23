#include "SafariWebExtensionCheckbox.h"

#include <QApplication>

#import <SafariServices/SafariServices.h>

SafariWebExtensionCheckbox::SafariWebExtensionCheckbox(QWidget *parent)
    : QCheckBox(parent)
{
    connect(qApp, &QApplication::applicationStateChanged, this, &SafariWebExtensionCheckbox::onApplicationStateChanged);
}

void SafariWebExtensionCheckbox::mousePressEvent(QMouseEvent *e) {
    if (e->button() == Qt::LeftButton) {
        [SFSafariApplication showPreferencesForExtensionWithIdentifier:@"me.livoni.KeePassXC.SafariWebExtension" completionHandler:nil];
    }
}

void SafariWebExtensionCheckbox::mouseReleaseEvent(QMouseEvent *e) { }

void SafariWebExtensionCheckbox::onApplicationStateChanged(Qt::ApplicationState state)
{
    if (state != Qt::ApplicationActive) {
        return;
    }

    [SFSafariExtensionManager getStateOfSafariExtensionWithIdentifier:@"me.livoni.KeePassXC.SafariWebExtension" completionHandler:^(SFSafariExtensionState *state, NSError *error) {
        if (error) {
            NSLog(@"Error fetching extension state: %@", error.localizedDescription);
            return;
        }

        setChecked(state.isEnabled);
    }];
}
