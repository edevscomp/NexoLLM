!include "MUI2.nsh"

!ifndef VERSION
  !define VERSION "0.9.1"
!endif

Name "NexoLLM ${VERSION}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\NexoLLM"
InstallDirRegKey HKCU "Software\EdevS\NexoLLM" "InstallDir"
RequestExecutionLevel user
Unicode True
SetCompressor /SOLID lzma

!ifdef ICON_FILE
  !define MUI_ICON "${ICON_FILE}"
  !define MUI_UNICON "${ICON_FILE}"
!endif

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\NexoLLM.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch NexoLLM"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Italian"
!insertmacro MUI_LANGUAGE "Spanish"
!insertmacro MUI_LANGUAGE "French"
!insertmacro MUI_LANGUAGE "German"
!insertmacro MUI_LANGUAGE "Portuguese"

Section "NexoLLM Desktop" SecMain
  SetOutPath "$INSTDIR"
  File /oname=NexoLLM.exe "${BIN_PATH}"
  !ifdef ICON_FILE
    File /oname=NexoLLM.ico "${ICON_FILE}"
  !endif

  WriteRegStr HKCU "Software\EdevS\NexoLLM" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\NexoLLM"
  CreateShortcut "$SMPROGRAMS\NexoLLM\NexoLLM.lnk" "$INSTDIR\NexoLLM.exe"
  CreateShortcut "$DESKTOP\NexoLLM.lnk" "$INSTDIR\NexoLLM.exe"

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NexoLLM" "DisplayName" "NexoLLM"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NexoLLM" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NexoLLM" "Publisher" "EdevS"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NexoLLM" "DisplayIcon" "$INSTDIR\NexoLLM.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NexoLLM" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NexoLLM" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NexoLLM" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\NexoLLM\NexoLLM.lnk"
  RMDir "$SMPROGRAMS\NexoLLM"
  Delete "$DESKTOP\NexoLLM.lnk"
  Delete "$INSTDIR\NexoLLM.ico"
  Delete "$INSTDIR\NexoLLM.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NexoLLM"
  DeleteRegKey HKCU "Software\EdevS\NexoLLM"
SectionEnd
