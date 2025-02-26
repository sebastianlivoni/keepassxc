<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.application-identifier</key>
	<string>${APPLE_TEAM_ID}.${APPLE_APP_IDENTIFIER}</string>
	<key>com.apple.security.application-groups</key>
 	<array>
 		<string>${APPLE_TEAM_ID}.${APPLE_APP_IDENTIFIER}</string>
 	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>${APPLE_TEAM_ID}.${APPLE_APP_IDENTIFIER}</string>
	</array>
	<key>com.apple.security.app-sandbox</key>
 	<true/>
 	<key>com.apple.security.device.usb</key>
 	<true/>
 	<key>com.apple.security.files.user-selected.read-write</key>
 	<true/>
 	<key>com.apple.security.network.client</key>
 	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.files.bookmarks.document-scope</key>
	<true/>
	<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
	<array>
		<string>/Library/Application Support/Google/Chrome/NativeMessagingHosts/</string>
		<string>/Library/Application Support/Chromium/NativeMessagingHosts/</string>
		<string>/Library/Application Support/Mozilla/NativeMessagingHosts/</string>
		<string>/Library/Application Support/Vivaldi/NativeMessagingHosts/</string>
		<string>/Library/Application Support/TorBrowser-Data/Browser/Mozilla/NativeMessagingHosts/</string>
		<string>/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/</string>
		<string>/Library/Application Support/Microsoft Edge/NativeMessagingHosts/</string>
	</array>
</dict>
</plist>
