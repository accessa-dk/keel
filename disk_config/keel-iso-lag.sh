#!/bin/bash
# Keel 0.1 (fund 1 fra trin 5): den foerste opdatering efter en installation fra ISO'en skal kun
# hente de lag, der er aendret, ikke hele systemet igen.
#
# bootc-image-builder kopierer imaget fra sit lokale lager (containers-storage) til OCI-mappen
# /container paa ISO'en (osbuild-trinnet org.osbuild.skopeo). Lagene pakkes da paa ny og faar
# andre digests end lagene i registret. Anaconda installerer fra den kopi, og ostree gemmer lagene
# under kopiens digests. Den foerste `bootc upgrade` mod registret genkender derfor ingen lag og
# henter alle 128 (3,6 GB).
#
# Dette script erstatter /container paa ISO'en med en kopi, hentet fra registret med
# `skopeo copy --preserve-digests`, saa manifest og lag-digests er de samme som i registret.
# Indholdet er det samme image (samme config-digest kontrolleres), og ISO'en installerer stadig
# uden net.
#
#   keel-iso-lag.sh skift <install.iso> <arbejdsmappe>    maal, hent registrets kopi, erstat
#   keel-iso-lag.sh kontrol <install.iso> <arbejdsmappe>  kontroller den faerdige ISO
#
# Begge skriver linjer, der starter med "KEEL-LAG", saa resultatet kan findes i byggeloggen.

set -euo pipefail
# Ogsaa i $(...), saa en fejl i en funktion stopper scriptet
shopt -s inherit_errexit

MODE="$1"
ISO="$2"
WORK="$3"
L="$WORK/lag"
mkdir -p "$L"

notice() {
    echo "::notice title=Keel ISO lag::$*"
}
log() {
    echo "KEEL-LAG $*"
}
mb() {
    awk -v b="$1" 'BEGIN { printf "%.1f MB", b / 1000000 }'
}

# Udtraek en fil fra ISO'en til en lokal sti
fra_iso() {
    osirrox -indev "$1" -extract "$2" "$3" > /dev/null 2>&1
    test -s "$3"
}

# Manifestet i en OCI-mappe paa ISO'en: index.json skal pege paa praecis et manifest.
# Skriver index.json og manifestet til $2.index.json og $2.manifest.json og returnerer digesten.
iso_manifest() {
    local iso="$1" ud="$2" antal digest
    fra_iso "$iso" "$OCI_STI/index.json" "$ud.index.json"
    antal="$(jq '.manifests | length' "$ud.index.json")"
    if [ "$antal" != "1" ]; then
        echo "$OCI_STI/index.json har $antal manifester, ventede 1" >&2
        jq . "$ud.index.json" >&2
        return 1
    fi
    digest="$(jq -r '.manifests[0].digest' "$ud.index.json")"
    fra_iso "$iso" "$OCI_STI/blobs/sha256/${digest#sha256:}" "$ud.manifest.json"
    # Manifestets egen sha256 skal passe med digesten i index.json
    test "sha256:$(sha256sum "$ud.manifest.json" | cut -d' ' -f1)" = "$digest"
    echo "$digest"
}

beskriv() {
    # $1 = navn, $2 = manifest-fil, $3 = manifest-digest
    log "$1: manifest $3"
    log "$1: config $(jq -r '.config.digest' "$2")"
    log "$1: $(jq '.layers | length' "$2") lag, i alt $(mb "$(jq '[.layers[].size] | add' "$2")")"
    log "$1: lagtyper $(jq -r '[.layers[].mediaType] | group_by(.) | map("\(.[0]) x\(length)") | join(", ")' "$2")"
    log "$1: foerste lag $(jq -r '.layers[0].digest' "$2"), sidste lag $(jq -r '.layers[-1].digest' "$2")"
}

# Lag i $2, som ikke findes i $1: antal og bytes (det, en opdatering fra $1 til $2 skal hente)
nye_lag() {
    jq -r '.layers[].digest' "$1" | sort -u > "$L/a.txt"
    jq -r '.layers[] | "\(.digest) \(.size)"' "$2" | sort -u > "$L/b.txt"
    awk 'NR == FNR { har[$1] = 1; next } !($1 in har) { n++; s += $2 } END { printf "%d %d\n", n, s }' "$L/a.txt" "$L/b.txt"
}

