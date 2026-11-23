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
# VERSION_ID=44 roeres ikke. dnf laeser releasever fra rpm-databasen (den pakke, der giver
# system-release), ikke fra os-release.
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
# Hvilken pakke dnf tager releasever fra (libdnf5 vars.cpp: foerste af system-release(releasever),
# system-release, ...). Kun til loggen; selve kontrollen er releasever-linjen nedenfor.
rpm -q --whatprovides 'system-release(releasever)' system-release || true
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

# dnf copr vaelger Copr-chroot efter ID (keel-44 findes ikke). Aurora har filen
# copr.vendor.conf med distribution = fedora. Basen har allerede en (set i proevebyggeri 2);
# den beholdes, hvis den siger fedora, ellers stopper byggeriet.
COPR_VENDOR=/usr/share/dnf/plugins/copr.vendor.conf
if [ -e "$COPR_VENDOR" ]; then
    rpm -qf "$COPR_VENDOR" || true
    cat "$COPR_VENDOR"
else
    mkdir -p /usr/share/dnf/plugins
    printf '[main]\ndistribution = fedora\n' > "$COPR_VENDOR"
fi
grep -Eqx 'distribution *= *fedora' "$COPR_VENDOR"

# toolbox vaelger sit standard-image efter ID. Med et ukendt ID falder toolbox 0.3 tilbage paa
# fedora-toolbox:42. Keel peger det paa Fedora med basens version.
if rpm -q toolbox; then
    # Basen har toolbox-pakkens skabelon, hvor alle valg er kommenteret ud (set i proevebyggeri 3).
    # De to linjer "## distro" og "## release" slaas til; resten af skabelonen bliver staaende.
    TBC=/etc/containers/toolbox.conf
    TOOLBOX_RELEASE="$(. "$OSR" && echo "$VERSION_ID")"
    rpm -qf "$TBC"
    if grep -Eq '^[[:space:]]*(distro|release|image)[[:space:]]*=' "$TBC"; then
        echo "toolbox.conf har allerede aktive valg" >&2
        exit 1
    fi
    test "$(grep -c '^## distro = ' "$TBC")" = "1"
    test "$(grep -c '^## release = ' "$TBC")" = "1"
    sed -i \
        -e 's|^## distro = .*|distro = "fedora"|' \
        -e "s|^## release = .*|release = \"${TOOLBOX_RELEASE}\"|" \
        "$TBC"
    grep -qx 'distro = "fedora"' "$TBC"
    grep -qx "release = \"${TOOLBOX_RELEASE}\"" "$TBC"
    grep -E '^\[general\]|^(distro|release|image) =' "$TBC"
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

### Keel 0.1 (B3, trin 6): VERSION i os-release.
# Basen skriver VERSION="44.<dato>.0 (Kinoite)". Keel viser "0.1". VERSION er kun til visning;
# programmer, der skal kende udgivelsen, laeser VERSION_ID, som bliver 44: bootc-image-builder
# slaar Fedora 44's pakker op efter ID_LIKE og VERSION_ID, og toolbox (trin 4) bruger VERSION_ID.
# Basens byggenummer staar fortsat i OSTREE_VERSION og i imagets etiketter.
grep -Eq '^VERSION="?44\.' "$OSR"
sed -i "s|^VERSION=.*|VERSION=\"${KEEL_VERSION}\"|" "$OSR"
grep -qx "VERSION=\"${KEEL_VERSION}\"" "$OSR"
test "$(grep -c '^VERSION=' "$OSR")" = "1"
grep -qx 'VERSION_ID=44' "$OSR"
if grep -E '^(NAME|VERSION|PRETTY_NAME)=' "$OSR" | grep -qi kinoite; then
    echo "os-release viser stadig Kinoite" >&2
    exit 1
fi
echo "::notice title=Keel version::$(grep -E '^(VERSION|VERSION_ID|OSTREE_VERSION)=' "$OSR" | tr '\n' ' ')"

### Keel 0.1 (krav 4, trin 3): Keel fortaeller ikke lokalnettet, hvem den er.
# Maalt 22.11.2026 (knowledge/claude/keel-anonymt-maaling i projektet): ved login sendte KDE Connect
# sit faste enheds-id og navnet "keel" ud (UDP 1716 broadcast og mDNS), og avahi annoncerede
# keel.local med maskinens adresser.

