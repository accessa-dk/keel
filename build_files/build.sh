#!/bin/bash

set -ouex pipefail

### Keel 0.1 (B3, trin 2): logoerne.
# Fedoras logoer ud, den neutrale pakke ind. Skal ske FOER system_files kopieres ind,
# ellers overskriver pakken Keels egne filer (start-here og watermark.png).
dnf -y swap fedora-logos generic-logos
rpm -q generic-logos
if rpm -q fedora-logos > /dev/null 2>&1; then
    echo "fedora-logos er stadig installeret" >&2
    exit 1
fi

# Kopierer indholdet af system_files/ i repoet til / i imaget
cp -avf "/ctx/system_files"/. /

# Keels maerke (pladsholder): ikonet keel-logo, programmenuens start-here og
# opstartsbilledets watermark.png. watermark.png er lavet af branding/watermark.svg
# med "rsvg-convert -w 200 -h 60" og kommer foerst med i opstartsbilledet, naar initramfs bygges om (trin 3).
for f in \
    /usr/share/icons/hicolor/scalable/apps/keel-logo.svg \
    /usr/share/icons/hicolor/scalable/apps/start-here.svg \
    /usr/share/icons/hicolor/scalable/places/start-here.svg \
    /usr/share/plymouth/themes/spinner/watermark.png; do
    test -s "$f"
done
# GTK-programmer laeser ikoner gennem en cache. Den skal kende de nye filer.
if command -v gtk-update-icon-cache > /dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor
fi

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
  -e 's|^LOGO=.*|LOGO=keel-logo|' \
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
grep -q '^LOGO=keel-logo$' "$OSR"
grep -q '^ID=fedora$' "$OSR"
grep -q '^VERSION_ID=44$' "$OSR"
cat "$OSR"

# Fedoras side i KDE's Velkomstcenter ("Welcome to Fedora!"). Uden --no-autoremove
# kunne dnf tage selve Velkomstcenter med.
if rpm -q plasma-welcome-fedora > /dev/null 2>&1; then
    dnf -y remove --no-autoremove plasma-welcome-fedora
fi
rpm -q plasma-welcome

# Opstartsbillede, eget id og installationsprogrammet kommer i trin 3 til 5
# (se claude/keel-b3-plan.md i projektet).

### Midlertidigt: oplysninger til trin 3 (opstartsbilledet) og konsoltastaturet.
# Kun udskrift til byggeloggen, aendrer intet i imaget. Fjernes i trin 3.
(
    set +e
    echo "=== KEEL-INFO: kerner"; ls /usr/lib/modules
    echo "=== KEEL-INFO: pakker"; rpm -q kernel-core dracut plymouth plymouth-theme-spinner systemd kbd kbd-misc kbd-legacy kmscon ostree bootc
    echo "=== KEEL-INFO: plymouth-tema"; plymouth-set-default-theme; cat /etc/plymouth/plymouthd.conf /usr/share/plymouth/plymouthd.defaults 2>&1
    echo "=== KEEL-INFO: dracut-opsaetning"; ls -la /usr/lib/dracut/dracut.conf.d /etc/dracut.conf.d 2>&1; cat /usr/lib/dracut/dracut.conf.d/*.conf /etc/dracut.conf.d/*.conf 2>&1
    echo "=== KEEL-INFO: initramfs"; ls -la /usr/lib/modules/*/initramfs.img
    for i in /usr/lib/modules/*/initramfs.img; do
        lsinitrd "$i" | head -40
        lsinitrd "$i" | grep -E "watermark|vconsole|keymaps/.*(dk|us)\.map|plymouth/themes/[a-z]+/[a-z]+\.plymouth"
        lsinitrd -f etc/vconsole.conf "$i"
    done
    echo "=== KEEL-INFO: tastatur"; cat /etc/vconsole.conf 2>&1; ls /usr/lib/kbd/keymaps/xkb/dk* /usr/lib/kbd/keymaps/legacy/i386/qwerty/dk* 2>&1
    ls -la /usr/lib/systemd/system/autovt@.service /usr/lib/systemd/system/getty.target.wants 2>&1
    cat /usr/lib/udev/rules.d/90-vconsole.rules 2>&1
    echo "=== KEEL-INFO: kernelinje"; ls -la /usr/lib/bootc/kargs.d 2>&1; cat /usr/lib/bootc/kargs.d/* 2>&1
    echo "=== KEEL-INFO: slut"
) || true
