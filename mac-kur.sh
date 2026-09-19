#!/usr/bin/env bash
# Voltara — Mac kurulum ve iOS derleme hazırlığı (tek komut).
# Kullanım:  bash <(curl -fsSL https://cansapaz.github.io/Voltara-Privacy/mac-kur.sh)
#            (Voltara deposu özel olduğu için betik herkese açık Voltara-Privacy sayfasından sunulur;
#             kaynak dosya Voltara/scripts/mac-kur.sh — değişince oraya da kopyalanır)
#            veya klonlanmış depoda: bash scripts/mac-kur.sh
# Yaptıkları: Xcode kontrolü → Node (nodejs.org .pkg; Homebrew kullanılmaz) → ~/voltara klon/güncelle
#             → ios dalı → Xcode'un dokunduğu dosyaları stash → pull → npm ci → build → cap sync ios → Xcode aç
set -euo pipefail

REPO="https://github.com/CanSapaz/Voltara.git"
DIR="$HOME/voltara"
NODE_MAJOR=22

say() { printf '\n\033[1;32m▶ %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

# 1) Xcode
say "Xcode kontrol ediliyor"
if ! xcode-select -p >/dev/null 2>&1; then
  die "Xcode bulunamadı. App Store'dan Xcode'u kurup bir kez açın (lisansı kabul edin), sonra bu betiği yeniden çalıştırın."
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  say "Komut satırı araçları Xcode'a yönlendiriliyor (şifre istenebilir)"
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept || true
fi
xcodebuild -version | head -1

# 2) Node (Homebrew DEĞİL: Intel Mac'lerde artık desteklenmiyor; resmi .pkg her mimaride çalışır)
say "Node.js kontrol ediliyor"
need_node=1
if command -v node >/dev/null 2>&1; then
  v=$(node -v | sed 's/v//' | cut -d. -f1)
  [ "$v" -ge "$NODE_MAJOR" ] && need_node=0
fi
if [ "$need_node" = 1 ]; then
  arch=$(uname -m); [ "$arch" = "arm64" ] || arch="x64"
  ver=$(curl -fsSL https://nodejs.org/dist/index.json | python3 -c "import sys,json;print([x['version'] for x in json.load(sys.stdin) if x['lts'] and x['version'].startswith('v$NODE_MAJOR.')][0])")
  pkg="/tmp/node-$ver.pkg"
  say "Node $ver ($arch) indiriliyor"
  curl -fL "https://nodejs.org/dist/$ver/node-$ver-$arch.pkg" -o "$pkg"
  sudo installer -pkg "$pkg" -target /
  export PATH="/usr/local/bin:$PATH"
fi
node -v && npm -v

# 3) GitHub girişi (depo özel). GitHub CLI: resmi .pkg (Homebrew yok), sonra tarayıcıdan giriş.
say "GitHub girişi kontrol ediliyor"
if ! command -v gh >/dev/null 2>&1; then
  ghv=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | python3 -c "import sys,json;print(json.load(sys.stdin)['tag_name'].lstrip('v'))")
  say "GitHub CLI $ghv indiriliyor"
  curl -fL "https://github.com/cli/cli/releases/download/v$ghv/gh_${ghv}_macOS_universal.pkg" -o /tmp/gh.pkg
  sudo installer -pkg /tmp/gh.pkg -target /
  export PATH="/usr/local/bin:$PATH"
fi
if ! gh auth status >/dev/null 2>&1; then
  say "GitHub'a giriş: tarayıcı açılacak, CanSapaz hesabıyla onaylayın"
  gh auth login --hostname github.com --git-protocol https --web
fi
gh auth setup-git >/dev/null 2>&1 || true

# 4) Depo
if [ -d "$DIR/.git" ]; then
  say "Depo güncelleniyor: $DIR"
  cd "$DIR"
  git fetch origin
  # "ios" hem dal hem klasör adı: switch belirsizlik hatası vermez, checkout verir
  git switch ios 2>/dev/null || git switch -c ios origin/ios
  # Xcode'un otomatik dokunduğu dosyalar pull'u engellemesin
  git stash push -q -- ios/App/App.xcodeproj/project.pbxproj package-lock.json 2>/dev/null || true
  git pull --ff-only origin ios
  git stash pop -q 2>/dev/null || true
else
  say "Depo klonlanıyor: $DIR"
  gh repo clone CanSapaz/Voltara "$DIR" -- --branch ios
  cd "$DIR"
fi

# 5) Bağımlılıklar ve web derlemesi
say "npm bağımlılıkları"
npm ci || npm install
if [ ! -f .env ]; then
  cp .env.example .env
  printf '\n\033[1;33m! .env oluşturuldu (.env.example kopyası). OCM anahtarını ve iOS AdMob kimliklerini doldurun.\033[0m\n'
fi
say "Web derlemesi"
npm run build

# 6) iOS senkron ve Xcode
say "Capacitor iOS senkronu (SPM; Xcode paketleri ilk açılışta indirir)"
npx cap sync ios
say "Xcode açılıyor — ilk kez: Signing & Capabilities → Team seçin (Personal Team DEĞİL), sonra ▶︎"
npx cap open ios
