# Taakverdeling — Zero Trust SecureMed (2 weken)

**Team**: Lahce, Ryan, Alan
**Deadline**: 2 weken vanaf nu
**Bron-repo (guide)**: terraform-zerotrust (bestaande infra)
**Doel-repo**: nieuwe lege repo, iedereen commit zijn eigen werk

---

## Week 1 — Infrastructuur + Applicatie + Documentatie basis

### Lahce — Netwerk, Wazuh & Honeypot

| Dag | Taak | Commits |
|-----|------|---------|
| Ma | Repo aanmaken, `main.tf`, `variables.tf`, `outputs.tf`, `provider.tf` root-bestanden | `feat: initial project setup with provider config` |
| Ma | `modules/network/` — VNet (10.0.0.0/16), 5 subnets | `feat(network): add VNet and subnet configuration` |
| Di | `modules/network/` — NSG regels per subnet (nsg-app, nsg-honeypot, nsg-database, nsg-wazuh) | `feat(network): add NSG rules for all subnets` |
| Di | NSG Deny-Internet-Outbound regel voor honeypot | `feat(network): add deny-outbound rule for honeypot` |
| Wo | `modules/wazuh/` — Wazuh all-in-one VM (manager + indexer + dashboard), 4GB swap | `feat(wazuh): add Wazuh all-in-one VM module` |
| Do | Custom honeypot detection rules (100001, 100002, 100003) in local_rules.xml | `feat(wazuh): add custom honeypot detection rules` |
| Do | Active response config + Discord webhook | `feat(wazuh): configure active response and Discord alerts` |
| Vr | FIM (syscheck) frequency 60s + monitored directories | `feat(wazuh): configure File Integrity Monitoring` |
| Vr | `modules/honeypot/` — Honeypot VM, decoy account (decoyadmin), Wazuh agent 4.9.2 | `feat(honeypot): add honeypot VM with decoy accounts` |
| Za | `docs/infrastructuur-schema.md` — netwerk diagram | `docs: add infrastructuur schema` |
| Za | `docs/wazuh-setup.md` — Wazuh uitleg, custom rules, active response | `docs: add wazuh setup guide` |

### Ryan — Applicatie, Key Vault & Database

| Dag | Taak | Commits |
|-----|------|---------|
| Ma | `modules/compute/` — App VM met NGINX + Node.js, static IP 10.0.1.10 | `feat(compute): add app VM with NGINX and Node.js` |
| Ma | Wazuh agent installatie op app VM (versie 4.9.2) | `feat(compute): add Wazuh agent installation` |
| Di | `app/securemed/server.js` — backend basis + login endpoint | `feat(app): add SecureMed backend with login` |
| Di | `app/securemed/public/index.html` — frontend login pagina | `feat(app): add frontend login page` |
| Wo | Rolgebaseerde toegang (Arts, Verpleging, Administratie) + input validatie | `feat(app): add role-based access and input validation` |
| Wo | Debug endpoints verwijderd, OWASP hardening | `feat(app): harden API endpoints against OWASP top 10` |
| Do | `app/setup-onveilig.sh` — onveilige versie (hardcoded secrets, debug endpoints open) | `feat(app): add insecure setup script for demo comparison` |
| Do | `app/setup-veilig.sh` — veilige versie (secrets uit Key Vault) | `feat(app): add secure setup script with Key Vault` |
| Vr | `modules/keyvault/` — Key Vault + managed identity + RBAC (Secrets User rol) | `feat(keyvault): add Key Vault with managed identity RBAC` |
| Za | `modules/database/` — MySQL Flexible Server, private endpoint in snet-database | `feat(database): add MySQL Flexible Server module` |
| Za | `docs/keyvault-setup.md` — secrets management uitleg | `docs: add Key Vault setup guide` |

### Alan — Identiteit, Bastion, WAF & Rapport start

| Dag | Taak | Commits |
|-----|------|---------|
| Ma | `modules/bastion/` — Azure Bastion in AzureBastionSubnet, tunneling enabled | `feat(bastion): add Azure Bastion module` |
| Di | `modules/appgateway/` — Application Gateway, backend pool vm-app, HTTP listener | `feat(appgateway): add Application Gateway module` |
| Di | WAF policy met OWASP 3.2 ruleset, Prevention mode | `feat(appgateway): add WAF policy with OWASP rules` |
| Wo | `modules/identity/` — Entra ID users (an.peeters, dries.michiels, etc.) | `feat(identity): add Entra ID user configuration` |
| Wo | App rollen (Arts, Verpleging, Administratie) + roltoewijzingen | `feat(identity): add app roles and assignments` |
| Do | MFA afdwingen + Conditional Access policies (MFA, block legacy auth, block risky sign-ins) | `feat(identity): add MFA and Conditional Access policies` |
| Vr | `docs/identity-setup.md` — Entra ID, MFA, CA uitleg | `docs: add identity setup guide` |
| Vr | `docs/threat-model.md` — STRIDE analyse van SecureMed | `docs: add threat model with STRIDE` |
| Za | `README.md` — project overzicht, team, hoe te deployen | `docs: add README` |
| Za | `docs/architectuur-schema.md` — architectuur diagram alle componenten | `docs: add architectuur schema` |

