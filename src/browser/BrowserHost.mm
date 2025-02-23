/*
 *  Copyright (C) 2020 KeePassXC Team <team@keepassxc.org>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "BrowserHost.h"
#include "BrowserShared.h"

#include <QJsonDocument>
#include <QLocalServer>
#include <QLocalSocket>

#import <Foundation/Foundation.h>
#import <SafariServices/SafariServices.h>

#ifdef Q_OS_WIN
#include <fcntl.h>
#undef NOMINMAX
#define NOMINMAX
#include <windows.h>
#else
#include <sys/socket.h>
#endif

BrowserHost::BrowserHost(QObject* parent)
    : QObject(parent)
{
    m_localServer = new QLocalServer(this);
    m_localServer->setSocketOptions(QLocalServer::UserAccessOption);
    connect(m_localServer.data(), SIGNAL(newConnection()), this, SLOT(proxyConnected()));
}

BrowserHost::~BrowserHost()
{
    stop();
}

void BrowserHost::start()
{
    if (!m_localServer->isListening()) {
        m_localServer->listen(BrowserShared::localServerPath());
    }
}

void BrowserHost::stop()
{
    m_socketList.clear();
    m_localServer->close();
}

void BrowserHost::proxyConnected()
{
    auto socket = m_localServer->nextPendingConnection();
    if (socket) {
        m_socketList.append(socket);
        connect(socket, SIGNAL(readyRead()), this, SLOT(readProxyMessage()));
        connect(socket, SIGNAL(disconnected()), this, SLOT(proxyDisconnected()));
    }
}

void BrowserHost::readProxyMessage()
{
    QLocalSocket* socket = qobject_cast<QLocalSocket*>(QObject::sender());
    if (!socket || socket->bytesAvailable() <= 0) {
        return;
    }

    socket->setReadBufferSize(BrowserShared::NATIVEMSG_MAX_LENGTH);
    int socketDesc = socket->socketDescriptor();
    if (socketDesc) {
        int max = BrowserShared::NATIVEMSG_MAX_LENGTH;
        setsockopt(socketDesc, SOL_SOCKET, SO_SNDBUF, reinterpret_cast<char*>(&max), sizeof(max));
    }

    QJsonParseError error;
    auto json = QJsonDocument::fromJson(socket->readAll(), &error);
    if (json.isNull()) {
        qWarning() << "Failed to read proxy message: " << error.errorString();
        return;
    }

    emit clientMessageReceived(socket, json.object());
}

void BrowserHost::broadcastClientMessage(const QJsonObject& json)
{
    QString reply(QJsonDocument(json).toJson(QJsonDocument::Compact));
    bool containsSafariWebExtensionSocket = false;

    // Send message to all non-Safari sockets
    for (const auto socket : m_socketList) {
        if (isSafariWebExtension(socket)) {
            containsSafariWebExtensionSocket = true;
            continue; // Skip Safari web extension sockets because we are using SFSafariApplication instead
        }

        sendClientData(socket, reply);
    }

    if (containsSafariWebExtensionSocket) {
        NSString* jsonString = reply.toNSString();
        NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];

        NSError *error = nil;
        NSDictionary *message = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

        if (error) {
            NSLog(@"Error converting NSString to NSDictionary: %@", error.localizedDescription);
            return;
        }

        [SFSafariApplication dispatchMessageWithName:@"proxy_message"
                        toExtensionWithIdentifier:@"me.livoni.KeePassXC.SafariWebExtension"
                                            userInfo:message
                                            completionHandler:nil];
    }
}

bool BrowserHost::isSafariWebExtension(QLocalSocket* socket)
{
    int sockfd = socket->socketDescriptor();
    pid_t pid = -1;
    socklen_t len = sizeof(pid);
    if (getsockopt(sockfd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) == -1) {
        NSLog(@"Failed to get peer PID, error: %s", strerror(errno));
        return false;
    }

    SecCodeRef parentCode = NULL;
    CFDictionaryRef attributes = (__bridge CFDictionaryRef)@{(NSString *)kSecGuestAttributePid: @(pid)};
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, attributes, 0, &parentCode);

    if (status != errSecSuccess || parentCode == NULL) {
        NSLog(@"Failed to get SecCode for parent process (PID %d): %d", pid, static_cast<int>(status));
        return false;
    }

    NSString *requirementString = @"anchor apple generic and identifier \"me.livoni.KeePassXC.SafariWebExtension\"";

    SecRequirementRef requirement = NULL;
    status = SecRequirementCreateWithString((__bridge CFStringRef)requirementString, SecCSFlags(), &requirement);

    if (status != errSecSuccess || requirement == NULL) {
        NSLog(@"Failed to create requirement: %d", static_cast<int>(status));
        if (parentCode != NULL) {
            CFRelease(parentCode);
        }
        return false;
    }

    status = SecCodeCheckValidity(parentCode, SecCSFlags(), requirement);

    if (status == errSecSuccess) {
        NSLog(@"Caller is verified successfully.");
    } else {
        NSLog(@"Caller verification failed: %d", static_cast<int>(status));
    }

    if (parentCode != NULL) {
        CFRelease(parentCode);
    }
    if (requirement != NULL) {
        CFRelease(requirement);
    }

    return (status == errSecSuccess);
}

void BrowserHost::sendClientMessage(QLocalSocket* socket, const QJsonObject& json)
{
    QString reply(QJsonDocument(json).toJson(QJsonDocument::Compact));
    sendClientData(socket, reply);
}

void BrowserHost::sendClientData(QLocalSocket* socket, const QString& data)
{
    if (socket && socket->isValid() && socket->state() == QLocalSocket::ConnectedState) {
        QByteArray arr = data.toUtf8();
        socket->write(arr.constData(), arr.length());
        socket->flush();
    }
}

void BrowserHost::proxyDisconnected()
{
    auto socket = qobject_cast<QLocalSocket*>(QObject::sender());
    m_socketList.removeOne(socket);
}
