# Guide Ryan — Applicatie, Key Vault & Database

> Ryan is verantwoordelijk voor de SecureMed app, Key Vault secrets management en de MySQL database.
> Gebruik deze guide om stap voor stap je Terraform code en app code te schrijven.

---

## Stap 1 — modules/compute/ (App VM)

### `modules/compute/variables.tf`

```hcl
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "vm_size" { type = string }
variable "admin_username" { type = string }
variable "admin_password" { type = string; sensitive = true }
variable "wazuh_manager_ip" { type = string }
```

### `modules/compute/main.tf`

```hcl
resource "azurerm_network_interface" "app" {
  name                = "nic-app"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "app-ip-config"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
  }
}

resource "azurerm_linux_virtual_machine" "app" {
  name                            = "vm-app"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.app.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    export DEBIAN_FRONTEND=noninteractive
    apt-get update

    # NGINX installeren (frontend)
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx

    # Node.js installeren (backend API)
    apt-get install -y nodejs npm
    mkdir -p /opt/api
    cd /opt/api
    npm init -y
    npm install express mysql2

    # NGINX reverse proxy naar Node.js API
    cat > /etc/nginx/sites-available/api <<'NGINX'
    server {
        listen 3000;
        location / {
            proxy_pass http://127.0.0.1:3001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
    NGINX
    ln -sf /etc/nginx/sites-available/api /etc/nginx/sites-enabled/api
    systemctl reload nginx

    # Wazuh agent installeren (versie 4.9.2, moet matchen met manager)
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list
    apt-get update
    WAZUH_MANAGER="${var.wazuh_manager_ip}" apt-get install -y -o Dpkg::Options::='--force-confnew' wazuh-agent=4.9.2-1
    systemctl daemon-reload
    systemctl enable wazuh-agent
    systemctl start wazuh-agent
  EOF
  )
}
```

### `modules/compute/outputs.tf`

```hcl
output "app_private_ip" {
  value = azurerm_network_interface.app.private_ip_address
}

output "app_vm_id" {
  value = azurerm_linux_virtual_machine.app.id
}

output "app_identity_principal_id" {
  value = azurerm_linux_virtual_machine.app.identity[0].principal_id
}
```

**Commits**:
- `feat(compute): add app VM with NGINX and Node.js`
- `feat(compute): add Wazuh agent installation`

---

## Stap 2 — SecureMed Applicatie

### `app/securemed/package.json`

```json
{
  "name": "securemed",
  "version": "1.0.0",
  "description": "SecureMed - Medische applicatie met Zero Trust",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "mysql2": "^3.6.0"
  }
}
```

### `app/securemed/server.js`

```javascript
const express = require('express');
const path = require('path');
const app = express();
const PORT = 3001;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

// Rolgebaseerde data - Arts ziet alles, Verpleging minder, Administratie alleen planning
const ROLES = {
  'Arts': {
    patienten: true,
    dossiers: true,
    planning: true,
    medischeData: true
  },
  'Verpleging': {
    patienten: true,
    dossiers: false,
    planning: true,
    medischeData: false
  },
  'Administratie': {
    patienten: false,
    dossiers: false,
    planning: true,
    medischeData: false
  }
};

// Simpele gebruikers (in productie: Entra ID tokens)
const USERS = {
  'an.peeters': { naam: 'An Peeters', rol: 'Arts' },
  'jan.verpleeg': { naam: 'Jan Verpleegkundige', rol: 'Verpleging' },
  'lisa.admin': { naam: 'Lisa Administratie', rol: 'Administratie' },
  'dries.michiels': { naam: 'Dries Michiels', rol: null }
};

// Input validatie - voorkom SQL injection en XSS
function sanitizeInput(input) {
  if (typeof input !== 'string') return '';
  return input.replace(/[<>"';&|`$(){}]/g, '');
}

