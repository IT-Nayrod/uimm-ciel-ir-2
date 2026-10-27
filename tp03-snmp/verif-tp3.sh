#!/bin/bash
# ------------------------------------------------------------------
# BTS CIEL 2 IR, TP3 : Supervision SNMP, de v2c à v3
# Script de vérification, à lancer sur srv-cible.
#
#   sudo ./verif-tp3.sh             verdict global
#   sudo ./verif-tp3.sh --details   détail de chaque contrôle et quoi corriger
#
# Les passphrases SNMPv3 demandées servent uniquement à tester une requête
# locale. Elles ne sont ni affichées ni enregistrées.
# ------------------------------------------------------------------

IP_SRV="192.168.100.10"
IP_MANAGER="192.168.100.20"
USER_V3="supervision"
CONF="/etc/snmp/snmpd.conf"
CONF_D="/etc/snmp/snmpd.conf.d"
PERSIST="/var/lib/snmp/snmpd.conf"
OID_SYSNAME=".1.3.6.1.2.1.1.5.0"
# nsExtendOutput1Line."temperature" en notation numérique
OID_TEMP=".1.3.6.1.4.1.8072.1.3.2.3.1.1.11.116.101.109.112.101.114.97.116.117.114.101"

DETAILS=0
case "$1" in
    -d|--details) DETAILS=1 ;;
    "") ;;
    *) echo "Utilisation : sudo $0 [--details]"; exit 2 ;;
esac

if [ "$EUID" -ne 0 ]; then
    echo "Lance ce script avec sudo : sudo $0 $*"
    exit 2
fi

VERT=$'\e[32m'; ROUGE=$'\e[31m'; GRAS=$'\e[1m'; RAZ=$'\e[0m'
total=0
reussis=0
lignes=()

verifier() {
    # $1 libellé, $2 conseil en cas d'échec, $3 fonction de test
    total=$((total + 1))
    if "$3" >/dev/null 2>&1; then
        reussis=$((reussis + 1))
        lignes+=("${VERT}[OK]${RAZ}       $1")
    else
        lignes+=("${ROUGE}[MANQUANT]${RAZ} $1"$'\n'"           -> $2")
    fi
}

