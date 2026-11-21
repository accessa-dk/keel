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
# med "rsvg-convert -w 200 -h 60". Opstartsbilledet laeser det fra initramfs, som bygges om
# i initramfs.sh (trin 3, eget RUN-trin i Containerfile).
for f in \
    /usr/share/icons/hicolor/scalable/apps/keel-logo.svg \
    /usr/share/icons/hicolor/scalable/apps/start-here.svg \
    /usr/share/icons/hicolor/scalable/places/start-here.svg \
    /usr/share/plymouth/themes/spinner/watermark.png; do
    test -s "$f"
done
# "Om dette system" (kcm-about-distrorc): Fedoras kde-settings peger paa
# /usr/share/pixmaps/system-logo-white.png, som i generic-logos er en hotdog. Keels egen
# fil i system_files/etc/xdg peger paa keel-logo.svg (trin 3).
grep -qx 'LogoPath=/usr/share/icons/hicolor/scalable/apps/keel-logo.svg' /etc/xdg/kcm-about-distrorc
cat /etc/xdg/kcm-about-distrorc
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
grep -q '^VERSION_ID=44$' "$OSR"

# Fedoras side i KDE's Velkomstcenter ("Welcome to Fedora!"). Uden --no-autoremove
# kunne dnf tage selve Velkomstcenter med.
if rpm -q plasma-welcome-fedora > /dev/null 2>&1; then
    dnf -y remove --no-autoremove plasma-welcome-fedora
fi
rpm -q plasma-welcome

### Keel 0.1 (B3, trin 4): eget id.
# ID=keel, saa programmer ikke tror, de koerer paa Fedora. ID_LIKE="fedora" fortaeller de
# programmer, der kender Fedora, at Keel ligner det: bootc-image-builder vaelger installer-
# opsaetning efter ID og derefter ID_LIKE, og systemd-sysext matcher mod begge.
# VERSION_ID=44 roeres ikke: dnf laeser releasever fra pakken fedora-release-common
# (system-release(releasever)), ikke fra os-release.
grep -qx 'ID=fedora' "$OSR"
if grep -q '^ID_LIKE=' "$OSR"; then
    echo "os-release har allerede ID_LIKE" >&2
    exit 1
fi
sed -i 's|^ID=fedora$|ID=keel\nID_LIKE="fedora"|' "$OSR"
grep -qx 'ID=keel' "$OSR"
grep -qx 'ID_LIKE="fedora"' "$OSR"
grep -qx 'VERSION_ID=44' "$OSR"
test "$(grep -c '^ID=' "$OSR")" = "1"
# /etc/os-release er et link til den rettede fil (det er den, dracut og de fleste programmer laeser)
test "$(readlink -f /etc/os-release)" = "/usr/lib/os-release"
cat "$OSR"

# dnf skal stadig finde Fedora 44's pakker efter ID-skiftet. Byggeriet stopper, hvis ikke.
rpm -q --whatprovides 'system-release(releasever)'
dnf --dump-variables repolist --enabled | tee /tmp/keel-dnf.txt
grep -qx 'releasever = 44' /tmp/keel-dnf.txt
dnf -q --refresh repoquery --available --latest-limit=1 bash | tee /tmp/keel-repoquery.txt
grep -q '\.fc44\.' /tmp/keel-repoquery.txt

# grub2-switch-to-blscfg finder EFI-mappen som EFI/${ID}. Shim og grub ligger fortsat i
# EFI/fedora, saa mappen saettes fast, som Aurora og Bluefin goer.
find /usr/lib/efi /usr/lib/bootupd /usr/lib/ostree-boot -name 'shim*.efi' 2>/dev/null | tee /tmp/keel-shim.txt
grep -q '/EFI/fedora/shimx64.efi$' /tmp/keel-shim.txt
if [ -f /usr/sbin/grub2-switch-to-blscfg ]; then
    grep -n '^EFIDIR=' /usr/sbin/grub2-switch-to-blscfg
    sed -i 's|^EFIDIR=.*|EFIDIR="fedora"|' /usr/sbin/grub2-switch-to-blscfg
    grep -qx 'EFIDIR="fedora"' /usr/sbin/grub2-switch-to-blscfg
else
    echo "::notice title=Keel id::grub2-switch-to-blscfg findes ikke i imaget"
fi

# dnf copr vaelger Copr-chroot efter ID (keel-44 findes ikke). Samme rettelse som Aurora.
mkdir -p /usr/share/dnf/plugins
test ! -e /usr/share/dnf/plugins/copr.vendor.conf
printf '[main]\ndistribution = fedora\n' > /usr/share/dnf/plugins/copr.vendor.conf

# toolbox vaelger sit standard-image efter ID. Med et ukendt ID falder toolbox 0.3 tilbage paa
# fedora-toolbox:42. Keel peger det paa Fedora med basens version.
if rpm -q toolbox; then
    test ! -e /etc/containers/toolbox.conf
    TOOLBOX_RELEASE="$(. "$OSR" && echo "$VERSION_ID")"
    printf '[general]\ndistro = "fedora"\nrelease = "%s"\n' "$TOOLBOX_RELEASE" > /etc/containers/toolbox.conf
    cat /etc/containers/toolbox.conf
fi

# "Om dette system" viser "Keel 0.1" og ingen undertitel. Version= og Variant= staar i Keels
# kcm-about-distrorc (kinfocenter bruger dem foran VERSION_ID og VARIANT fra os-release).
grep -qx "Version=${KEEL_VERSION}" /etc/xdg/kcm-about-distrorc
grep -qx 'Variant=' /etc/xdg/kcm-about-distrorc
if command -v kreadconfig6 > /dev/null 2>&1; then
    test "$(kreadconfig6 --file /etc/xdg/kcm-about-distrorc --group General --key Version --default STANDARD)" = "${KEEL_VERSION}"
    test "$(kreadconfig6 --file /etc/xdg/kcm-about-distrorc --group General --key Variant --default STANDARD)" = ""
else
    echo "::notice title=Keel id::kreadconfig6 findes ikke, Version/Variant ikke laest med KConfig"
fi

for linje in \
    "os-release: $(grep -E '^(ID|ID_LIKE|VERSION_ID)=' "$OSR" | tr '\n' ' ')" \
    "dnf: $(grep -E '^releasever = ' /tmp/keel-dnf.txt), repoquery bash: $(tr '\n' ' ' < /tmp/keel-repoquery.txt)" \
    "shim: $(tr '\n' ' ' < /tmp/keel-shim.txt)"; do
    echo "::notice title=Keel id::${linje}"
done
rm -f /tmp/keel-dnf.txt /tmp/keel-repoquery.txt /tmp/keel-shim.txt

# Installationsprogrammet kommer i trin 5 (se claude/keel-b3-plan.md i projektet).

# dnf (trin 2) efterlader filer, som bootc container lint advarer om. Ryd dem vaek.
rm -rf /run/dnf /var/lib/dnf/repos