// Login endpoint
app.post('/api/login', (req, res) => {
  const username = sanitizeInput(req.body.username || '');
  const user = USERS[username];

  if (!user) {
    return res.status(401).json({ error: 'Gebruiker niet gevonden' });
  }

  if (!user.rol) {
    return res.status(403).json({ error: 'Toegang geweigerd - geen rol toegewezen' });
  }

  res.json({
    naam: user.naam,
    rol: user.rol,
    permissions: ROLES[user.rol]
  });
});

// Patienten endpoint - alleen met juiste rol
app.get('/api/patienten', (req, res) => {
  const rol = req.headers['x-user-role'];
  if (!rol || !ROLES[rol] || !ROLES[rol].patienten) {
    return res.status(403).json({ error: 'Geen toegang tot patientengegevens' });
  }

  res.json([
    { id: 1, naam: 'Jan de Vries', afdeling: 'Cardiologie' },
    { id: 2, naam: 'Maria Jansen', afdeling: 'Neurologie' }
  ]);
});

// GEEN debug endpoint - bewust verwijderd voor security
// GEEN /api/medewerkers - bevat gevoelige data

// Catch-all: onbekende API routes geven 404
app.all('/api/*', (req, res) => {
  res.status(404).json({ error: 'Endpoint bestaat niet' });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`SecureMed API draait op port ${PORT}`);
});
```

### `app/securemed/public/index.html`

```html
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SecureMed - Inloggen</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f0f4f8; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .login-box { background: white; padding: 2rem; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); width: 350px; }
        h1 { color: #1a73e8; text-align: center; }
        input { width: 100%; padding: 10px; margin: 8px 0; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }
        button { width: 100%; padding: 10px; background: #1a73e8; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        button:hover { background: #1557b0; }
        .error { color: red; text-align: center; display: none; }
        .success { color: green; }
        .info { background: #e8f0fe; padding: 10px; border-radius: 4px; margin-top: 10px; font-size: 14px; }
    </style>
</head>
<body>
    <div class="login-box">
        <h1>SecureMed</h1>
        <p style="text-align:center;color:#666;">Medisch informatiesysteem</p>
        <form id="loginForm">
            <input type="text" id="username" placeholder="Gebruikersnaam" required>
            <input type="password" id="password" placeholder="Wachtwoord" required>
            <button type="submit">Inloggen</button>
        </form>
        <p class="error" id="error"></p>
        <div class="info" id="result" style="display:none;"></div>
    </div>
    <script>
        document.getElementById('loginForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const username = document.getElementById('username').value;
            const errorEl = document.getElementById('error');
            const resultEl = document.getElementById('result');
            errorEl.style.display = 'none';
            resultEl.style.display = 'none';

            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ username })
                });
                const data = await res.json();
                if (!res.ok) {
                    errorEl.textContent = data.error;
                    errorEl.style.display = 'block';
                } else {
                    resultEl.innerHTML = '<p class="success">Welkom, ' + data.naam + '</p><p>Rol: <strong>' + data.rol + '</strong></p>';
                    resultEl.style.display = 'block';
                }
            } catch (err) {
                errorEl.textContent = 'Verbindingsfout';
                errorEl.style.display = 'block';
            }
        });
    </script>
</body>
</html>
```

**Commits**:
- `feat(app): add SecureMed backend with login and role-based access`
- `feat(app): add frontend login page`
- `feat(app): add input validation and OWASP hardening`

---

## Stap 3 — Setup scripts (voor/na vergelijking)

### `app/setup-onveilig.sh` (de SLECHTE versie)

```bash
#!/bin/bash
# ONVEILIGE versie - ter vergelijking met de veilige versie
# NIET GEBRUIKEN IN PRODUCTIE

# Hardcoded database wachtwoord (FOUT!)
DB_PASSWORD="SuperGeheim123!"
DB_HOST="mysql-zerotrust.mysql.database.azure.com"

# Debug endpoint open (FOUT!)
cat > /opt/api/server-onveilig.js <<'EOF'
const express = require('express');
const app = express();

// DEBUG ENDPOINT - lekt serverconfiguratie
app.get('/api/debug', (req, res) => {
    res.json({
        env: process.env,
        dbHost: "mysql-zerotrust.mysql.database.azure.com",
        dbPassword: "SuperGeheim123!",
        nodeVersion: process.version
    });
});

