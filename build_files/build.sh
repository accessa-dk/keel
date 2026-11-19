#!/bin/bash

set -ouex pipefail

# Kopierer indholdet af system_files/ i repoet til / i imaget
cp -avf "/ctx/system_files"/. /

# Keel 0.0: basen er uaendret. Ingen pakker tilfoejes eller fjernes endnu.
# Keel-laget (navn, udseende, Keel Scan-profil) kommer i B3.
