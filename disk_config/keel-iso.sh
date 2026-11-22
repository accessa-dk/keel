#!/bin/bash
# Keel 0.1 (B3, trin 6): Keels navn, version og udseende i installations-ISO'en.
#
# bootc-image-builder tager installationsprogrammets navn og version fra NAME og VERSION_ID i
# imagets os-release ("Keel 44"). VERSION_ID skal blive 44, fordi bootc-image-builder slaar
# Fedora 44's pakker op efter den. Derfor rettes den faerdige ISO bagefter med Fedoras eget
# vaerktoej til formaalet, mkksiso (lorax):
#   1. GRUB-menuen paa ISO'en: "Keel 44" -> "Keel 0.1" (BIOS og EFI, efiboot.img bygges om).
#   2. Et opdateringsbillede (updates.img, inst.updates=) som Anacondas dracut-modul pakker ud
#      over installationsmiljoeet foer start:
#        /.buildstamp med Product=Keel og Version=0.1 (Anaconda 44 laeser navn og version herfra)
#        Keels stylesheet og maerke i stedet for Fedoras logo og blaa sidebjaelke.
#   3. MD5-kontrolsummen til "Test this media" laegges ind igen (mkksiso goer det selv).
#
# Koeres i en Fedora 44-container fra build-disk.yml:
#   keel-iso.sh <repo-mappe> <install.iso>
# ISO'en erstattes paa stedet.

set -euo pipefail

REPO="$1"
ISO="$2"

test -f "$ISO"
test -f "$REPO/system_files/usr/share/keel/release"

KEEL_VERSION="$(. "$REPO/system_files/usr/share/keel/release" && echo "$KEEL_VERSION")"
test -n "$KEEL_VERSION"
LOGO="$REPO/system_files/usr/share/plymouth/themes/spinner/watermark.png"
CSS="$REPO/disk_config/anaconda/keel.css"
test -s "$LOGO"
test -s "$CSS"

dnf -y -q install lorax xorriso isomd5sum squashfs-tools cpio gzip dosfstools mtools
rpm -q lorax xorriso isomd5sum

ISODIR="$(dirname "$ISO")"
WORK="$ISODIR/.keel-iso"
rm -rf "$WORK"
mkdir -p "$WORK/tmp" "$WORK/updates"
df -h "$ISODIR"

notice() {
    echo "::notice title=Keel ISO::$*"
}

### Hvad bootc-image-builder har lavet
xorriso -indev "$ISO" -pvd_info 2>&1 | grep -E '^Volume id|^Volume Set Id|^App Id' || true
osirrox -indev "$ISO" -extract /images/install.img "$WORK/install.img" \
    -extract /boot/grub2/grub.cfg "$WORK/grub-bios-foer.cfg" \
    -extract /EFI/BOOT/grub.cfg "$WORK/grub-efi-foer.cfg"
echo "--- GRUB (EFI) foer:"
cat "$WORK/grub-efi-foer.cfg"

# .buildstamp fra installationsmiljoeet (en flad squashfs)
unsquashfs -cat "$WORK/install.img" .buildstamp > "$WORK/buildstamp-foer"
echo "--- .buildstamp foer:"
cat "$WORK/buildstamp-foer"
PRODUCT="$(sed -n 's/^Product=//p' "$WORK/buildstamp-foer")"
VERSION="$(sed -n 's/^Version=//p' "$WORK/buildstamp-foer")"
test "$PRODUCT" = "Keel"
test -n "$VERSION"
FRA="${PRODUCT} ${VERSION}"
TIL="${PRODUCT} ${KEEL_VERSION}"
grep -qF "$FRA" "$WORK/grub-efi-foer.cfg"
grep -qF "$FRA" "$WORK/grub-bios-foer.cfg"

# Installationsmiljoeets os-release og Anacondas profiler: hvilket stylesheet bruges?
echo "--- os-release i installationsmiljoeet:"
unsquashfs -cat "$WORK/install.img" usr/lib/os-release || true
unsquashfs -d "$WORK/profiler" "$WORK/install.img" etc/anaconda/profile.d > /dev/null
grep -H '^custom_stylesheet' "$WORK"/profiler/etc/anaconda/profile.d/*.conf || true
mapfile -t STYLESHEETS < <(sed -n 's/^custom_stylesheet *= *//p' "$WORK"/profiler/etc/anaconda/profile.d/*.conf | sort -u)
if [ "${#STYLESHEETS[@]}" -eq 0 ]; then
    echo "Ingen custom_stylesheet i Anacondas profiler" >&2
    exit 1
