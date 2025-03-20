terraform {
  required_providers {
    linode = {
      source = "linode/linode"
    }
    remote = {
      source = "tenstad/remote"
    }
   digitalocean = {
     source = "digitalocean/digitalocean"
   }
    cloudflare = {
      source  = "cloudflare/cloudflare"
    }
  }
}

provider "linode" {
  token = var.li_token
}
provider "digitalocean" {
  token = var.do_token
}
provider "cloudflare" {
  api_token = var.cf_token
}
provider "remote" {}
variable "do_token" {}
variable "li_size" {}
variable "li_token" {}
variable "li_region" {}
variable "li_image" {}
variable "li_ed25519_private" {}
variable "li_domain" {}
variable "li_subdom" {}
variable "li_maildomain" {}
variable "li_user" {}
variable "cf_zone_id" {}
variable "cf_token" {}

resource "linode_sshkey" "li_ed25519" {
  label = "li_ed25519"
  ssh_key = chomp(file("~/.ssh/li_ed25519.pub"))
}

data "template_file" "cloud-init-yaml" {
  template = file("${path.module}/files/user_data.yml")
  vars = {
    init_ssh_public_key = linode_sshkey.li_ed25519.ssh_key
  }
}

resource "digitalocean_domain" "root_domain" {
  name = var.li_domain
}

resource "cloudflare_dns_record" "domain_mail_a" {
  zone_id = var.cf_zone_id
  type = "A"
  name = var.li_subdom
  ttl = 3600
  content = linode_instance.domain_mail_instance.ip_address
}

resource "linode_firewall" "mail_fw" {
  label = "mail-fw"
  linodes = [linode_instance.domain_mail_instance.id]
  inbound_policy = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    protocol = "TCP"
    label = "Allow_SSH"
    action = "ACCEPT"
    ports = "22"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }

  inbound {
    protocol = "TCP"
    ports = "25"
    label = "Allow_SMTP"
    action = "ACCEPT"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }
 
  inbound {
    protocol = "TCP"
    label = "Allow_WEB"
    action = "ACCEPT"
    ports = "80"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }
 
  inbound {
    protocol = "TCP"
    label = "Allow_IMAP"
    action = "ACCEPT"
    ports = "143"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }

  inbound {
    protocol = "TCP"
    label = "Allow_SMTPs"
    action = "ACCEPT"
    ports = "465"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }

  inbound {
    protocol = "TCP"
    label = "Allow_SMTP_with-TLS"
    action = "ACCEPT"
    ports = "587"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }

  inbound {
    protocol = "TCP"
    label = "Allow_Spamassasin"
    action = "ACCEPT"
    ports = "783"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }

  inbound {
    protocol = "TCP"
    label = "Allow_IMAPs"
    action = "ACCEPT"
    ports = "993"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = ["::/0"]
  }

  outbound {
    protocol = "TCP"
    label = "Allow_all_outgoing"
    action = "ACCEPT"
    ports = "1-65535"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }
  
  outbound {
    protocol = "UDP"
    label = "Allow_DNS_out"
    action = "ACCEPT"
    ports = "53"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }

  outbound {
    protocol = "ICMP"
    label = "Allow_ICMP"
    action = "ACCEPT"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }
}

resource "linode_instance" "domain_mail_instance" {
  image = var.li_image
  label = var.li_maildomain
  region = var.li_region
  type = var.li_size
  authorized_keys = [linode_sshkey.li_ed25519.ssh_key]
  
}

resource "linode_rdns" "domain_mail_rdns" {
  address = linode_instance.domain_mail_instance.ip_address
  rdns = var.li_maildomain
}

resource "terraform_data" "ansible_mail" {
  depends_on = [
    cloudflare_dns_record.domain_mail_a,
  ]
  provisioner "local-exec" {
    command = "sleep 15; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u root -i '${linode_instance.domain_mail_instance.ip_address},' --private-key ${var.li_ed25519_private} --tags 'common, mail' -e 'domain=${var.li_domain}' -e 'subdom=${var.li_subdom}' -e 'maildomain=${var.li_maildomain}' ../ansible/li_mail.yml"
  }
}

data "remote_file" "dkim_pub_key" {
  depends_on = [terraform_data.ansible_mail]
  conn {
    host = linode_instance.domain_mail_instance.ip_address
    user = "root"
    sudo = true
    agent = true
  }
  path = "/etc/postfix/dkim/${var.li_subdom}_pub.txt"
}

resource "cloudflare_dns_record" "domain_dmarc" {
  zone_id = var.cf_zone_id
  type = "TXT" 
  name = "_dmarc.${var.li_subdom}"
  ttl = 3600
  content = "v=DMARC1; p=reject; rua=mailto:dmarc@${var.li_domain}; fo=1"
}

resource "cloudflare_dns_record" "domain_dkim" {
  zone_id = var.cf_zone_id
  type = "TXT" 
  name = "${var.li_subdom}._domainkey"
  ttl = 3600
  content = "v=DKIM1; k=rsa; ${trimspace(data.remote_file.dkim_pub_key.content)}"
}

resource "cloudflare_dns_record" "domain_spf" {
  zone_id = var.cf_zone_id
  type = "TXT"
  name = "@"
  ttl = 3600
  content = "v=spf1 mx a:${var.li_maildomain} -all"
}

resource "cloudflare_dns_record" "domain_mx" {
  zone_id = var.cf_zone_id
  type = "MX"
  name = "@"
  ttl = 3600
  priority = 10
  content = "${var.li_maildomain}."
}

output "mail_droplet_ip" {
  value = linode_instance.domain_mail_instance.ip_address
}

output "mail_dmarc_txt" {
  value = cloudflare_dns_record.domain_dmarc
}

output "mail_dkim_txt" {
  value = cloudflare_dns_record.domain_dkim
}

output "mail_spf_txt" {
  value = cloudflare_dns_record.domain_spf
}
