terraform {
  required_providers {
    linode = {
      source = "linode/linode"
    }
    remote = {
      source = "tenstad/remote"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
    }
  }
}

provider "linode" {
  token = var.li_token
}
provider "cloudflare" {
  api_token = var.cf_token
}
provider "remote" {}
variable "li_labsize" {}
variable "li_token" {}
variable "li_region" {}
variable "li_image" {}
variable "li_ed25519_private" {}
variable "li_domain" {}
variable "li_labdom" {}
variable "li_labdomain" {}
variable "li_labkasmadmin" {}
variable "li_labkasmuser" {}
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

resource "cloudflare_dns_record" "domain_lab_a" {
  zone_id = var.cf_zone_id
  type = "A"
  name = var.li_labdom
  ttl = 600
  content = linode_instance.domain_lab_instance.ip_address
}


resource "linode_firewall" "_fw" {
  label = "lab-fw"
  linodes = [linode_instance.domain_lab_instance.id]
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
    label = "Allow_WEB"
    action = "ACCEPT"
    ports = "80"
    ipv4 = ["0.0.0.0/0"]
    ipv6 = [ "::/0"]
  }

  inbound {
    protocol = "TCP"
    label = "Allow_HTTPS"
    action = "ACCEPT"
    ports = "443"
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

resource "linode_instance" "domain_lab_instance" {
  image = var.li_image
  label = var.li_labdomain
  region = var.li_region
  type = var.li_labsize
  authorized_keys = [linode_sshkey.li_ed25519.ssh_key]

}

resource "linode_rdns" "domain_lab_rdns" {
  address = linode_instance.domain_lab_instance.ip_address
  rdns = var.li_labdomain
}

resource "terraform_data" "ansible_lab" {
  depends_on = [
    cloudflare_dns_record.domain_lab_a,
  ]
  provisioner "local-exec" {
    command = "nmap -p 22 ${var.li_labdom}.${var.li_domain} | grep ssh | grep open ; while [ $? -ne 0 ]; do sleep 5;nmap -p 22 ${var.li_labdom}.${var.li_domain} | grep ssh | grep open ; done ; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u root -i '${linode_instance.domain_lab_instance.ip_address},' --private-key ${var.li_ed25519_private} --tags 'common, kasm' -e 'domain=${var.li_domain}' -e 'subdom=${var.li_labdom}' -e 'kasm_admin_password=${var.li_labkasmadmin}' -e 'kasm_user_password=${var.li_labkasmuser}' ../ansible/li_lab.yml"
  }
}

output "lab_droplet_ip" {
  value = linode_instance.domain_lab_instance.ip_address
}

