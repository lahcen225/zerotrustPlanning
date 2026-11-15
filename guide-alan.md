# Guide Alan — Identiteit, Bastion, WAF, Rapport & Presentatie

> Alan is verantwoordelijk voor Entra ID (identiteit), Azure Bastion, Application Gateway + WAF,
> het rapport, de slides en de demo video.

---

## Stap 1 — modules/bastion/

### `modules/bastion/variables.tf`

```hcl
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
```

### `modules/bastion/main.tf`

```hcl
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "main" {
  name                = "bastion-zerotrust"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tunneling_enabled   = true

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = var.subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}
```

### `modules/bastion/outputs.tf`

```hcl
output "bastion_name" {
  value = azurerm_bastion_host.main.name
}

output "bastion_id" {
  value = azurerm_bastion_host.main.id
}
```

**Waarom Bastion?**
- Geen publieke IP's op VM's nodig (Zero Trust)
- SSH/RDP via Azure Portal of CLI tunnel
- Alle sessies worden gelogd (audit trail)
- SKU Standard nodig voor tunneling (CLI-gebruik)

**Commit**: `feat(bastion): add Azure Bastion with tunneling enabled`

---

## Stap 2 — modules/appgateway/

### `modules/appgateway/variables.tf`

```hcl
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "frontend_vm_private_ip" { type = string }
variable "random_suffix" { type = string }
```

### `modules/appgateway/main.tf`

```hcl
resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

data "azurerm_client_config" "current" {}

# Key Vault voor SSL certificaat
resource "azurerm_key_vault" "appgw" {
  name                       = "kv-zt-${var.random_suffix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions      = ["Get", "List", "Set", "Delete", "Purge"]
    certificate_permissions = ["Get", "List", "Create", "Import", "Delete", "Purge"]
  }

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

# Self-signed SSL certificaat
resource "azurerm_key_vault_certificate" "appgw" {
  name         = "appgw-ssl-cert"
  key_vault_id = azurerm_key_vault.appgw.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=appgw-zerotrust.local"
      validity_in_months = 12

      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }
  }
}

# Managed identity voor App Gateway
resource "azurerm_user_assigned_identity" "appgw" {
  name                = "id-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_key_vault_access_policy" "appgw_identity" {
  key_vault_id = azurerm_key_vault.appgw.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.appgw.principal_id

  secret_permissions      = ["Get"]
  certificate_permissions = ["Get"]
}

# Application Gateway met WAF
resource "azurerm_application_gateway" "main" {
  name                = "appgw-zerotrust"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw.id]
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = var.subnet_id
  }

  frontend_port {
    name = "https-port"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "appgw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name         = "frontend-vm-pool"
    ip_addresses = [var.frontend_vm_private_ip]
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  ssl_certificate {
    name                = "appgw-ssl-cert"
    key_vault_secret_id = azurerm_key_vault_certificate.appgw.secret_id
  }

  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "https-port"
    protocol                       = "Https"
    ssl_certificate_name           = "appgw-ssl-cert"
  }

  request_routing_rule {
    name                       = "routing-rule"
    priority                   = 1
    rule_type                  = "Basic"
    http_listener_name         = "https-listener"
    backend_address_pool_name  = "frontend-vm-pool"
    backend_http_settings_name = "http-settings"
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  firewall_policy_id = azurerm_web_application_firewall_policy.main.id

  depends_on = [azurerm_key_vault_access_policy.appgw_identity]
}

# WAF Policy - OWASP 3.2 in Prevention mode
resource "azurerm_web_application_firewall_policy" "main" {
  name                = "waf-policy-zerotrust"
  resource_group_name = var.resource_group_name
  location            = var.location

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}
```

### `modules/appgateway/outputs.tf`

```hcl
output "appgw_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}

output "appgw_id" {
  value = azurerm_application_gateway.main.id
}
```

**Commits**:
- `feat(appgateway): add Application Gateway module`
- `feat(appgateway): add WAF policy with OWASP 3.2 Prevention mode`

---

## Stap 3 — modules/identity/ (Entra ID)

