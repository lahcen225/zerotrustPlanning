# Guide Lahce — Netwerk, Wazuh & Honeypot

> Jij bent verantwoordelijk voor de hele netwerk-infra, Wazuh SIEM en de honeypot.
> Gebruik deze guide om stap voor stap je Terraform code te schrijven in de nieuwe repo.

---

## Stap 1 — Root bestanden aanmaken

### `provider.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

### `variables.tf`

```hcl
variable "resource_group_name" {
  type    = string
  default = "rg-zerotrust"
}

variable "location" {
  type    = string
  default = "Sweden Central"
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "admin_username" {
  type    = string
  default = "azureadmin"
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "mysql_admin_username" {
  type    = string
  default = "mysqladmin"
}

variable "mysql_admin_password" {
  type      = string
  sensitive = true
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s_v2"
}
```

### `main.tf`

```hcl
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

module "network" {
  source = "./modules/network"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  vnet_address_space  = var.vnet_address_space
}

module "bastion" {
  source = "./modules/bastion"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  subnet_id           = module.network.subnet_bastion_id
}

module "wazuh" {
  source = "./modules/wazuh"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  subnet_id           = module.network.subnet_wazuh_id
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
}

module "compute" {
  source = "./modules/compute"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  subnet_id           = module.network.subnet_app_id
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  wazuh_manager_ip    = module.wazuh.wazuh_private_ip
}

module "appgateway" {
  source = "./modules/appgateway"

  resource_group_name    = data.azurerm_resource_group.main.name
  location               = data.azurerm_resource_group.main.location
  subnet_id              = module.network.subnet_appgw_id
  frontend_vm_private_ip = module.compute.app_private_ip
  random_suffix          = random_string.suffix.result
}

module "database" {
  source = "./modules/database"

  resource_group_name  = data.azurerm_resource_group.main.name
  location             = data.azurerm_resource_group.main.location
  subnet_id            = module.network.subnet_database_id
  vnet_id              = module.network.vnet_id
  mysql_admin_username = var.mysql_admin_username
  mysql_admin_password = var.mysql_admin_password
}

module "honeypot" {
  source = "./modules/honeypot"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  subnet_id           = module.network.subnet_honeypot_id
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  wazuh_manager_ip    = module.wazuh.wazuh_private_ip
}
```

### `outputs.tf`

```hcl
output "vnet_id" {
  value = module.network.vnet_id
}

output "wazuh_private_ip" {
  value = module.wazuh.wazuh_private_ip
}

output "app_private_ip" {
  value = module.compute.app_private_ip
}

output "appgw_public_ip" {
  value = module.appgateway.appgw_public_ip
}

output "bastion_name" {
  value = module.bastion.bastion_name
}
```

### `terraform.tfvars.example`

```hcl
resource_group_name  = "rg-zerotrust"
location             = "Sweden Central"
admin_password       = "WIJZIG-DIT-WACHTWOORD"
mysql_admin_password = "WIJZIG-DIT-WACHTWOORD"
```

**Commit**: `feat: initial project setup with provider and root config`

---

## Stap 2 — modules/network/

### `modules/network/variables.tf`

```hcl
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "vnet_address_space" { type = list(string) }
```

### `modules/network/main.tf`

```hcl
resource "azurerm_virtual_network" "main" {
  name                = "vnet-zerotrust"
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
}

# --- Subnet: Azure Bastion ---
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/26"]
}

# --- Subnet: Application Gateway ---
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.64/26"]
}

# --- Subnet: App (Frontend + Backend) ---
resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# --- Subnet: Database ---
resource "azurerm_subnet" "database" {
  name                 = "snet-database"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/26"]

  delegation {
    name = "mysql-delegation"
    service_delegation {
      name    = "Microsoft.DBforMySQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# --- Subnet: Honeypot ---
resource "azurerm_subnet" "honeypot" {
  name                 = "snet-honeypot"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.64/26"]
  service_endpoints    = ["Microsoft.Storage"]
}

# --- Subnet: Wazuh ---
resource "azurerm_subnet" "wazuh" {
  name                 = "snet-wazuh"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/26"]
}

# =============================================
# NSG REGELS — Microsegmentatie per subnet
# =============================================

# --- NSG: App Subnet ---
resource "azurerm_network_security_group" "app" {
  name                = "nsg-app"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-HTTP-From-AppGW"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "10.0.0.64/26"
    destination_address_prefix = "10.0.1.0/24"
  }

  security_rule {
    name                       = "Allow-SSH-From-Bastion"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.0.0/26"
    destination_address_prefix = "10.0.1.0/24"
  }

  security_rule {
    name                       = "Allow-Frontend-To-Backend"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "10.0.1.0/24"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# --- NSG: Database Subnet ---
resource "azurerm_network_security_group" "database" {
  name                = "nsg-database"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-MySQL-From-App"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "10.0.2.0/26"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "database" {
  subnet_id                 = azurerm_subnet.database.id
  network_security_group_id = azurerm_network_security_group.database.id
}

# --- NSG: Honeypot Subnet (BLOKKEERT OUTBOUND!) ---
resource "azurerm_network_security_group" "honeypot" {
  name                = "nsg-honeypot"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-All-Inbound-Honeypot"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.2.64/26"
  }

  security_rule {
    name                       = "Deny-Internet-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.2.64/26"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "honeypot" {
  subnet_id                 = azurerm_subnet.honeypot.id
  network_security_group_id = azurerm_network_security_group.honeypot.id
}

# --- NSG: Wazuh Subnet ---
resource "azurerm_network_security_group" "wazuh" {
  name                = "nsg-wazuh"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-Wazuh-Agent-Registration"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["1514", "1515"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.3.0/26"
  }

  security_rule {
    name                       = "Allow-Wazuh-Dashboard"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.3.0/26"
  }

  security_rule {
    name                       = "Allow-SSH-From-Bastion"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.0.0/26"
    destination_address_prefix = "10.0.3.0/26"
  }

  security_rule {
    name                       = "Allow-Wazuh-Indexer"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9200"
    source_address_prefix      = "10.0.3.0/26"
    destination_address_prefix = "10.0.3.0/26"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "wazuh" {
  subnet_id                 = azurerm_subnet.wazuh.id
  network_security_group_id = azurerm_network_security_group.wazuh.id
}
```