fi
echo "--- pixmaps i installationsmiljoeet:"
unsquashfs -l "$WORK/install.img" usr/share/anaconda/pixmaps | sed -n '1,80p'
if unsquashfs -cat "$WORK/install.img" usr/share/anaconda/pixmaps/fedora.css > "$WORK/fedora.css" 2> /dev/null; then
    echo "--- Fedoras fedora.css (erstattes):"
    cat "$WORK/fedora.css"
fi

### Opdateringsbilledet
U="$WORK/updates"
sed -e "s|^Version=.*|Version=${KEEL_VERSION}|" "$WORK/buildstamp-foer" > "$U/.buildstamp"
grep -qx "Product=Keel" "$U/.buildstamp"
grep -qx "Version=${KEEL_VERSION}" "$U/.buildstamp"
install -D -m 0644 "$LOGO" "$U/usr/share/anaconda/pixmaps/keel-sidebar-logo.png"
for s in "${STYLESHEETS[@]}"; do
    case "$s" in
        /usr/share/anaconda/*) install -D -m 0644 "$CSS" "$U$s" ;;
        *) echo "Uventet stylesheet-sti: $s" >&2; exit 1 ;;
    esac
done
( cd "$U" && find . | LC_ALL=C sort | cpio --quiet -o -H newc --owner=0:0 ) | gzip -9 > "$WORK/updates.img"
echo "--- updates.img:"
gzip -dc "$WORK/updates.img" | cpio -it --quiet

### Ny ISO med mkksiso
NY="$ISODIR/install-keel.iso"
rm -f "$NY"
mkksiso --tmp "$WORK/tmp" --updates "$WORK/updates.img" -R "$FRA" "$TIL" "$ISO" "$NY"

### Kontrol af den nye ISO
osirrox -indev "$NY" -extract /boot/grub2/grub.cfg "$WORK/grub-bios-efter.cfg" \
    -extract /EFI/BOOT/grub.cfg "$WORK/grub-efi-efter.cfg" \
    -extract /updates.img "$WORK/updates-paa-iso.img"
echo "--- GRUB (EFI) efter:"
cat "$WORK/grub-efi-efter.cfg"
for cfg in "$WORK/grub-bios-efter.cfg" "$WORK/grub-efi-efter.cfg"; do
    grep -qF "$TIL" "$cfg"
    if grep -qF "$FRA" "$cfg"; then
        echo "$cfg indeholder stadig '$FRA'" >&2
        exit 1
    fi
    grep -q 'inst.updates=' "$cfg"
done
cmp "$WORK/updates.img" "$WORK/updates-paa-iso.img"
# EFI-partitionen (GPT-partition 2), som EFI-firmware starter fra, skal have den nye grub.cfg.
# xorriso skriver fx "GPT start and size :   2  9348612  20480" (blokke af 512 byte).
xorriso -indev "$NY" -report_el_torito plain -report_system_area plain 2>&1 | tee "$WORK/rapport.txt"
read -r EFI_START EFI_BLOKKE < <(awk '/^GPT start and size/ && $6 == "2" {print $7, $8; exit}' "$WORK/rapport.txt") || true
if [ -n "${EFI_START:-}" ] && [ -n "${EFI_BLOKKE:-}" ] \
    && dd if="$NY" of="$WORK/efi-part.img" bs=512 skip="$EFI_START" count="$EFI_BLOKKE" status=none \
    && mtype -i "$WORK/efi-part.img" ::/EFI/BOOT/grub.cfg > "$WORK/grub-efi-part.cfg"; then
    if ! grep -qF "$TIL" "$WORK/grub-efi-part.cfg" || grep -qF "$FRA" "$WORK/grub-efi-part.cfg"; then
        echo "EFI-partitionens grub.cfg er ikke rettet:" >&2
        cat "$WORK/grub-efi-part.cfg" >&2
        exit 1
    fi
    notice "EFI-partitionens grub.cfg siger '$TIL'"
else
    echo "::warning title=Keel ISO::EFI-partitionens grub.cfg kunne ikke laeses; kun ISO-traeets er kontrolleret"
fi
checkisomd5 --verbose "$NY" | tail -n 3

mv -f "$NY" "$ISO"
rm -rf "$WORK"
notice "GRUB og Anaconda: '$FRA' -> '$TIL'"
notice "Anaconda-stylesheet erstattet: ${STYLESHEETS[*]}"
ls -l "$ISODIR"