// MEDEWERKERS ENDPOINT - lekt PII
app.get('/api/medewerkers', (req, res) => {
    res.json([
        { naam: 'An Peeters', email: 'an.peeters@securemed.nl', bsn: '111222333', salaris: 4500 },
        { naam: 'Dries Michiels', email: 'dries@securemed.nl', bsn: '444555666', salaris: 3800 }
    ]);
});

// Geen input validatie (FOUT!)
app.get('/api/patient', (req, res) => {
    const id = req.query.id; // Direct in query zonder sanitatie
    res.json({ query: `SELECT * FROM patienten WHERE id = ${id}` });
});

app.listen(3001);
EOF

echo "ONVEILIGE versie geinstalleerd - alleen voor demo!"
```

### `app/setup-veilig.sh` (de GOEDE versie)

```bash
#!/bin/bash
# VEILIGE versie - secrets uit Key Vault via managed identity
set -e

# Secrets ophalen uit Key Vault via managed identity (geen wachtwoorden in code!)
export DB_PASSWORD=$(az keyvault secret show \
    --vault-name "kv-zt-SUFFIX" \
    --name "mysql-password" \
    --query "value" -o tsv)

export DB_HOST=$(az keyvault secret show \
    --vault-name "kv-zt-SUFFIX" \
    --name "mysql-host" \
    --query "value" -o tsv)

# App starten met secrets uit environment variables
cd /opt/api
node server.js

echo "VEILIGE versie gestart - secrets komen uit Key Vault"
```

**Commits**:
- `feat(app): add insecure setup script for demo comparison`
- `feat(app): add secure setup script with Key Vault integration`

---

## Stap 4 — modules/keyvault/

### `modules/keyvault/variables.tf`

```hcl
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "random_suffix" { type = string }
variable "app_identity_principal_id" {
  type        = string
  description = "Principal ID van de app VM managed identity"
}
```

### `modules/keyvault/main.tf`

```hcl
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = "kv-securemed-${var.random_suffix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  enable_rbac_authorization = true

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

# RBAC: Deployer krijgt admin rechten
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# RBAC: App VM krijgt alleen leesrechten op secrets (least privilege!)
resource "azurerm_role_assignment" "kv_app_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.app_identity_principal_id
}

# Secrets opslaan
resource "azurerm_key_vault_secret" "mysql_password" {
  name         = "mysql-password"
  value        = "WIJZIG-DIT"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "mysql_host" {
  name         = "mysql-host"
  value        = "mysql-zerotrust.mysql.database.azure.com"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_admin]
}
```

### `modules/keyvault/outputs.tf`

```hcl
output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}
```

**Commit**: `feat(keyvault): add Key Vault with managed identity RBAC`

---

## Stap 5 — modules/database/

### `modules/database/variables.tf`

```hcl
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "vnet_id" { type = string }
variable "mysql_admin_username" { type = string }
variable "mysql_admin_password" { type = string; sensitive = true }
```

### `modules/database/main.tf`

```hcl
resource "azurerm_private_dns_zone" "mysql" {
  name                = "privatelink.mysql.database.azure.com"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "mysql-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = var.vnet_id
}

resource "azurerm_mysql_flexible_server" "main" {
  name                   = "mysql-zerotrust"
  location               = var.location
  resource_group_name    = var.resource_group_name
  administrator_login    = var.mysql_admin_username
  administrator_password = var.mysql_admin_password
  sku_name               = "B_Standard_B1ms"
  version                = "8.0.21"
  zone                   = "1"

  delegated_subnet_id = var.subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.mysql.id

  storage {
    size_gb = 20
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.mysql]
}

resource "azurerm_mysql_flexible_database" "app" {
  name                = "appdb"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}
```

### `modules/database/outputs.tf`

```hcl
output "mysql_server_fqdn" {
  value = azurerm_mysql_flexible_server.main.fqdn
}