---

## Week 2 — Documentatie, Presentatie, Rapport & Demo

### Lahce — Security docs + Demo voorbereiding

| Dag | Taak | Commits |
|-----|------|---------|
| Ma | `docs/honeypot-design.md` — waarom honeypot, decoy accounts, honeytoken uitleg | `docs: add honeypot design document` |
| Ma | `docs/aanval-simulatie.md` — alle stappen van de hacker simulatie + verwachte alerts | `docs: add aanval simulatie guide` |
| Di | `DEMO-STAPPENPLAN.md` — complete demo guide met commando's | `docs: add demo stappenplan` |
| Wo | Demo Deel 4 oefenen: Wazuh + honeypot + aanval simulatie | — |
| Do | Demo opnemen (Deel 4: brute force, decoy login, FIM, exfiltratie, MITRE ATT&CK) | — |
| Vr | `rapport/reflecties/lahce.md` — persoonlijke reflectie (±1 pagina) | `docs: add Lahce reflectie` |
| Za | Review van rapport + feedback geven aan Alan | — |

### Ryan — App security docs + Demo voorbereiding

| Dag | Taak | Commits |
|-----|------|---------|
| Ma | `docs/app-hardening.md` — voor vs na vergelijking, OWASP maatregelen | `docs: add app hardening document` |
| Ma | `docs/deployment-guide.md` — stap-voor-stap deployment instructies | `docs: add deployment guide` |
| Di | `docs/ai-gebruik.md` — AI tools gebruikt, wat gecontroleerd, beperkingen, risico's | `docs: add AI usage documentation` |
| Wo | Demo Deel 2+3 oefenen: WAF, NSG, Key Vault, managed identity | — |
| Do | Demo opnemen (Deel 2: WAF + segmentatie, Deel 3: Key Vault + RBAC) | — |
| Vr | `rapport/reflecties/ryan.md` — persoonlijke reflectie (±1 pagina) | `docs: add Ryan reflectie` |
| Za | Review van rapport + feedback geven aan Alan | — |

### Alan — Rapport + Presentatie + Demo

