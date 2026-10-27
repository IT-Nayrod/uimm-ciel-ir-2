#!/bin/bash
# ------------------------------------------------------------------
# BTS CIEL 2 IR, TP3 : Supervision SNMP, de v2c à v3
# Simulation des capteurs d'une ligne de production.
# Les valeurs sont exposées en SNMP par snmpd grâce à la directive extend.
#
# Utilisation :
#   capteurs temperature | pression | etat   valeur courante (appelé par snmpd)
#   capteurs --statut                         mode en cours et les trois valeurs
#   sudo capteurs --panne                     simule une dérive (surchauffe, surpression)
#   sudo capteurs --nominal                   retour au fonctionnement nominal
#
# Installation sur srv-cible :
#   sudo install -m 755 capteurs.sh /usr/local/bin/capteurs
#   sudo capteurs --nominal
# ------------------------------------------------------------------

DOSSIER=/var/lib/capteurs
FICHIER_MODE="$DOSSIER/mode"

mode=$(cat "$FICHIER_MODE" 2>/dev/null)
[ -z "$mode" ] && mode=nominal

# Nombre entier aléatoire entre $1 et $2 inclus
alea() {
    echo $(( $1 + RANDOM % ($2 - $1 + 1) ))
}

# Valeur d'un capteur selon le mode en cours
valeur() {
    case "$1:$mode" in
        temperature:panne) alea 88 96 ;;      # degrés Celsius, moteur en surchauffe
        temperature:*)     alea 62 74 ;;      # degrés Celsius, plage nominale
        pression:panne)    alea 7400 7800 ;;  # millibars, surpression du circuit
        pression:*)        alea 5900 6100 ;;  # millibars, plage nominale (environ 6 bar)
        etat:panne)        echo "DEGRADED" ;;
        etat:*)            echo "RUNNING" ;;
    esac
}

# Change le mode (réservé à root) et le trace dans le journal système
ecrire_mode() {
    if [ "$EUID" -ne 0 ]; then
        echo "Cette option demande les droits administrateur : sudo capteurs $2" >&2
        exit 1
    fi
    mkdir -p "$DOSSIER"
    chmod 755 "$DOSSIER"
    echo "$1" > "$FICHIER_MODE"
    chmod 644 "$FICHIER_MODE"
    logger -t capteurs "Ligne de production : passage en mode $1"
    echo "Ligne de production : mode $1"
}

case "$1" in
    temperature|pression|etat)
        valeur "$1"
        ;;
    --statut)
        echo "Mode : $mode"
        for c in temperature pression etat; do
            echo "  $c : $(valeur "$c")"
        done
        ;;
    --panne)
        ecrire_mode panne --panne
        ;;
    --nominal)
        ecrire_mode nominal --nominal
        ;;
    *)
        echo "Utilisation : capteurs temperature|pression|etat|--statut" >&2
        echo "              sudo capteurs --panne|--nominal" >&2
        exit 1
        ;;
esac
