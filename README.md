# Pterodactyl MTU Fix (GRE Tunnel)

Fix voor Docker MTU mismatch wanneer je een **GRE tunnel** gebruikt.

## Probleem

Bij een GRE tunnel wordt je WAN MTU vaak verlaagd (bijv. 1476).  
Docker bridges blijven standaard op 1500 staan.

Gevolg:

- HTTPS timeouts in containers  
- Minecraft auth errors  
- API connecties die hangen  
- Host werkt, container niet  

Dit is een MTU mismatch.

---

## Wat doet deze script?

- Detecteert MTU van `eth0`
- Zet Docker MTU gelijk aan WAN MTU
- Herstart Docker + Wings
- Recreate `pterodactyl_nw`

---

## Gebruik

Run als root:

```bash
curl -fsSL https://raw.githubusercontent.com/ivoryvanboes2004-source/pterodactyl-mtu-fix/main/fix-mtu.sh -o fix-mtu.sh
chmod +x fix-mtu.sh
./fix-mtu.sh
