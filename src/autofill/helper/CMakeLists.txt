set(SOURCES
  AutoFillHelper.m
  main.m
)

add_executable(KeePassXCAutoFillHelper ${SOURCES})

set_target_properties(KeePassXCAutoFillHelper PROPERTIES
  MACOSX_BUNDLE_BUNDLE_NAME "KeePassXCAutoFillHelper"
)

configure_file(${CMAKE_SOURCE_DIR}/share/macosx/helper/helper.entitlements ${CMAKE_CURRENT_BINARY_DIR}/helper.entitlements)
configure_file(${CMAKE_SOURCE_DIR}/share/macosx/helper/Info.plist ${CMAKE_CURRENT_BINARY_DIR}/Info.plist)

target_link_libraries(KeePassXCAutoFillHelper "-framework Foundation" "-sectcreate __TEXT __info_plist ${CMAKE_CURRENT_BINARY_DIR}/Info.plist")

target_compile_definitions(KeePassXCAutoFillHelper PRIVATE
  HELPER_XPC_SERVICE_NAME="${HELPER_XPC_SERVICE_NAME}"
  APPLE_TEAM_ID="${APPLE_TEAM_ID}"
  APPLE_APP_IDENTIFIER="${APPLE_APP_IDENTIFIER}"
  AUTOFILL_EXTENSION_IDENTIFIER="${AUTOFILL_EXTENSION_IDENTIFIER}"
  HELPER_APP_IDENTIFIER="${HELPER_APP_IDENTIFIER}"
  DESIGNATED_REQUIREMENT="${DESIGNATED_REQUIREMENT}"
)

target_compile_options(KeePassXCAutoFillHelper PRIVATE "-fobjc-arc")

# Inside the app bundle (Contents/MacOS), next to KeePassXC; never loose in the package
install(TARGETS KeePassXCAutoFillHelper
    RUNTIME DESTINATION ${BIN_INSTALL_DIR}
)

set(HELPER_APP_DIR "${CMAKE_BINARY_DIR}/src/${BIN_INSTALL_DIR}")

add_custom_command(TARGET KeePassXCAutoFillHelper POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:KeePassXCAutoFillHelper>
        "${HELPER_APP_DIR}/KeePassXCAutoFillHelper"
)

configure_file(${CMAKE_SOURCE_DIR}/share/macosx/helper/LaunchAgent.plist ${CMAKE_CURRENT_BINARY_DIR}/LaunchAgent.plist)

add_custom_command(TARGET KeePassXCAutoFillHelper POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy
          ${CMAKE_CURRENT_BINARY_DIR}/LaunchAgent.plist
          $<TARGET_BUNDLE_CONTENT_DIR:${PROGNAME}>/Library/LaunchAgents/${HELPER_APP_IDENTIFIER}.plist
      COMMENT "Copying LaunchAgent.plist into app bundle"
  )