| Dag | Taak | Commits |
|-----|------|---------|
| Ma | `docs/nist-iso-mapping.md` — mapping maatregelen → NIST CSF / ISO 27001 controls | `docs: add NIST ISO mapping` |
| Di | `rapport/rapport.md` — scenario, context, aanpak, tools (eerste 4 pagina's) | `docs: add rapport draft` |
| Wo | Rapport: screenshots + schema's verzamelen van alle 3, lessons learned | `docs: add screenshots and lessons learned` |
| Wo | Rapport: groepsreflectie + aanbevelingen + toepasbaarheid | `docs: update rapport with reflections` |
| Do | Rapport: eindredactie, opmaak, spelcheck, exporteren als PDF | `docs: finalize rapport` |
| Do | Slides maken: intro → aanpak → resultaten → lessons learned | `feat: add presentatie slides` |
| Vr | Demo Deel 1 oefenen + opnemen (Entra ID, MFA, rollen, CA) | — |
| Vr | Alle demo delen samenvoegen tot 1 video | — |
| Za | Alles inleveren: rapport (PDF) + video + repo link via Blackboard | — |

---

## Wie presenteert wat (20 min + 10 min Q&A)

| Tijd | Wie | Onderwerp |
|------|-----|-----------|
| 0:00–1:00 | Alan | Intro: SecureMed scenario, waarom Zero Trust |
| 1:00–5:00 | Alan | Deel 1: Identiteit — Entra ID, MFA, rollen, Conditional Access |
| 5:00–9:00 | Ryan | Deel 2: Netwerk & App — WAF, NSG, segmentatie, app hardening |
| 9:00–12:00 | Ryan | Deel 3: Secrets — Key Vault, managed identity, RBAC |
| 12:00–18:00 | Lahce | Deel 4: Detectie — Wazuh, honeypot, aanval simulatie, MITRE ATT&CK |
| 18:00–20:00 | Alan | Afsluiting: Zero Trust samenvatting, lessons learned |
| 20:00–30:00 | Iedereen | Q&A: iedereen beantwoordt vragen over zijn eigen deel |

---

## Security concepten verdeling (15%)

| Concept | Wie | Waar |
|---------|-----|------|
| Cyber Threat Intelligence (CTI) | Lahce | docs/wazuh-setup.md + docs/aanval-simulatie.md |
| Cyber Threat Modeling (CTM/STRIDE) | Alan | docs/threat-model.md |
| MITRE ATT&CK framework | Lahce | docs/aanval-simulatie.md + Wazuh dashboard demo |
| NIST CSF / ISO 27001 | Alan | docs/nist-iso-mapping.md |
| Security Operations (SOC/SIEM) | Lahce | docs/wazuh-setup.md + demo |
| Application Security (AppSec) | Ryan | docs/app-hardening.md + demo |

---

## Checklist rapport (10%) — Alan is eindverantwoordelijke

- [ ] Scenario en context beschreven
- [ ] Aanpak, tools en security-aspecten uitgelegd
- [ ] Screenshots en schema's (infra, architectuur, componenten)
- [ ] Lessons learned + aanbevelingen
- [ ] Groepsreflectie: wat ging goed, wat kan beter
- [ ] Persoonlijke reflectie per persoon (±1 pagina)
- [ ] Toepasbaarheid in toekomstige context
- [ ] Link naar demo video
- [ ] Link naar GitHub repo met commit history
- [ ] ±10 pagina's, duidelijke structuur, geen spelfouten, professionele toon
- [ ] Geüpload als PDF op Blackboard

## Checklist GitHub documentatie (25%) — iedereen eigen deel

- [ ] Repo aangemaakt (Lahce)
- [ ] Infrastructuurschema (Lahce)
- [ ] Architectuurschema (Alan)
- [ ] Alle scripts toegevoegd (Ryan: setup scripts)
- [ ] Alle configuratiebestanden (iedereen: eigen modules)
- [ ] AI-gebruik gedocumenteerd met controle en beperkingen (Ryan)
- [ ] Deployment instructies aanwezig en reproduceerbaar (Ryan)
- [ ] Commit history verspreid over alle 3 teamleden

## Checklist presentatie (30%) — Alan coördineert

- [ ] ±20 minuten + 10 minuten Q&A
- [ ] Slides aanwezig en duidelijk (Alan)
- [ ] Logische opbouw: intro → aanpak → resultaten → lessons learned
- [ ] Pre-recorded demo met mondelinge toelichting
- [ ] Iedereen kan vragen beantwoorden over eigen deel
- [ ] Ingediend via Blackboard op tijd

## Checklist technische moeilijkheidsgraad (20%)

- [ ] Geavanceerde technieken: Wazuh SIEM, custom rules, honeypot, active response (Lahce)
- [ ] Automatisatie: Terraform IaC, cloud-init scripts (iedereen)
- [ ] Creatieve oplossingen: honeytoken, decoy accounts, NSG exfiltratie blokkade (Lahce)
- [ ] App hardening: voor/na vergelijking, OWASP (Ryan)
- [ ] Zero Trust identity: Conditional Access, MFA, RBAC (Alan)

## Checklist security concepten (15%)

- [ ] CTI correct toegepast (Lahce)
- [ ] CTM/STRIDE correct toegepast (Alan)
- [ ] MITRE ATT&CK / NIST / ISO 27001 zichtbaar verwerkt (Lahce + Alan)
- [ ] Security Operations zichtbaar in oplossing (Lahce)
- [ ] AppSec aantoonbaar meegenomen (Ryan)
- [ ] Concepten technisch onderbouwd en gekoppeld aan scenario

---

## Repo structuur

```
terraform-zerotrust/
├── main.tf                        # Lahce
├── variables.tf                   # Lahce
├── outputs.tf                     # Lahce
├── provider.tf                    # Lahce
├── terraform.tfvars.example       # Lahce
├── modules/
│   ├── network/                   # Lahce
│   ├── wazuh/                     # Lahce
│   ├── honeypot/                  # Lahce
│   ├── compute/                   # Ryan
│   ├── keyvault/                  # Ryan
│   ├── database/                  # Ryan
│   ├── identity/                  # Alan
│   ├── bastion/                   # Alan
│   └── appgateway/                # Alan
├── app/
│   ├── securemed/                 # Ryan
│   ├── setup-veilig.sh            # Ryan
│   └── setup-onveilig.sh          # Ryan
├── docs/
│   ├── infrastructuur-schema.md   # Lahce
│   ├── wazuh-setup.md             # Lahce
│   ├── honeypot-design.md         # Lahce
│   ├── aanval-simulatie.md        # Lahce
│   ├── keyvault-setup.md          # Ryan
│   ├── app-hardening.md           # Ryan
│   ├── deployment-guide.md        # Ryan
│   ├── ai-gebruik.md              # Ryan
│   ├── identity-setup.md          # Alan
│   ├── threat-model.md            # Alan
│   ├── architectuur-schema.md     # Alan
│   └── nist-iso-mapping.md        # Alan
├── rapport/
│   ├── rapport.md                 # Alan (eindredactie)
│   ├── screenshots/               # Iedereen
│   └── reflecties/
│       ├── lahce.md
│       ├── ryan.md
│       └── alan.md
├── presentatie/
│   └── slides.md                  # Alan
├── DEMO-STAPPENPLAN.md            # Lahce
└── README.md                      # Alan
```

---

## Git tips

- **Feature branches**: `feature/network`, `feature/app`, `feature/identity`, etc.
- **Pull Requests**: review elkaars code (minstens 2-3 PR's per persoon)
- **Commit messages**: `feat(module): beschrijving`, `docs: beschrijving`, `fix(module): beschrijving`
- **Verspreid commits over meerdere dagen** — niet alles op 1 dag
- **Minstens 10-15 commits per persoon**
