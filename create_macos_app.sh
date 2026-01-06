#!/bin/bash
# Script para criar bundle GIMP.app para macOS

set -e

APP_NAME="GIMP-Metal"
APP_VERSION="3.2.0-RC2+git"
BUNDLE_DIR="$PWD/${APP_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🎨 Criando bundle ${APP_NAME}.app..."

# Limpar bundle anterior
rm -rf "$BUNDLE_DIR"

# Criar estrutura do bundle
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copiar executável
echo "📦 Copiando executável..."
cp /opt/homebrew/bin/gimp-3.2 "$MACOS_DIR/gimp"
chmod +x "$MACOS_DIR/gimp"

# Copiar bibliotecas necessárias
echo "📚 Copiando bibliotecas GIMP..."
mkdir -p "$RESOURCES_DIR/lib"
cp -r /opt/homebrew/lib/gimp "$RESOURCES_DIR/lib/" 2>/dev/null || true

# Copiar recursos
echo "🎨 Copiando recursos..."
mkdir -p "$RESOURCES_DIR/share"
cp -r /opt/homebrew/share/gimp "$RESOURCES_DIR/share/" 2>/dev/null || true

# Criar ícone (usar logo do GIMP)
if [ -f "/opt/homebrew/share/icons/hicolor/256x256/apps/gimp.png" ]; then
    echo "🖼️  Convertendo ícone..."
    sips -s format icns "/opt/homebrew/share/icons/hicolor/256x256/apps/gimp.png" \
         --out "$RESOURCES_DIR/gimp.icns" 2>/dev/null || true
fi

# Criar Info.plist
echo "📄 Criando Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>gimp</string>
    <key>CFBundleIconFile</key>
    <string>gimp.icns</string>
    <key>CFBundleIdentifier</key>
    <string>org.gimp.GIMP-Metal</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.graphics-design</string>
</dict>
</plist>
PLIST

# Criar script de lançamento
echo "🚀 Criando launcher..."
cat > "$MACOS_DIR/gimp-launcher.sh" << 'LAUNCHER'
#!/bin/bash
BUNDLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export GIMP3_DATADIR="$BUNDLE_DIR/Resources/share/gimp/3.0"
export GIMP3_LOCALEDIR="$BUNDLE_DIR/Resources/share/locale"
export GIMP3_PLUGINDIR="$BUNDLE_DIR/Resources/lib/gimp/3.0"
export GIMP3_SYSCONFDIR="$BUNDLE_DIR/Resources/etc/gimp/3.0"
export PATH="/opt/homebrew/bin:$PATH"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib:$DYLD_LIBRARY_PATH"

cd "$HOME"
exec "$BUNDLE_DIR/MacOS/gimp" "$@"
LAUNCHER

chmod +x "$MACOS_DIR/gimp-launcher.sh"

# Renomear executável e usar launcher
mv "$MACOS_DIR/gimp" "$MACOS_DIR/gimp-bin"
mv "$MACOS_DIR/gimp-launcher.sh" "$MACOS_DIR/gimp"

echo ""
echo "✅ Bundle criado com sucesso!"
echo "📍 Localização: $BUNDLE_DIR"
echo ""
echo "Para testar:"
echo "  open \"$BUNDLE_DIR\""
echo ""
echo "Para criar DMG:"
echo "  hdiutil create -volname \"${APP_NAME}\" -srcfolder \"$BUNDLE_DIR\" -ov -format UDZO \"${APP_NAME}-${APP_VERSION}.dmg\""