output "mysql_database_name" {
  value = azurerm_mysql_flexible_database.app.name
}
```

**Commit**: `feat(database): add MySQL Flexible Server with private DNS`

---

## Stap 6 — Documentatie

### `docs/keyvault-setup.md`
Beschrijf:
- Waarom Key Vault (geen hardcoded secrets in code of environment variables)
- RBAC vs Access Policies (wij gebruiken RBAC — moderner, fijnmaziger)
- Managed Identity: vm-app authenticeert automatisch, geen wachtwoorden nodig
- Rol "Key Vault Secrets User": kan secrets lezen maar niet wijzigen (least privilege)
- Hoe de app secrets ophaalt via `az keyvault secret show`
- Vergelijking voor/na: setup-onveilig.sh vs setup-veilig.sh

### `docs/app-hardening.md`
Beschrijf voor/na vergelijking:

| Aspect | Onveilig (voor) | Veilig (na) |
|--------|-----------------|-------------|
| Debug endpoint | `/api/debug` lekt env vars + wachtwoorden | Verwijderd (404) |
| Medewerkers endpoint | `/api/medewerkers` lekt PII + salarissen | Verwijderd (404) |
| Database wachtwoord | Hardcoded in script | Uit Key Vault via managed identity |
| Input validatie | Geen — SQL injection mogelijk | sanitizeInput() verwijdert gevaarlijke tekens |
| API catch-all | Onbekende routes geven 200 | Onbekende routes geven 404 |

OWASP Top 10 maatregelen:
- A01 Broken Access Control → rolgebaseerde toegang
- A02 Cryptographic Failures → HTTPS via App Gateway
- A03 Injection → input sanitatie
- A05 Security Misconfiguration → geen debug endpoints
- A07 Authentication Failures → MFA via Entra ID

### `docs/deployment-guide.md`
Stap-voor-stap:
1. `az login`
2. `terraform init`
3. `terraform plan -var-file="terraform.tfvars"`
4. `terraform apply`
5. Wacht op cloud-init (±15 min)
6. Bastion tunnel openen
7. Verifieer Wazuh agents

### `docs/ai-gebruik.md`
Beschrijf eerlijk:
- Welke AI tools gebruikt (Claude, ChatGPT, Copilot, etc.)
- Waarvoor: Terraform code generatie, troubleshooting, documentatie
- Wat gecontroleerd: alle code handmatig gereviewd, Terraform plan gecontroleerd
- Hallucinaties gevonden: ja/nee, welke
- Security risico's van AI: kan verkeerde NSG rules suggereren, secrets lekken in prompts
- Wat door het team zelf uitgewerkt: architectuur beslissingen, security design, testing
- Beperkingen: AI kent niet onze specifieke Azure omgeving

---

## Stap 7 — Key Vault toevoegen aan main.tf

> **Let op**: Lahce beheert main.tf. Vraag Lahce om dit blok toe te voegen nadat jij modules/keyvault/ hebt gecommit:

```hcl
module "keyvault" {
  source = "./modules/keyvault"

  resource_group_name       = data.azurerm_resource_group.main.name
  location                  = data.azurerm_resource_group.main.location
  random_suffix             = random_string.suffix.result
  app_identity_principal_id = module.compute.app_identity_principal_id
}
```

---

## Wat je moet kunnen uitleggen in de Q&A

- Waarom Key Vault en niet environment variables? (env vars zijn leesbaar, Key Vault is encrypted + audited)
- Wat is managed identity? (Azure wijst automatisch een identiteit toe aan de VM, geen wachtwoord nodig)
- Waarom RBAC en niet Access Policies? (RBAC is Azure-native, fijnmaziger, auditable)
- Wat is de voor/na vergelijking? (setup-onveilig vs setup-veilig)
- Welke OWASP top 10 risico's heb je aangepakt? (A01, A02, A03, A05, A07)
- Waarom is input validatie belangrijk? (voorkomt SQL injection, XSS)
- Hoe voorkom je dat secrets in git terechtkomen? (.gitignore, Key Vault, geen hardcoded values)
