set(SOURCES
  AutoFillXPCRendezvous.m
  main.m
)

add_executable(KeePassXCAutoFillXPCRendezvous ${SOURCES})

set_target_properties(KeePassXCAutoFillXPCRendezvous PROPERTIES
  MACOSX_BUNDLE_BUNDLE_NAME "KeePassXCAutoFillXPCRendezvous"
)

configure_file(${CMAKE_SOURCE_DIR}/share/macosx/rendezvous/rendezvous.entitlements ${CMAKE_CURRENT_BINARY_DIR}/rendezvous.entitlements)
configure_file(${CMAKE_SOURCE_DIR}/share/macosx/rendezvous/Info.plist ${CMAKE_CURRENT_BINARY_DIR}/Info.plist)

target_link_libraries(KeePassXCAutoFillXPCRendezvous "-framework Foundation" "-sectcreate __TEXT __info_plist ${CMAKE_CURRENT_BINARY_DIR}/Info.plist")

target_compile_definitions(KeePassXCAutoFillXPCRendezvous PRIVATE
  RENDEZVOUS_XPC_SERVICE_NAME="${RENDEZVOUS_XPC_SERVICE_NAME}"
  APPLE_TEAM_ID="${APPLE_TEAM_ID}"
  APPLE_APP_IDENTIFIER="${APPLE_APP_IDENTIFIER}"
  AUTOFILL_EXTENSION_IDENTIFIER="${AUTOFILL_EXTENSION_IDENTIFIER}"
  RENDEZVOUS_APP_IDENTIFIER="${RENDEZVOUS_APP_IDENTIFIER}"
  DESIGNATED_REQUIREMENT="${DESIGNATED_REQUIREMENT}"
)

target_compile_options(KeePassXCAutoFillXPCRendezvous PRIVATE "-fobjc-arc")

install(TARGETS KeePassXCAutoFillXPCRendezvous
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

set(RENDEZVOUS_APP_DIR "${CMAKE_BINARY_DIR}/src/${BIN_INSTALL_DIR}")

add_custom_command(TARGET KeePassXCAutoFillXPCRendezvous POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:KeePassXCAutoFillXPCRendezvous>
        "${RENDEZVOUS_APP_DIR}/KeePassXCAutoFillXPCRendezvous"
)

configure_file(${CMAKE_SOURCE_DIR}/share/macosx/rendezvous/LaunchAgent.plist ${CMAKE_CURRENT_BINARY_DIR}/LaunchAgent.plist)

add_custom_command(TARGET KeePassXCAutoFillXPCRendezvous POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy
          ${CMAKE_CURRENT_BINARY_DIR}/LaunchAgent.plist
          $<TARGET_BUNDLE_CONTENT_DIR:${PROGNAME}>/Library/LaunchAgents/${RENDEZVOUS_APP_IDENTIFIER}.plist
      COMMENT "Copying LaunchAgent.plist into app bundle"
  )