> **Let op**: Entra ID configuratie kan niet altijd volledig via Terraform.
> Sommige dingen (Conditional Access, MFA) moeten handmatig in Azure Portal.
> Documenteer alles in `docs/identity-setup.md` met screenshots.

### `modules/identity/variables.tf`

```hcl
variable "resource_group_name" { type = string }
```

### `modules/identity/main.tf`

> Dit is een placeholder — de echte Entra ID config doe je in de Azure Portal.
> Documenteer elke stap met screenshots.

```hcl
# Entra ID configuratie wordt handmatig gedaan in Azure Portal
# omdat Terraform's AzureAD provider extra permissies vereist.
#
# Handmatige stappen (gedocumenteerd in docs/identity-setup.md):
#
# 1. Users aanmaken:
#    - an.peeters (Arts)
#    - jan.verpleeg (Verpleging)
#    - lisa.admin (Administratie)
#    - dries.michiels (geen rol - voor demo "toegang geweigerd")
#
# 2. App registratie "SecureMed" aanmaken
#
# 3. App rollen definiëren:
#    - Arts: volledige toegang tot patiëntendata
#    - Verpleging: beperkte toegang
#    - Administratie: alleen planning
#
# 4. MFA afdwingen voor alle gebruikers
#
# 5. Conditional Access policies:
#    - Require MFA for all cloud apps
#    - Block legacy authentication
#    - Block risky sign-ins

# RBAC op Resource Group level
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}
```

### `modules/identity/outputs.tf`

```hcl
output "identity_note" {
  value = "Entra ID is handmatig geconfigureerd - zie docs/identity-setup.md"
}
```

**Commit**: `feat(identity): add Entra ID configuration documentation and placeholder`

---

## Stap 4 — Handmatige Entra ID configuratie (Azure Portal)

### 4.1 Users aanmaken
1. Ga naar **Azure Portal** → **Entra ID** → **Users** → **New user**
2. Maak aan:
   - `an.peeters@JOUW-TENANT.onmicrosoft.com` — naam: An Peeters
   - `jan.verpleeg@JOUW-TENANT.onmicrosoft.com` — naam: Jan Verpleegkundige
   - `lisa.admin@JOUW-TENANT.onmicrosoft.com` — naam: Lisa Administratie
   - `dries.michiels@JOUW-TENANT.onmicrosoft.com` — naam: Dries Michiels (GEEN rol!)
3. **Screenshot maken** van de users lijst

### 4.2 App registratie
1. Ga naar **Entra ID** → **App registrations** → **New registration**
2. Naam: `SecureMed`
3. Redirect URI: `https://APP-GATEWAY-IP/callback`
4. Ga naar **App roles** → maak aan:
   - Display name: `Arts`, Value: `Arts`, Description: `Volledige toegang`
   - Display name: `Verpleging`, Value: `Verpleging`, Description: `Beperkte toegang`
   - Display name: `Administratie`, Value: `Administratie`, Description: `Alleen planning`
5. Ga naar **Enterprise applications** → SecureMed → **Users and groups**
6. Wijs rollen toe:
   - an.peeters → Arts
   - jan.verpleeg → Verpleging
   - lisa.admin → Administratie
   - dries.michiels → GEEN rol
7. **Screenshots maken** van app roles en toewijzingen

### 4.3 MFA afdwingen
1. Ga naar **Entra ID** → **Security** → **Authentication methods**
2. Zorg dat Microsoft Authenticator is ingeschakeld
3. Of gebruik **Security defaults** (dwingt MFA af voor iedereen)
4. **Screenshot maken**

### 4.4 Conditional Access
1. Ga naar **Entra ID** → **Security** → **Conditional Access** → **New policy**
2. Policy 1: **Require MFA**
   - Users: All users
   - Cloud apps: All cloud apps
   - Grant: Require MFA
   - Status: **On**
3. Policy 2: **Block legacy auth**
   - Users: All users
   - Client apps: Exchange ActiveSync, Other clients
   - Grant: Block access
   - Status: **On**
4. **Screenshots maken** van alle policies

---

## Stap 5 — Documentatie

