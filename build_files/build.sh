#!/bin/bash

set -ouex pipefail

# Kopierer indholdet af system_files/ i repoet til / i imaget
cp -avf "/ctx/system_files"/. /

### Keel 0.1 (B3, trin 1): navnet.
# Systemets navn staar i /usr/lib/os-release. Startmenuen, tekst-login, KDE's opsaetningsguide,
# Velkomstcenter og installationsprogrammets tekster henter det derfra.
# ID og VERSION_ID roeres ikke i dette trin: dnf og ISO-byggeriet bruger dem.
KEEL_VERSION="0.1"
OSR="/usr/lib/os-release"
REPO_URL="https://github.com/jonashelbech-max/keel"

sed -i \
  -e 's|^NAME=.*|NAME="Keel"|' \
  -e "s|^PRETTY_NAME=.*|PRETTY_NAME=\"Keel ${KEEL_VERSION}\"|" \
  -e 's|^DEFAULT_HOSTNAME=.*|DEFAULT_HOSTNAME="keel"|' \
  -e "s|^HOME_URL=.*|HOME_URL=\"${REPO_URL}\"|" \
  -e "s|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL=\"${REPO_URL}\"|" \
  -e "s|^SUPPORT_URL=.*|SUPPORT_URL=\"${REPO_URL}/issues\"|" \
  -e "s|^BUG_REPORT_URL=.*|BUG_REPORT_URL=\"${REPO_URL}/issues\"|" \
  -e '/^REDHAT_BUGZILLA_PRODUCT/d' \
  -e '/^REDHAT_SUPPORT_PRODUCT/d' \
  "$OSR"

# Stop byggeriet, hvis filen ikke ser ud som forventet
grep -q '^NAME="Keel"$' "$OSR"
grep -q "^PRETTY_NAME=\"Keel ${KEEL_VERSION}\"\$" "$OSR"
grep -q '^ID=fedora$' "$OSR"
grep -q '^VERSION_ID=44$' "$OSR"
cat "$OSR"

# Fedoras side i KDE's Velkomstcenter ("Welcome to Fedora!"). Uden --no-autoremove
# kunne dnf tage selve Velkomstcenter med.
if rpm -q plasma-welcome-fedora > /dev/null 2>&1; then
    dnf -y remove --no-autoremove plasma-welcome-fedora
fi
rpm -q plasma-welcome

# Logoer, opstartsbillede, eget id og installationsprogrammet kommer i trin 2 til 5
# (se claude/keel-b3-plan.md i projektet).