### `modules/network/outputs.tf`

```hcl
output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "subnet_bastion_id" {
  value = azurerm_subnet.bastion.id
}

output "subnet_appgw_id" {
  value = azurerm_subnet.appgw.id
}

output "subnet_app_id" {
  value = azurerm_subnet.app.id
}

output "subnet_database_id" {
  value = azurerm_subnet.database.id
}

output "subnet_honeypot_id" {
  value = azurerm_subnet.honeypot.id
}

output "subnet_wazuh_id" {
  value = azurerm_subnet.wazuh.id
}
```

**Commits**:
- `feat(network): add VNet and subnet configuration`
- `feat(network): add NSG rules for all subnets`

---

## Stap 3 — modules/wazuh/

### `modules/wazuh/variables.tf`

```hcl
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "vm_size" { type = string }
variable "admin_username" { type = string }
variable "admin_password" { type = string; sensitive = true }
```

### `modules/wazuh/main.tf`

```hcl
resource "azurerm_network_interface" "wazuh" {
  name                = "nic-wazuh"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "wazuh-ip-config"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.3.10"
  }
}

resource "azurerm_linux_virtual_machine" "wazuh" {
  name                            = "vm-wazuh"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.wazuh.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 50
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
    set -e
    export DEBIAN_FRONTEND=noninteractive

    # Swap toevoegen (4 GB) voor betere performance
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Wazuh all-in-one installatie (manager + indexer + dashboard)
    curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
    curl -sO https://packages.wazuh.com/4.9/config.yml

    cat > config.yml <<'CONFIG'
    nodes:
      indexer:
        - name: wazuh-indexer
          ip: "10.0.3.10"
      server:
        - name: wazuh-server
          ip: "10.0.3.10"
      dashboard:
        - name: wazuh-dashboard
          ip: "10.0.3.10"
    CONFIG

    bash wazuh-install.sh --generate-config-files
    bash wazuh-install.sh --wazuh-indexer wazuh-indexer
    bash wazuh-install.sh --start-cluster
    bash wazuh-install.sh --wazuh-server wazuh-server
    bash wazuh-install.sh --wazuh-dashboard wazuh-dashboard

    # Honeypot detectie regels toevoegen
    cat >> /var/ossec/etc/rules/local_rules.xml <<'RULES'
    <group name="honeypot,">
      <rule id="100001" level="15">
        <if_sid>5716</if_sid>
        <match>decoyadmin</match>
        <description>ALARM: Decoy account login gedetecteerd</description>
      </rule>

      <rule id="100002" level="15">
        <if_sid>5715</if_sid>
        <hostname>vm-honeypot</hostname>
        <description>ALARM: SSH login op honeypot VM gedetecteerd</description>
      </rule>

      <rule id="100003" level="12">
        <if_sid>5501</if_sid>
        <hostname>vm-honeypot</hostname>
        <description>ALARM: Login poging op honeypot VM</description>
      </rule>
    </group>
    RULES

    systemctl restart wazuh-manager
  EOF
  )
}
```

### `modules/wazuh/outputs.tf`

```hcl
output "wazuh_private_ip" {
  value = azurerm_network_interface.wazuh.private_ip_address
}

output "wazuh_vm_id" {
  value = azurerm_linux_virtual_machine.wazuh.id
}
```