### `docs/identity-setup.md`
Beschrijf met screenshots:
- Welke users zijn aangemaakt en waarom
- Wat zijn app rollen en hoe werken ze
- Waarom MFA (iets dat je weet + iets dat je hebt)
- Conditional Access policies: welke, waarom, wat doen ze
- Sign-in logs: hoe zie je dat CA is toegepast
- Verschil tussen Authentication (wie ben je) en Authorization (wat mag je)

### `docs/threat-model.md`
Gebruik STRIDE methodologie:

| Threat | Beschrijving | Maatregel |
|--------|-------------|-----------|
| **S**poofing | Aanvaller doet zich voor als legitieme gebruiker | MFA + Conditional Access |
| **T**ampering | Aanvaller wijzigt systeembestanden | File Integrity Monitoring (Wazuh) |
| **R**epudiation | Aanvaller ontkent acties | Wazuh logging + audit trail |
| **I**nformation Disclosure | Gevoelige data lekt | Key Vault + NSG segmentatie + geen debug endpoints |
| **D**enial of Service | Systeem onbereikbaar maken | WAF + rate limiting |
| **E**levation of Privilege | Ongeautoriseerde toegang krijgen | RBAC + least privilege + honeypot detectie |

Koppel elke maatregel aan een specifiek onderdeel van de infrastructuur.

### `docs/architectuur-schema.md`
Teken het architectuur diagram met alle componenten:
- Internet → App Gateway (WAF) → snet-app (vm-app)
- vm-app → snet-database (MySQL)
- vm-app ← snet-wazuh (Wazuh monitoring)
- snet-honeypot (vm-honeypot, geïsoleerd)
- Azure Bastion voor beheer
- Key Vault voor secrets
- Entra ID voor authenticatie

### `docs/nist-iso-mapping.md`
Map onze maatregelen naar frameworks:

| Onze maatregel | NIST CSF | ISO 27001 |
|---------------|----------|-----------|
| MFA + Conditional Access | PR.AC-1 (Identity Management) | A.9.4.2 (Secure log-on) |
| NSG segmentatie | PR.AC-5 (Network Integrity) | A.13.1.1 (Network controls) |
| WAF | PR.PT-4 (Communications Protection) | A.13.1.2 (Security of network services) |
| Key Vault | PR.DS-1 (Data-at-rest Protection) | A.10.1.1 (Cryptographic controls) |
| Wazuh SIEM | DE.CM-1 (Network Monitoring) | A.12.4.1 (Event logging) |
| FIM | DE.CM-7 (Unauthorized Changes) | A.12.4.3 (Admin and operator logs) |
| Honeypot | DE.CM-1 (Network Monitoring) | A.12.4.1 (Event logging) |
| Active Response | RS.MI-1 (Incidents Contained) | A.16.1.5 (Response to incidents) |
| RBAC | PR.AC-4 (Access Permissions) | A.9.2.3 (Management of privileged access) |
| Bastion | PR.AC-3 (Remote Access) | A.6.2.2 (Teleworking) |

### `README.md`

```markdown
# Zero Trust SecureMed

Zero Trust beveiligingsarchitectuur voor een medische applicatie, gebouwd met Terraform op Azure.

## Team
- **Lahce** — Netwerk, Wazuh SIEM, Honeypot
- **Ryan** — Applicatie, Key Vault, Database
- **Alan** — Identiteit, Bastion, WAF, Rapport

## Architectuur
- **VNet** met microsegmentatie (6 subnets, elk met eigen NSG)
- **Entra ID** met MFA en Conditional Access
- **Application Gateway** met WAF (OWASP 3.2, Prevention mode)
- **Azure Bastion** voor veilig beheer (geen publieke IP's)
- **Key Vault** met managed identity (geen hardcoded secrets)
- **Wazuh SIEM** met custom detectieregels en MITRE ATT&CK mapping
- **Honeypot** met decoy accounts en data exfiltratie blokkade

## Deployment

### Vereisten
- Azure CLI (`az login`)
- Terraform >= 1.5.0
- Azure subscription met Contributor rechten

### Stappen
1. Clone de repo
2. `cp terraform.tfvars.example terraform.tfvars` en vul wachtwoorden in
3. `terraform init`
4. `terraform plan`
5. `terraform apply`
6. Wacht ±15 minuten op cloud-init
7. Open Bastion tunnel naar Wazuh: zie docs/deployment-guide.md

## Security concepten
- Cyber Threat Intelligence (CTI)
- Cyber Threat Modeling (STRIDE)
- MITRE ATT&CK framework
- NIST CSF / ISO 27001
- Security Operations (SOC/SIEM)
- Application Security (OWASP Top 10)

## Documentatie
Zie de `docs/` map voor gedetailleerde documentatie per onderdeel.
```

