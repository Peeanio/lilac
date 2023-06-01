terraform {
  required_providers {
    linode = {
      source = "linode/linode"
    }
    remote = {
      source = "tenstad/remote"
    }
  }
}

provider "linode" {
  token = var.li_token
}
provider "remote" {}

variable "li_size" {}
variable "li_token" {}
variable "li_region" {}
variable "li_subnet" {}
variable "li_image" {}
variable "li_ed25519_private" {}
variable "li_domain" {}
variable "li_subdom" {}
variable "li_maildomain" {}
variable "li_user" {}
#variable "li_user_data" {}
#variable "li_ansible_exec" {}

data "linode_sshkey" "li_ed25519" {
  label = "li_ed25519"
}

data "template_file" "cloud-init-yaml" {
  template = file("${path.module}/files/user_data.yml")
  vars = {
    init_ssh_public_key = data.digitalocean_ssh_key.li_ed25519.public_key
  }
}

resource "linode_instance_ip" "domain_mail_ip" {
  linode_id = linode_instance.domain_mail_instance.id
  public = true
}

resource "digitalocean_domain" "root_domain" {
  domain = var.li_domain
  type = "master"
}

resource "digitalocean_record" "domain_mail_a" {
  domain_id = digitalocean_domain.root_domain.id
  record_type = "A"
  name = var.li_subdom
  target = digitalocean_reserved_ip.domain_mail_ip.ip_address
}

resource "digitalocean_vpc" "domain_vpc" {
  name = "${var.li_domain}-vpc"
  region = var.li_region
  ip_range = var.li_subnet
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
  image = var.li_image
  name = var.li_maildomain
  region = var.li_region
  size = var.li_size
  ssh_keys = [data.digitalocean_ssh_key.li_ed25519.id]
  vpc_uuid = digitalocean_vpc.domain_vpc.id

  user_data = data.template_file.cloud-init-yaml.rendered

#  provisioner "local-exec" {
#    command = "sleep 10; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ${var.li_user} -i '${self.ipv4_address},' --private-key ${var.li_ed25519_private} --tags 'common, mail' -e 'domain=${var.li_domain}' -e 'subdom=${var.li_subdom}' -e 'maildomain=${var.li_maildomain}' ../ansible/site2.yml"
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
    command = "sleep 10; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ${var.li_user} -i '${digitalocean_reserved_ip.domain_mail_ip.ip_address},' --private-key ${var.li_ed25519_private} --tags 'common, mail' -e 'domain=${var.li_domain}' -e 'subdom=${var.li_subdom}' -e 'maildomain=${var.li_maildomain}' ../ansible/site2.yml"
  }
}

data "remote_file" "dkim_pub_key" {
  depends_on = [terraform_data.ansible_mail]
  conn {
    host = digitalocean_reserved_ip.domain_mail_ip.ip_address
    user = var.li_user
    sudo = true
    agent = true
  }
  path = "/etc/postfix/dkim/${var.li_subdom}_pub.txt"
}

resource "digitalocean_record" "domain_dmarc" {
  domain = digitalocean_domain.root_domain.id
  type = "TXT" 
  name = "_dmarc.${var.li_subdom}"
  value = "v=DMARC1; p=reject; rua=mailto:dmarc@${var.li_domain}; fo=1"
}

resource "digitalocean_record" "domain_dkim" {
  domain = digitalocean_domain.root_domain.id
  type = "TXT" 
  name = "${var.li_subdom}._domainkey"
  value = "v=DKIM1; k=rsa; ${trimspace(data.remote_file.dkim_pub_key.content)}"
}

resource "digitalocean_record" "domain_spf" {
  domain = digitalocean_domain.root_domain.id
  type = "TXT"
  name = "@"
  value = "v=spf1 mx a:${var.li_maildomain} -all"
}

resource "digitalocean_record" "domain_mx" {
  domain = digitalocean_domain.root_domain.id
  type = "MX"
  name = "@"
  value = "${var.li_maildomain}."
  priority = 10
}

resource "digitalocean_project_resources" "domain_project_resources" {
  project = digitalocean_project.domain_project.id
  resources = [
   digitalocean_domain.root_domain.urn,
   digitalocean_droplet.domain_mail_droplet.urn,
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