**Commits**:
- `feat(wazuh): add Wazuh all-in-one VM module`
- `feat(wazuh): add custom honeypot detection rules`

---

## Stap 4 — modules/honeypot/

### `modules/honeypot/variables.tf`

```hcl
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "vm_size" { type = string }
variable "admin_username" { type = string }
variable "admin_password" { type = string; sensitive = true }
variable "wazuh_manager_ip" { type = string }
```

### `modules/honeypot/main.tf`

```hcl
resource "azurerm_network_interface" "honeypot" {
  name                = "nic-honeypot"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "honeypot-ip-config"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.68"
  }
}

resource "azurerm_linux_virtual_machine" "honeypot" {
  name                            = "vm-honeypot"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.honeypot.id]

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
    apt-get install -y mysql-server
    systemctl enable mysql
    systemctl start mysql

    # Nep patientendata aanmaken
    mysql -e "CREATE DATABASE IF NOT EXISTS patienten_db;"
    mysql -e "CREATE TABLE IF NOT EXISTS patienten_db.patienten (id INT AUTO_INCREMENT PRIMARY KEY, naam VARCHAR(100), bsn VARCHAR(9), diagnose VARCHAR(200));"
    mysql -e "INSERT INTO patienten_db.patienten (naam, bsn, diagnose) VALUES ('Jan de Vries', '123456789', 'Griep'), ('Maria Jansen', '987654321', 'Controle');"

    # Decoy account aanmaken
    useradd -m -s /bin/bash decoyadmin
    echo "decoyadmin:HoneyP0t2024!" | chpasswd

    # Wazuh agent installeren (versie moet matchen met manager)
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

resource "random_string" "honey_storage" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "honeypot" {
  name                     = "sthoney${random_string.honey_storage.result}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [var.subnet_id]
  }
}
```

### `modules/honeypot/outputs.tf`

```hcl
output "honeypot_private_ip" {
  value = azurerm_network_interface.honeypot.private_ip_address
}

output "honeypot_vm_id" {
  value = azurerm_linux_virtual_machine.honeypot.id
}
```

**Commit**: `feat(honeypot): add honeypot VM with decoy accounts and Wazuh agent`

---

## Stap 5 — Documentatie

### `docs/infrastructuur-schema.md`
Beschrijf het netwerk diagram:
- VNet: 10.0.0.0/16
- Subnets: AzureBastionSubnet (10.0.0.0/26), snet-appgw (10.0.0.64/26), snet-app (10.0.1.0/24), snet-database (10.0.2.0/26), snet-honeypot (10.0.2.64/26), snet-wazuh (10.0.3.0/26)
- NSG regels per subnet en waarom
- Leg uit: waarom microsegmentatie (Zero Trust principe)

### `docs/wazuh-setup.md`
Beschrijf:
- Wat is Wazuh (open-source SIEM/XDR)
- All-in-one architectuur (manager + indexer + dashboard op 1 VM)
- Custom rules: 100001 (decoy login), 100002 (honeypot SSH), 100003 (honeypot login poging)
- Active response: automatische IP blokkade na brute force
- FIM: syscheck frequency 60s, monitored directories (/etc, /usr/bin, /usr/sbin)
- Discord webhook: real-time alerts naar team
- Koppeling met MITRE ATT&CK framework
- **Security Operations (SOC/SIEM) concept**: leg uit hoe dit past in een SOC workflow
- **CTI concept**: leg uit hoe custom rules gebaseerd zijn op threat intelligence

### `docs/honeypot-design.md`
Beschrijf:
- Wat is een honeypot en waarom
- Decoy account: decoyadmin (geen legitiem gebruik, elke login = alarm)
- Nep patientendata (BSN, diagnoses)
- NSG Deny-Internet-Outbound: data kan niet geexfiltreerd worden
- Wazuh agent rapporteert alles naar SIEM
- Honeytoken concept op applicatieniveau

### `docs/aanval-simulatie.md`
Beschrijf alle fases:
1. Brute force (sshpass, regel 5712)
2. Decoy login (regel 100002, level 15)
3. File tampering (/etc/hosts, FIM regel 550)
4. Data exfiltratie geblokkeerd (curl fails)
5. MITRE ATT&CK mapping (welke tactieken)

---

## Wat je moet kunnen uitleggen in de Q&A

- Waarom microsegmentatie? (Zero Trust: vertrouw geen enkel subnet)
- Waarom Deny-Internet-Outbound op honeypot? (data exfiltratie voorkomen)
- Hoe werken de custom Wazuh rules? (if_sid triggert op parent rule, hostname filtert op agent)
- Wat is het verschil tussen rule level 12 en 15? (15 = hoogste alarm)
- Hoe past dit in MITRE ATT&CK? (Credential Access, Lateral Movement, etc.)
- Wat is CTI en hoe pas je het toe? (threat intel → custom detection rules)