# Toutes les lignes actives de la configuration de l'agent
config_active() {
    cat "$CONF" "$CONF_D"/*.conf /usr/share/snmp/snmpd.conf 2>/dev/null | grep -Ev '^\s*(#|$)'
}

# Requête SNMPv3 authPriv locale
requete_v3() {
    snmpget -v3 -l authPriv -u "$USER_V3" -a SHA-256 -A "$AUTH" -x AES -X "$PRIV" \
        -t 2 -r 1 -Oqv "$1" "$2"
}

# ---------- Tests ----------
t_paquets()        { dpkg -s snmpd && dpkg -s snmp; }
t_sauvegarde()     { [ -f /etc/snmp/snmpd.conf.bak ]; }
t_actif()          { systemctl is-active --quiet snmpd; }
t_active_boot()    { systemctl is-enabled --quiet snmpd; }
t_ecoute_interne() { ss -H -lun 'sport = :161' | awk '{print $4}' | grep -qx "${IP_SRV}:161"; }
t_pas_partout()    { ! ss -H -lun 'sport = :161' | awk '{print $4}' | grep -Eq '^(0\.0\.0\.0|\*|\[::\]):161$'; }
t_infos_systeme() {
    config_active | grep -Eiq '^\s*syslocation\s+\S' &&
    ! config_active | grep -Eiq '^\s*syslocation\s+Sitting on the Dock' &&
    config_active | grep -Eiq '^\s*syscontact\s+\S' &&
    ! config_active | grep -Eiq '^\s*syscontact\s+Me <me@example\.org>'
}
t_ufw_actif()      { LC_ALL=C ufw status | grep -q "Status: active"; }
t_ufw_manager()    { LC_ALL=C ufw status | grep -Eq "^161(/udp)?\s+ALLOW(\s+IN)?\s+${IP_MANAGER//./\\.}(\s|$)"; }
t_ufw_pas_tous()   { ! LC_ALL=C ufw status | grep -Eq "^161(/udp)?(\s+\(v6\))?\s+ALLOW(\s+IN)?\s+Anywhere"; }
t_aucune_communaute() { ! config_active | grep -Eiq '^\s*(rocommunity6?|rwcommunity6?|com2sec6?)\s'; }
t_v2c_refusee() {
    local ip c
    for ip in 127.0.0.1 "$IP_SRV"; do
        for c in public ciel-lab; do
            snmpget -v2c -c "$c" -t 1 -r 0 "$ip" "$OID_SYSNAME" && return 1
        done
    done
    return 0
}
t_usm_cree() {
    grep -Eq "^usmUser .*(\"${USER_V3}\"|0x7375706572766973696f6e)" "$PERSIST"
}
t_pas_de_clair() {
    ! grep -Eq '^\s*createUser' "$PERSIST" && ! config_active | grep -Eiq '^\s*createUser'
}
t_rouser_priv()    { config_active | grep -Eiq "^\s*rouser\s+${USER_V3}\s+(priv|authpriv)(\s|$)"; }
t_refus_sans_auth() {
    ! snmpget -v3 -l noAuthNoPriv -u "$USER_V3" -t 1 -r 0 127.0.0.1 "$OID_SYSNAME"
}
t_v3_ok()          { [ -n "$AUTH" ] && [ -n "$(requete_v3 127.0.0.1 "$OID_SYSNAME")" ]; }
t_capteurs_installe() { [ -x /usr/local/bin/capteurs ]; }
t_extend() {
    local c
    for c in temperature pression etat; do
        config_active | grep -Eq "^\s*extend\s+${c}\s+/usr/local/bin/capteurs\s+${c}\s*$" || return 1
    done
}
t_capteurs_v3()    { [ -n "$AUTH" ] && requete_v3 127.0.0.1 "$OID_TEMP" | tr -d '"' | grep -Eqx '[0-9]+'; }
t_nominal()        { [ "$(cat /var/lib/capteurs/mode 2>/dev/null)" = "nominal" ]; }

# ---------- Passphrases ----------
echo "${GRAS}Vérification du TP3 : Supervision SNMP, de v2c à v3${RAZ}"
echo
echo "Saisis les passphrases de l'utilisateur SNMPv3 « ${USER_V3} »"
echo "(elles servent seulement à tester une requête, rien n'est affiché ni enregistré)."
read -r -s -p "  Passphrase d'authentification : " AUTH < /dev/tty; echo
read -r -s -p "  Passphrase de chiffrement     : " PRIV < /dev/tty; echo
echo

# ---------- Contrôles ----------
verifier "Paquets snmpd et snmp installés" \
    "sudo apt install -y snmpd snmp" t_paquets
verifier "Sauvegarde de la configuration d'origine (snmpd.conf.bak)" \
    "sudo cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.bak (Partie 1)" t_sauvegarde
verifier "Service snmpd démarré" \
    "sudo systemctl start snmpd, puis lis l'erreur avec : journalctl -u snmpd -n 20" t_actif
verifier "Service snmpd activé au démarrage" \
    "sudo systemctl enable snmpd" t_active_boot
verifier "Agent à l'écoute sur ${IP_SRV}:161 (réseau interne)" \
    "ligne agentaddress de $CONF : 127.0.0.1,${IP_SRV} (Partie 1)" t_ecoute_interne
verifier "Agent pas à l'écoute sur toutes les interfaces" \
    "agentaddress ne doit pas contenir udp:161 seul ni 0.0.0.0 : l'agent serait joignable par la carte NAT" t_pas_partout
verifier "sysLocation et sysContact personnalisés" \
    "remplace les valeurs par défaut de sysLocation et sysContact dans $CONF (Partie 1)" t_infos_systeme
verifier "Pare-feu UFW actif" \
    "sudo ufw enable (après avoir vérifié que le port SSH est autorisé)" t_ufw_actif
verifier "Port 161/udp autorisé depuis le manager ${IP_MANAGER}" \
    "sudo ufw allow from ${IP_MANAGER} to any port 161 proto udp (Partie 1)" t_ufw_manager
verifier "Port 161/udp pas ouvert à tout le monde" \
    "supprime la règle trop large : sudo ufw status numbered, puis sudo ufw delete <numéro>" t_ufw_pas_tous
verifier "Aucune communauté SNMPv1/v2c active dans la configuration" \
    "commente toutes les lignes rocommunity / rocommunity6 de $CONF (Partie 7)" t_aucune_communaute
verifier "Requêtes SNMPv2c refusées en pratique" \
    "une communauté répond encore : vérifie $CONF puis sudo systemctl restart snmpd" t_v2c_refusee
verifier "Utilisateur SNMPv3 « ${USER_V3} » créé" \
    "snmpd arrêté, ajoute la ligne createUser dans $PERSIST, puis redémarre (Partie 6)" t_usm_cree
verifier "Aucun mot de passe SNMPv3 resté en clair (createUser converti)" \
    "la ligne createUser doit disparaître : redémarre snmpd, et n'écris jamais createUser dans $CONF" t_pas_de_clair
verifier "Utilisateur limité au niveau authPriv (rouser ${USER_V3} priv)" \
    "ajoute la ligne : rouser ${USER_V3} priv dans $CONF (Partie 6)" t_rouser_priv
verifier "Requête sans authentification refusée" \
    "le niveau minimal de rouser doit être priv, pas noauth ni auth" t_refus_sans_auth
verifier "Requête SNMPv3 authPriv (SHA-256 / AES) acceptée" \
    "vérifie l'utilisateur, les deux passphrases et les algorithmes SHA-256 et AES de la ligne createUser" t_v3_ok
verifier "Script capteurs installé dans /usr/local/bin" \
    "sudo install -m 755 capteurs.sh /usr/local/bin/capteurs (Partie 8)" t_capteurs_installe
verifier "Capteurs temperature, pression et etat déclarés (extend)" \
    "ajoute les trois lignes extend de la Partie 8 dans $CONF, puis redémarre snmpd" t_extend
verifier "Température lisible en SNMPv3" \
    "si la requête SNMPv3 échoue aussi, corrige d'abord les passphrases ; sinon teste capteurs temperature, relis tes lignes extend et redémarre snmpd" t_capteurs_v3
verifier "Ligne de production revenue au mode nominal" \
    "sudo capteurs --nominal (retour au nominal après la panne simulée)" t_nominal

# ---------- Verdict ----------
if [ "$DETAILS" -eq 1 ]; then
    printf '%s\n' "${lignes[@]}"
    echo
fi

if [ "$reussis" -eq "$total" ]; then
    echo "${VERT}${GRAS}Tout est en place (${reussis}/${total}). Tu peux passer au TP4.${RAZ}"
    exit 0
else
    manquants=$((total - reussis))
    echo "${ROUGE}${GRAS}${reussis}/${total} contrôles validés : ${manquants} élément(s) manquant(s).${RAZ}"
    [ "$DETAILS" -eq 0 ] && echo "Relance avec : sudo ./verif-tp3.sh --details pour savoir quoi corriger."
    exit 1
fi
