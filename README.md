# Keel

Tidlig prototype (fase B1, "Keel 0.0"). Ikke klar til brug.

Keel er et styresystem-image bygget som et bootc-containerimage oven på Fedora
(Universal Blues `kinoite-main`, KDE Plasma). Repoet er oprettet fra
[ublue-os/image-template](https://github.com/ublue-os/image-template).

## Sådan bygges det

- `Containerfile` og `build_files/build.sh` er opskriften. I Keel 0.0 er basen uændret.
- Workflowet **Build container image** bygger imaget ved hvert push til `main` og lægger det på
  `ghcr.io/jonashelbech-max/keel:latest`.
- Workflowet **Build disk images** startes manuelt og laver en installer-ISO og et qcow2-diskimage
  af det seneste image. De ligger som artifacts på kørslen.

## Afvigelser fra skabelonen

- Base: `ghcr.io/ublue-os/kinoite-main:latest` i stedet for Bazzite.
- `disk_config/iso.toml` findes nu (skabelonens workflow pegede på en fil, der ikke fandtes).
- Signering med cosign er taget ud i B1 og tilføjes, før imaget skal bruges af andre.
- `/usr/share/keel/release` markerer, at et system er bygget fra dette repo.

## Advarsel

Installer-ISO'en overskriver den disk, den installeres på. Brug den kun i en virtuel maskine
eller på en test-pc.
