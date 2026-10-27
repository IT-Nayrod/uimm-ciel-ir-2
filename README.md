# uimm-ciel-ir-2

Scripts des TP de cybersécurité du BTS CIEL 2 IR : préparation des machines, simulation d'activité et vérification de fin de TP.

## Récupérer le dépôt

Sur la VM indiquée dans le TP :

```bash
cd ~
git clone https://github.com/IT-Nayrod/uimm-ciel-ir-2.git
```

Si le dépôt est déjà cloné, mets-le à jour :

```bash
cd ~/uimm-ciel-ir-2 && git pull
```

## Contenu

| Dossier | TP | Scripts |
| --- | --- | --- |
| `tp03-snmp` | TP3 : Supervision SNMP, de v2c à v3 | `capteurs.sh` (simulation des capteurs de la ligne), `verif-tp3.sh` (vérification) |

## Scripts de vérification

Chaque TP se termine par un script de vérification, à lancer avec sudo sur la VM indiquée dans le TP :

```bash
sudo ./verif-tpX.sh            # verdict global
sudo ./verif-tpX.sh --details  # détail de ce qui manque et comment le corriger
```

Ne passe au TP suivant que lorsque le script affiche « Tout est en place ».
