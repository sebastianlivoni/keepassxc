set(SOURCES
  AutofillXPCRendezvous.m
  main.m
)

add_executable(KeePassXCAutoFillXPCRendezvous ${SOURCES})

set_target_properties(KeePassXCAutoFillXPCRendezvous PROPERTIES
  MACOSX_BUNDLE_BUNDLE_NAME "KeePassXCAutoFillXPCRendezvous"
)

target_link_libraries(KeePassXCAutoFillXPCRendezvous "-framework Foundation" "-sectcreate __TEXT __info_plist ${CMAKE_CURRENT_SOURCE_DIR}/Info.plist")

#target_compile_options(KeePassXCAutoFillXPCRendezvous PRIVATE "-fobjc-arc")

install(TARGETS KeePassXCAutoFillXPCRendezvous
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

set(RENDEZVOUS_APP_DIR "${CMAKE_BINARY_DIR}/src/${BIN_INSTALL_DIR}")

add_custom_command(TARGET KeePassXCAutoFillXPCRendezvous POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:KeePassXCAutoFillXPCRendezvous>
        "${RENDEZVOUS_APP_DIR}/KeePassXCAutoFillXPCRendezvous"
)

add_custom_command(TARGET KeePassXCAutoFillXPCRendezvous POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy
          ${CMAKE_CURRENT_SOURCE_DIR}/LaunchAgent.plist
          $<TARGET_BUNDLE_CONTENT_DIR:${PROGNAME}>/Library/LaunchAgents/me.livoni.KeePassXC.AutoFillService.plist
      COMMENT "Copying LaunchAgent.plist into app bundle"
  )
