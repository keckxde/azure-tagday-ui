; ==============================================================================
; NSIS Modern Installer Script for Azure TagDay UI
; ==============================================================================

!include "MUI2.nsh"
!include "FileFunc.nsh"

; --- Application Information ---
!define PRODUCT_NAME "Azure TagDay & DevOps UI"
!define PRODUCT_VERSION "0.1.0"
!define PRODUCT_PUBLISHER "keckx"
!define PRODUCT_EXE "azure-tagday-ui.exe"
!define UNINSTALL_NAME "Uninstall.exe"
!define REG_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "dist\AzureTagDayUI-Setup-${PRODUCT_VERSION}.exe"
InstallDir "$LOCALAPPDATA\Programs\AzureTagDayUI"
InstallDirRegKey HKCU "Software\${PRODUCT_NAME}" "InstallDir"
RequestExecutionLevel user

; --- Interface Settings ---
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${PRODUCT_NAME}"

; --- Installer Pages ---
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; --- Uninstaller Pages ---
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; --- Language ---
!insertmacro MUI_LANGUAGE "English"

; --- Installer Section ---
Section "MainSection" SEC01
    SetOutPath "$INSTDIR"
    SetOverwrite on

    ; Copy all files produced by PyInstaller
    File /r "dist\azure-tagday-ui\*.*"

    ; Create uninstaller
    WriteUninstaller "$INSTDIR\${UNINSTALL_NAME}"

    ; Start Menu Shortcuts
    CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
    CreateShortcut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0
    CreateShortcut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall ${PRODUCT_NAME}.lnk" "$INSTDIR\${UNINSTALL_NAME}" "" "$INSTDIR\${UNINSTALL_NAME}" 0

    ; Desktop Shortcut
    CreateShortcut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0

    ; Write Registry Keys for Windows Add/Remove Programs
    WriteRegStr HKCU "Software\${PRODUCT_NAME}" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "${REG_KEY}" "DisplayName" "${PRODUCT_NAME}"
    WriteRegStr HKCU "${REG_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
    WriteRegStr HKCU "${REG_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
    WriteRegStr HKCU "${REG_KEY}" "UninstallString" '"$INSTDIR\${UNINSTALL_NAME}"'
    WriteRegStr HKCU "${REG_KEY}" "QuietUninstallString" '"$INSTDIR\${UNINSTALL_NAME}" /S'
    WriteRegStr HKCU "${REG_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${REG_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT_EXE},0"
    WriteRegDWORD HKCU "${REG_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${REG_KEY}" "NoRepair" 1

    ; Estimate installed size
    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKCU "${REG_KEY}" "EstimatedSize" "$0"
SectionEnd

; --- Uninstaller Section ---
Section "Uninstall"
    ; Remove shortcuts
    Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
    Delete "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk"
    Delete "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall ${PRODUCT_NAME}.lnk"
    RMDir "$SMPROGRAMS\${PRODUCT_NAME}"

    ; Remove installed files
    RMDir /r "$INSTDIR"

    ; Remove registry keys
    DeleteRegKey HKCU "${REG_KEY}"
    DeleteRegKey HKCU "Software\${PRODUCT_NAME}"
SectionEnd
