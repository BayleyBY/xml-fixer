#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/XMLFixer"
PROJECT_PATH="$PROJECT_DIR/XMLFixer.xcodeproj"
APP_NAME="${APP_NAME:-RPB XML Toolkit}"
SCHEME="${SCHEME:-XMLFixer}"
CONFIGURATION="${CONFIGURATION:-Release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/builds/app-store}"
BUILD_LABEL="${BUILD_LABEL:-$(awk -F'"' '/static let buildVersion/{print $2; exit}' "$PROJECT_DIR/XMLFixer/App/XMLFixerApp.swift")}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$OUTPUT_DIR/$APP_NAME $BUILD_LABEL.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$OUTPUT_DIR/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$OUTPUT_DIR/ExportOptions-AppStore.plist}"
EXPORT_DESTINATION="${EXPORT_DESTINATION:-export}"
TEAM_ID="${TEAM_ID:-}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-NO}"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "Required tool '$1' is not installed."
}

write_export_options() {
  mkdir -p "$OUTPUT_DIR"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0">'
    echo '<dict>'
    echo '  <key>method</key>'
    echo '  <string>app-store-connect</string>'
    echo '  <key>destination</key>'
    echo "  <string>$EXPORT_DESTINATION</string>"
    echo '  <key>manageAppVersionAndBuildNumber</key>'
    echo '  <false/>'
    echo '  <key>stripSwiftSymbols</key>'
    echo '  <true/>'
    echo '  <key>uploadSymbols</key>'
    echo '  <true/>'
    if [[ -n "$TEAM_ID" ]]; then
      echo '  <key>teamID</key>'
      echo "  <string>$TEAM_ID</string>"
    fi
    echo '</dict>'
    echo '</plist>'
  } >"$EXPORT_OPTIONS_PLIST"
}

main() {
  require_tool xcodebuild
  [[ -d "$PROJECT_PATH" ]] || fail "Project not found at '$PROJECT_PATH'."

  mkdir -p "$OUTPUT_DIR"
  rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
  write_export_options

  echo "==> Archiving $APP_NAME for App Store Connect"
  archive_cmd=(
    xcodebuild
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "generic/platform=macOS"
    -archivePath "$ARCHIVE_PATH"
    archive
  )
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
    archive_cmd+=(-allowProvisioningUpdates)
  fi
  if [[ -n "$TEAM_ID" ]]; then
    archive_cmd+=(DEVELOPMENT_TEAM="$TEAM_ID")
  fi
  "${archive_cmd[@]}"

  echo "==> Exporting archive with app-store-connect method"
  export_cmd=(
    xcodebuild
    -exportArchive
    -archivePath "$ARCHIVE_PATH"
    -exportPath "$EXPORT_PATH"
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
  )
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
    export_cmd+=(-allowProvisioningUpdates)
  fi
  "${export_cmd[@]}"

  echo
  echo "Success. App Store archive/export:"
  echo "  Archive: $ARCHIVE_PATH"
  echo "  Export: $EXPORT_PATH"
  echo "  Options: $EXPORT_OPTIONS_PLIST"
}

main "$@"
