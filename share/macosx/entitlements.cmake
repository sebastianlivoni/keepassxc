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
	<key>com.apple.developer.authentication-services.autofill-credential-provider</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
 	<true/>
  <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
	<array>
	    <string>6HH7K3R53J.me.livoni.KeePassXC.AutoFillService.Listener</string>
	</array>
</dict>
</plist>
