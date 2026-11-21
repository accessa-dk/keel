#!/bin/bash
# Keel 0.1 (B3, trin 3): opstartsbilledet.
# Bygger initramfs om, saa Keels watermark.png (lagt ind af build.sh) kommer med i
# opstartsbilledet. Argumenterne er dem, basens initramfs er bygget med (aflaest med
# lsinitrd i byggeriet af trin 2). Sikkerhedsnet: byggeriet stopper, hvis listen over
# dracut-moduler eller filnavne afviger fra basens, hvis stoerrelsen afviger mere end
# 10 %, eller hvis watermark.png i initramfs ikke er byte for byte Keels.
set -ouex pipefail

KVER="$(rpm -q --queryformat='%{evr}.%{arch}' kernel-core)"
INITRAMFS="/usr/lib/modules/${KVER}/initramfs.img"
WATERMARK="usr/share/plymouth/themes/spinner/watermark.png"
WORK="$(mktemp -d)"

test "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | wc -l)" = "1"
test -s "$INITRAMFS"
test -s "/${WATERMARK}"
rpm -q dracut plymouth

filnavne() {
    lsinitrd "$1" | awk 'NF >= 9 && $1 ~ /^[-dlcbps][-rwxsStT]{9}$/ {print $9}' | sort
}
moduler() {
    lsinitrd -f usr/lib/dracut/modules.txt "$1"
}
moduler "$INITRAMFS" > "$WORK/moduler-foer.txt"
filnavne "$INITRAMFS" > "$WORK/filer-foer.txt"
FOER="$(stat -c %s "$INITRAMFS")"
RETTIGHEDER="$(stat -c %a "$INITRAMFS")"
SHA_FOER="$(sha256sum "$INITRAMFS" | cut -d' ' -f1)"
WM_FOER="$(lsinitrd -f "$WATERMARK" "$INITRAMFS" | sha256sum | cut -d' ' -f1)"
test -s "$WORK/moduler-foer.txt"
grep -qx ostree "$WORK/moduler-foer.txt"
grep -qx plymouth "$WORK/moduler-foer.txt"

# /root er et link til var/roothome, som foerst oprettes ved opstart (tmpfiles). Uden maalet
# springer dracut-install /root over ("ERROR: installing '/root'", set i det foerste
# proevebyggeri), og basens initramfs har baade root og var/roothome. Maalet laves derfor
# kun under dracut-koerslen og fjernes bagefter, saa /var i imaget er uaendret.
ROOTHOME_LAVET=""
if [ -L /root ] && [ ! -e /root ]; then
    ROOTHOME_LAVET="$(readlink -f /root)"
    mkdir -m 0700 "$ROOTHOME_LAVET"
fi

DRACUT_NO_XATTR=1 /usr/bin/dracut --no-hostonly --kver "$KVER" --reproducible -v --add ostree -f "$INITRAMFS"
chmod "$RETTIGHEDER" "$INITRAMFS"
if [ -n "$ROOTHOME_LAVET" ]; then
    rmdir "$ROOTHOME_LAVET"
fi

moduler "$INITRAMFS" > "$WORK/moduler-efter.txt"
filnavne "$INITRAMFS" > "$WORK/filer-efter.txt"
EFTER="$(stat -c %s "$INITRAMFS")"
diff -u "$WORK/moduler-foer.txt" "$WORK/moduler-efter.txt"
diff -u "$WORK/filer-foer.txt" "$WORK/filer-efter.txt"

echo "initramfs: foer ${FOER} bytes, efter ${EFTER} bytes"
test "$EFTER" -ge "$(( FOER * 90 / 100 ))"
test "$EFTER" -le "$(( FOER * 110 / 100 ))"

lsinitrd -f "$WATERMARK" "$INITRAMFS" | cmp - "/${WATERMARK}"
SHA_EFTER="$(sha256sum "$INITRAMFS" | cut -d' ' -f1)"
WM_EFTER="$(sha256sum "/${WATERMARK}" | cut -d' ' -f1)"

# Sammendrag. Linjerne med ::notice:: bliver ogsaa til noter paa koerslen i GitHub.
for linje in \
    "kerne ${KVER}, rettigheder ${RETTIGHEDER}" \
    "stoerrelse foer ${FOER} bytes, efter ${EFTER} bytes" \
    "dracut-moduler: $(wc -l < "$WORK/moduler-foer.txt") foer, $(wc -l < "$WORK/moduler-efter.txt") efter, ens" \
    "filnavne: $(wc -l < "$WORK/filer-foer.txt") foer, $(wc -l < "$WORK/filer-efter.txt") efter, ens" \
    "watermark.png i initramfs: foer sha256 ${WM_FOER}, efter sha256 ${WM_EFTER} (cmp mod Keels fil: ens)" \
    "initramfs.img sha256 foer ${SHA_FOER}" \
    "initramfs.img sha256 efter ${SHA_EFTER}"; do
    echo "::notice title=Keel initramfs::${linje}"
done
rm -rf "$WORK"
