# Pterodactyl / VPS MTU Fix (GRE Ready)

MTU fix script voor servers met een **GRE tunnel** of verlaagde WAN MTU.

Lost Docker MTU mismatches en container netwerkproblemen op.

---

## Probleem

Bij gebruik van een GRE tunnel wordt de WAN MTU vaak verlaagd (bijv. 1476).

Docker bridges blijven standaard op 1500 staan.

Gevolg:

- HTTPS timeouts in containers  
- Minecraft auth errors  
- API calls die blijven hangen  
- Host werkt, container niet  

Dit is een MTU mismatch.

---

## Wat kan dit script?

Interactief menu met opties:

1. **Pterodactyl fix**
   - Zet Docker MTU gelijk aan WAN MTU
   - Restart Docker + Wings
   - Recreate `pterodactyl_nw`

2. **Host/VPS MTU aanpassen**
   - Wijzigt MTU van een gekozen interface

3. **Allebei**
   - Past host MTU aan
   - Past Docker MTU aan
   - Recreate network

Je kunt kiezen tussen:
- Auto-detect MTU
- Custom MTU handmatig invoeren

---

## Gebruik

Run als root:

```bash
curl -fsSL https://raw.githubusercontent.com/ivoryvanboes2004-source/pterodactyl-mtu-fix/main/fix-mtu.sh -o fix-mtu.sh
chmod +x fix-mtu.sh
./fix-mtu.sh