### Hvor ligger imaget paa ISO'en, og hvor opdaterer det installerede system fra?
# Kickstarten, bootc-image-builder genererer, siger begge dele:
#   ostreecontainer --url=/run/install/repo/container --transport=oci
#   bootc switch --mutate-in-place --transport registry ghcr.io/<ejer>/<navn>:latest
find_kickstart() {
    local iso="$1" f
    : > "$L/kickstarts.txt"
    while IFS= read -r f; do
        f="${f#\'}"; f="${f%\'}"
        fra_iso "$iso" "$f" "$L/ks-$(basename "$f")" && echo "$L/ks-$(basename "$f")" >> "$L/kickstarts.txt"
    done < <(xorriso -indev "$iso" -find / -name '*.ks' 2> /dev/null)
    test -s "$L/kickstarts.txt"
    OCI_URL="$(xargs cat < "$L/kickstarts.txt" | sed -nE 's/^ostreecontainer .*--url=([^ ]+).*/\1/p' | head -n 1)"
    OCI_TRANSPORT="$(xargs cat < "$L/kickstarts.txt" | sed -nE 's/^ostreecontainer .*--transport=([^ ]+).*/\1/p' | head -n 1)"
    TARGET="$(xargs cat < "$L/kickstarts.txt" | sed -nE 's/.*bootc switch .*--transport registry ([^ ]+).*/\1/p' | head -n 1)"
    log "kickstart: ostreecontainer --url=$OCI_URL --transport=$OCI_TRANSPORT; bootc switch til $TARGET"
    test "$OCI_TRANSPORT" = "oci"
    case "$OCI_URL" in
        /run/install/repo/*) OCI_STI="/${OCI_URL#/run/install/repo/}" ;;
        *) echo "Uventet ostreecontainer --url: $OCI_URL" >&2; return 1 ;;
    esac
    test -n "$TARGET"
    REPO_UDEN_TAG="${TARGET%:*}"
    test "$REPO_UDEN_TAG" != "$TARGET"
}

registret() {
    skopeo inspect --raw --retry-times 3 "docker://$TARGET" > "$L/registret.manifest.json"
    # Et OCI-manifest behoever ikke have feltet mediaType (registrets har det ikke), saa et enkelt
    # manifest kendes paa config og layers, og et indeks (flere arkitekturer) paa manifests.
    if ! jq -e 'has("config") and has("layers") and (has("manifests") | not)' "$L/registret.manifest.json" > /dev/null; then
        echo "Registret gav ikke et enkelt manifest for $TARGET:" >&2
        head -c 2000 "$L/registret.manifest.json" >&2
        return 1
    fi
    REG_DIGEST="$(skopeo manifest-digest "$L/registret.manifest.json")"
}

case "$MODE" in
skift)
    START=$SECONDS
    find_kickstart "$ISO"

    ### Maaling: bootc-image-builders kopi mod registret
    BIB_DIGEST="$(iso_manifest "$ISO" "$L/bib")"
    beskriv "ISO (bootc-image-builder)" "$L/bib.manifest.json" "$BIB_DIGEST"
    log "ISO (bootc-image-builder): ref.name '$(jq -r '.manifests[0].annotations["org.opencontainers.image.ref.name"] // ""' "$L/bib.index.json")', $(xorriso -indev "$ISO" -find "$OCI_STI" -type f 2> /dev/null | wc -l) filer under $OCI_STI"
    registret
    beskriv "registret ($TARGET)" "$L/registret.manifest.json" "$REG_DIGEST"
    read -r N_NYE B_NYE < <(nye_lag "$L/bib.manifest.json" "$L/registret.manifest.json")
    N_REG="$(jq '.layers | length' "$L/registret.manifest.json")"
    FAELLES_FOER=$(( N_REG - N_NYE ))
    log "FOER: faelles lag-digests ISO/registret: $FAELLES_FOER af $N_REG. Foerste opdatering ville hente $N_NYE lag, $(mb "$B_NYE")"
    # Lag for lag (registrets digest, kopiens digest, stoerrelser), samme raekkefoelge
    jq -r --slurpfile b "$L/bib.manifest.json" '
        [.layers, $b[0].layers] | transpose | to_entries[]
        | "KEEL-LAG lag \(.key + 1): registret \(.value[0].digest) \(.value[0].size) | ISO \(.value[1].digest // "-") \(.value[1].size // "-") \(.value[1].mediaType // "-")"' \
        "$L/registret.manifest.json"
    notice "Foer: ISO'ens kopi deler $FAELLES_FOER af $N_REG lag-digests med registret (manifest ${BIB_DIGEST:7:12} mod ${REG_DIGEST:7:12}); foerste opdatering ville hente $(mb "$B_NYE")"

    ### Samme image? Config-digesten aendres ikke af en ny pakning af lagene.
    BIB_CONFIG="$(jq -r '.config.digest' "$L/bib.manifest.json")"
    REG_CONFIG="$(jq -r '.config.digest' "$L/registret.manifest.json")"
    if [ "$BIB_CONFIG" != "$REG_CONFIG" ]; then
        echo "ISO'ens image (config $BIB_CONFIG) er ikke det, $TARGET peger paa nu (config $REG_CONFIG)." >&2
        echo "latest er formentlig flyttet under byggeriet. Koer byggeriet igen." >&2
        exit 1
    fi
    log "samme image: config $BIB_CONFIG i begge"

    ### Registrets kopi, byte for byte (manifest og lag uaendrede)
    NY_OCI="$WORK/container"
    rm -rf "$NY_OCI"
    REFNAME="$(jq -r '.manifests[0].annotations["org.opencontainers.image.ref.name"] // ""' "$L/bib.index.json")"
    skopeo copy --retry-times 3 --preserve-digests \
        "docker://$REPO_UDEN_TAG@$REG_DIGEST" "oci:$NY_OCI${REFNAME:+:$REFNAME}"
    test "$(jq '.manifests | length' "$NY_OCI/index.json")" = "1"
    test "$(jq -r '.manifests[0].digest' "$NY_OCI/index.json")" = "$REG_DIGEST"
    cmp "$NY_OCI/blobs/sha256/${REG_DIGEST#sha256:}" "$L/registret.manifest.json"
    skopeo inspect "oci:$NY_OCI${REFNAME:+:$REFNAME}" > /dev/null
    log "registrets kopi: $(find "$NY_OCI" -type f | wc -l) filer, $(du -sb "$NY_OCI" | cut -f1) byte"

    ### Erstat /container paa ISO'en. Opstartsopsaetningen (El Torito, GPT, EFI) genskabes som i mkksiso.
    FOER_BYTES="$(stat -c %s "$ISO")"
    MID="$(dirname "$ISO")/install-lag.iso"
    rm -f "$MID"
    if ! xorriso -indev "$ISO" -outdev "$MID" -boot_image any replay \
        -rm_r "$OCI_STI" -- \
        -map "$NY_OCI" "$OCI_STI" > "$L/xorriso-skift.log" 2>&1; then
        cat "$L/xorriso-skift.log" >&2
        exit 1
    fi
    grep -vE '^xorriso : UPDATE : +Writing:' "$L/xorriso-skift.log" || true
    test -s "$MID"
    mv -f "$MID" "$ISO"
    rm -rf "$NY_OCI"
    log "ISO: $FOER_BYTES byte foer, $(stat -c %s "$ISO") byte efter; trinnet tog $(( SECONDS - START )) s"
    ;;

kontrol)
    ### Den faerdige ISO: /container skal vaere registrets manifest med alle lag
    find_kickstart "$ISO"
    ISO_DIGEST="$(iso_manifest "$ISO" "$L/iso")"
    beskriv "ISO (faerdig)" "$L/iso.manifest.json" "$ISO_DIGEST"
    xorriso -indev "$ISO" -find "$OCI_STI/blobs/sha256" -type f 2> /dev/null \
        | sed -E "s|^'||; s|'$||; s|.*/|sha256:|" | sort -u > "$L/iso-blobs.txt"
    jq -r '.config.digest, .layers[].digest' "$L/iso.manifest.json" | sort -u > "$L/skal-findes.txt"
    MANGLER="$(comm -13 "$L/iso-blobs.txt" "$L/skal-findes.txt" | wc -l)"
    if [ "$MANGLER" -ne 0 ]; then
        echo "$MANGLER blobs fra manifestet mangler paa ISO'en" >&2
        exit 1
    fi
    registret
    read -r N_NYE B_NYE < <(nye_lag "$L/iso.manifest.json" "$L/registret.manifest.json")
    N_REG="$(jq '.layers | length' "$L/registret.manifest.json")"
    FAELLES=$(( N_REG - N_NYE ))
    log "EFTER: faelles lag-digests ISO/registret: $FAELLES af $N_REG. Foerste opdatering mod $TARGET nu ($REG_DIGEST): $N_NYE lag, $(mb "$B_NYE")"
    if [ "$ISO_DIGEST" = "$REG_DIGEST" ]; then
        log "EFTER: ISO'ens manifest er det samme som registrets ($REG_DIGEST)"
    fi
    if [ "$FAELLES" -ne "$N_REG" ] && [ "$ISO_DIGEST" = "$REG_DIGEST" ]; then
        echo "Samme manifest, men ikke alle lag faelles: kan ikke passe" >&2
        exit 1
    fi
    if [ "$ISO_DIGEST" != "$REG_DIGEST" ] && [ "$FAELLES" -eq 0 ]; then
        echo "Ingen faelles lag med registret efter skiftet" >&2
        exit 1
    fi
    notice "Efter: ISO'ens kopi = manifest ${ISO_DIGEST:7:12}, deler $FAELLES af $N_REG lag-digests med registret; foerste opdatering mod latest nu: $N_NYE lag, $(mb "$B_NYE")"
    ;;

*)
    echo "Ukendt tilstand: $MODE" >&2
    exit 2
    ;;
esac