---

## Stap 6 — Rapport schrijven

### Structuur (±10 pagina's)

1. **Inleiding** (1 pagina)
   - SecureMed scenario: medische app met gevoelige patientendata
   - Waarom Zero Trust: "never trust, always verify"
   - Teamsamenstelling en rolverdeling

2. **Aanpak** (2 pagina's)
   - Gekozen tools: Terraform, Azure, Wazuh
   - Methodologie: Infrastructure as Code, Defense in Depth
   - Planning en taakverdeling

3. **Implementatie** (3 pagina's)
   - Identiteit: Entra ID + MFA + CA (met screenshots)
   - Netwerk: segmentatie, WAF, Bastion
   - Secrets: Key Vault + managed identity
   - Detectie: Wazuh + honeypot + custom rules

4. **Resultaten** (2 pagina's)
   - Demo samenvatting: wat hebben we aangetoond
   - Screenshots van Wazuh alerts, WAF blocks, FIM events
   - MITRE ATT&CK mapping

5. **Lessons learned** (1 pagina)
   - Wat ging goed
   - Wat kon beter
   - Technische uitdagingen (FIM frequency, Wazuh agent versie, NSG blocking MySQL install)

6. **Groepsreflectie + Persoonlijke reflecties** (1 pagina)
   - Samenwerking
   - Persoonlijke leerpunten per teamlid
   - Toepasbaarheid in toekomstige context

7. **Bijlagen**
   - Link naar GitHub repo
   - Link naar demo video

---

## Stap 7 — Presentatie slides

### Slide structuur (±20 minuten)

1. Titelpagina: "Zero Trust SecureMed"
2. Agenda
3. Scenario: medische app, gevoelige data
4. Zero Trust uitleg: 4 lagen
5-8. Deel 1 (Alan): Identiteit — MFA, rollen, CA
9-12. Deel 2 (Ryan): Netwerk — WAF, NSG
13-14. Deel 3 (Ryan): Secrets — Key Vault
15-19. Deel 4 (Lahce): Detectie — Wazuh, honeypot, aanval
20. Afsluiting: Zero Trust samenvatting
21. Vragen?

Tips:
- Gebruik weinig tekst per slide, meer visuals
- Architectuur diagram op slide 4
- Screenshots van demo in de slides
- Zet command referenties in speaker notes, niet op slides

---

## Stap 8 — Demo video opnemen

1. Neem elk deel apart op (screen recording + microfoon)
2. Lahce neemt Deel 4 op, Ryan neemt Deel 2+3 op, Alan neemt Deel 1 op
3. Alan monteert alle delen tot 1 video
4. Totale duur: ±20 minuten
5. Geluid uit tijdens de demo, mondelinge toelichting erbij

---

## Wat je moet kunnen uitleggen in de Q&A

- Wat is Zero Trust? (Never trust, always verify — op elke laag)
- Waarom MFA? (Wachtwoord alleen is niet genoeg — iets dat je weet + iets dat je hebt)
- Wat doet Conditional Access? (Automatische regels: als X dan Y, bijv. risicovolle login → block)
- Wat is STRIDE? (Threat modeling methodologie — 6 categorieën van bedreigingen)
- Hoe past dit in NIST CSF? (Identify, Protect, Detect, Respond, Recover)
- Waarom Bastion en geen publieke IP's? (Minimaliseer aanvalsoppervlak)
- Wat is WAF Prevention vs Detection mode? (Prevention blokkeert actief, Detection logt alleen)
- Wat is het OWASP 3.2 ruleset? (Standaard regels tegen SQL injection, XSS, etc.)
