terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    remote = {
      source = "tenstad/remote"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}
provider "remote" {}

variable "do_size" {}
variable "do_token" {}
variable "do_region" {}
variable "do_subnet" {}
variable "do_image" {}
variable "do_ed25519_private" {}
variable "do_domain" {}
variable "do_subdom" {}
variable "do_maildomain" {}
variable "do_user" {}
#variable "do_user_data" {}
#variable "do_ansible_exec" {}

data "digitalocean_ssh_key" "do_ed25519" {
  name = "do_ed25519"
}

data "template_file" "cloud-init-yaml" {
  template = file("${path.module}/files/user_data.yml")
  vars = {
    init_ssh_public_key = data.digitalocean_ssh_key.do_ed25519.public_key
  }
}

resource "digitalocean_reserved_ip" "domain_mail_ip" {
  region = var.do_region
}

resource "digitalocean_reserved_ip_assignment" "domain_mail_ip_assignment" {
  droplet_id = digitalocean_droplet.domain_mail_droplet.id
  ip_address = digitalocean_reserved_ip.domain_mail_ip.ip_address
}

resource "digitalocean_project" "domain_project" {
  name = var.do_domain
  description = "Container project for the ${var.do_domain} domain"
}

resource "digitalocean_domain" "root_domain" {
  depends_on = [digitalocean_project.domain_project]
  name = var.do_domain
}

resource "digitalocean_record" "domain_mail_a" {
  domain = digitalocean_domain.root_domain.id
  type = "A"
  name = var.do_subdom
  value = digitalocean_reserved_ip.domain_mail_ip.ip_address
}

resource "digitalocean_vpc" "domain_vpc" {
  name = "${var.do_domain}-vpc"
  region = var.do_region
  ip_range = var.do_subnet
}

resource "digitalocean_firewall" "mail_fw" {
  name = "mail-fw"
  droplet_ids = [digitalocean_droplet.domain_mail_droplet.id]

  inbound_rule {
    protocol = "tcp"
    port_range = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol = "tcp"
    port_range = "25"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
 
  inbound_rule {
    protocol = "tcp"
    port_range = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
 
  inbound_rule {
    protocol = "tcp"
    port_range = "143"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol = "tcp"
    port_range = "465"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol = "tcp"
    port_range = "587"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol = "tcp"
    port_range = "783"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol = "tcp"
    port_range = "993"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol = "tcp"
    port_range = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  
  outbound_rule {
    protocol = "udp"
    port_range = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "digitalocean_droplet" "domain_mail_droplet" {
  depends_on = [digitalocean_record.domain_mail_a]
  image = var.do_image
  name = var.do_maildomain
  region = var.do_region
  size = var.do_size
  ssh_keys = [data.digitalocean_ssh_key.do_ed25519.id]
  vpc_uuid = digitalocean_vpc.domain_vpc.id

  user_data = data.template_file.cloud-init-yaml.rendered

#  provisioner "local-exec" {
#    command = "sleep 10; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u kryten -i '${self.ipv4_address},' --private-key ${var.do_ed25519_private} --tags 'common, mail' -e 'domain=${var.do_domain}' -e 'subdom=${var.do_subdom}' -e 'maildomain=${var.do_maildomain}' ../ansible/site2.yml"
#  }
}

resource "terraform_data" "ansible_mail" {
  depends_on = [
    digitalocean_reserved_ip_assignment.domain_mail_ip_assignment,
    digitalocean_record.domain_mail_a,
    digitalocean_project_resources.domain_project_resources,
    #digitalocean_record.domain_caa
  ]
  provisioner "local-exec" {
    command = "sleep 10; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u kryten -i '${digitalocean_reserved_ip.domain_mail_ip.ip_address},' --private-key ${var.do_ed25519_private} --tags 'common, mail' -e 'domain=${var.do_domain}' -e 'subdom=${var.do_subdom}' -e 'maildomain=${var.do_maildomain}' ../ansible/site2.yml"
  }
}

data "remote_file" "dkim_pub_key" {
  depends_on = [terraform_data.ansible_mail]
  conn {
    host = digitalocean_reserved_ip.domain_mail_ip.ip_address
    user = var.do_user
    sudo = true
    agent = true
  }
  path = "/etc/postfix/dkim/${var.do_subdom}_pub.txt"
}

resource "digitalocean_record" "domain_dmarc" {
  domain = digitalocean_domain.root_domain.id
  type = "TXT" 
  name = "_dmarc.${var.do_subdom}"
  value = "v=DMARC1; p=reject; rua=mailto:dmarc@${var.do_domain}; fo=1"
}

resource "digitalocean_record" "domain_dkim" {
  domain = digitalocean_domain.root_domain.id
  type = "TXT" 
  name = "${var.do_subdom}._domainkey"
  value = "v=DKIM1; k=rsa; ${trimspace(data.remote_file.dkim_pub_key.content)}"
}

resource "digitalocean_record" "domain_spf" {
  domain = digitalocean_domain.root_domain.id
  type = "TXT"
  name = "@"
  value = "v=spf1 mx a:${var.do_maildomain} -all"
}

resource "digitalocean_record" "domain_mx" {
  domain = digitalocean_domain.root_domain.id
  type = "MX"
  name = "@"
  value = "${var.do_maildomain}."
  priority = 10
}

resource "digitalocean_project_resources" "domain_project_resources" {
  project = digitalocean_project.domain_project.id
  resources = [
   digitalocean_domain.root_domain.urn,
  ] 
}

output "mail_droplet_ip" {
  value = digitalocean_reserved_ip.domain_mail_ip.ip_address
}

output "mail_dmarc_txt" {
  value = digitalocean_record.domain_dmarc
}

output "mail_dkim_txt" {
  value = digitalocean_record.domain_dkim
}

output "mail_spf_txt" {
  value = digitalocean_record.domain_spf
}