# KDE Connect bliver installeret, men dets netvaerk er fra, til brugeren selv slaar det til.
# Det er ikke nok at fjerne autostart: KDE Connect-ikonet i panelets bakke starter kdeconnectd
# over D-Bus. Derfor startes kdeconnectd alle steder gennem /usr/libexec/keel-kdeconnectd, som
# foerste gang pr. bruger skriver disabled_providers_v2=lan, bluetooth, loopback i
# ~/.config/kdeconnect/config. Uden backends sender kdeconnectd intet (LanLinkProvider::onStart
# vender om, naar den er slaaet fra). Brugeren slaar det til under Indstillinger > Backends.
KDC_WRAPPER=/usr/libexec/keel-kdeconnectd
test -x "$KDC_WRAPPER"
test -x /usr/bin/kdeconnectd
rpm -q kdeconnectd
grep -qx 'exec /usr/bin/kdeconnectd "$@"' "$KDC_WRAPPER"
KDC_FILES="$(grep -lx 'Exec=/usr/bin/kdeconnectd' \
    /etc/xdg/autostart/*.desktop /usr/share/applications/*.desktop /usr/share/dbus-1/services/*.service \
    2>/dev/null || true)"
printf '%s\n' "$KDC_FILES"
# Kilden (daemon/CMakeLists.txt) installerer samme Exec tre steder: autostart, programmer og D-Bus.
# Autostart og D-Bus skal vaere der; programmenuens kopi er NoDisplay og kan mangle.
test "$(printf '%s\n' "$KDC_FILES" | grep -c .)" -ge 2
printf '%s\n' "$KDC_FILES" | grep -qx /etc/xdg/autostart/org.kde.kdeconnect.daemon.desktop
printf '%s\n' "$KDC_FILES" | grep -qx /usr/share/dbus-1/services/org.kde.kdeconnect.service
for f in $KDC_FILES; do
    rpm -qf "$f"
    sed -i "s|^Exec=/usr/bin/kdeconnectd\$|Exec=${KDC_WRAPPER}|" "$f"
    grep -qx "Exec=${KDC_WRAPPER}" "$f"
done
if grep -rlx 'Exec=/usr/bin/kdeconnectd' /etc/xdg/autostart /usr/share/applications /usr/share/dbus-1 /usr/lib/systemd/user 2>/dev/null; then
    echo "kdeconnectd startes stadig uden om ${KDC_WRAPPER}" >&2
    exit 1
fi
# Proev omslaget i en tom hjemmemappe (kdeconnectd selv startes ikke).
KDC_TEST="$(mktemp -d)"
sed 's|^exec /usr/bin/kdeconnectd .*|exit 0|' "$KDC_WRAPPER" > "${KDC_TEST}/w.sh"
HOME="$KDC_TEST" XDG_CONFIG_HOME= sh "${KDC_TEST}/w.sh"
grep -qx '\[General\]' "${KDC_TEST}/.config/kdeconnect/config"
grep -qx 'disabled_providers_v2=lan, bluetooth, loopback' "${KDC_TEST}/.config/kdeconnect/config"
test -e "${KDC_TEST}/.config/kdeconnect/.keel-netvaerk-fra"
rm -rf "$KDC_TEST"

# avahi annoncerer ikke maskinen (keel.local, adresser, omvendte navne) og tager ikke imod
# annonceringer fra programmer. Opslag af andre maskiners .local-navne (nss-mdns) og soegning
# efter tjenester virker fortsat; det er netop det, disable-publishing er lavet til.
# systemd-resolved har mDNS slaaet fra og LLMNR kun til opslag (uaendret).
AVC=/etc/avahi/avahi-daemon.conf
rpm -qf "$AVC"
test "$(grep -Ec '^#?disable-publishing=' "$AVC")" = "1"
sed -i -E 's|^#?disable-publishing=.*|disable-publishing=yes|' "$AVC"
test "$(awk '/^\[/{s=$0} /^disable-publishing=yes$/{print s}' "$AVC")" = "[publish]"
grep -E '^\[|^[a-z0-9-]+=' "$AVC"

echo "::notice title=Keel anonymt::kdeconnectd via ${KDC_WRAPPER} i $(printf '%s ' $KDC_FILES); avahi disable-publishing=yes"

# dnf (trin 2) efterlader filer, som bootc container lint advarer om. Ryd dem vaek.
rm -rf /run/dnf /var/lib/dnf/repos
