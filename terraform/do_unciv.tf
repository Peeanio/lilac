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
variable "do_uncivdomain" {}
variable "do_user" {}
variable "do_service_port" {}

data "digitalocean_ssh_key" "do_ed25519" {
  name = "do_ed25519"
}

data "template_file" "cloud-init-yaml" {
  template = file("${path.module}/files/user_data.yml")
  vars = {
    init_ssh_public_key = data.digitalocean_ssh_key.do_ed25519.public_key
  }
}

resource "digitalocean_reserved_ip" "domain_unciv_ip" {
  region = var.do_region
}

resource "digitalocean_reserved_ip_assignment" "domain_unciv_ip_assignment" {
  droplet_id = digitalocean_droplet.domain_unciv_droplet.id
  ip_address = digitalocean_reserved_ip.domain_unciv_ip.ip_address
}

resource "digitalocean_project" "domain_project" {
  name = var.do_domain
  description = "Container project for the ${var.do_domain} domain"
}

resource "digitalocean_domain" "root_domain" {
  depends_on = [digitalocean_project.domain_project]
  name = var.do_domain
}

resource "digitalocean_record" "domain_unciv_a" {
  domain = digitalocean_domain.root_domain.id
  type = "A"
  name = var.do_subdom
  value = digitalocean_reserved_ip.domain_unciv_ip.ip_address
}

resource "digitalocean_vpc" "domain_vpc" {
  name = "${var.do_domain}-vpc"
  region = var.do_region
  ip_range = var.do_subnet
}

resource "digitalocean_firewall" "unciv_fw" {
  name = "unciv-fw"
  droplet_ids = [digitalocean_droplet.domain_unciv_droplet.id]

  inbound_rule {
    protocol = "tcp"
    port_range = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol = "tcp"
    port_range = var.do_service_port
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

resource "digitalocean_droplet" "domain_unciv_droplet" {
  depends_on = [digitalocean_record.domain_unciv_a]
  image = var.do_image
  name = var.do_uncivdomain
  region = var.do_region
  size = var.do_size
  ssh_keys = [data.digitalocean_ssh_key.do_ed25519.id]
  vpc_uuid = digitalocean_vpc.domain_vpc.id

  user_data = data.template_file.cloud-init-yaml.rendered

}

resource "terraform_data" "ansible_unciv" {
  depends_on = [
    digitalocean_reserved_ip_assignment.domain_unciv_ip_assignment,
    digitalocean_record.domain_unciv_a,
    digitalocean_project_resources.domain_project_resources,
    #digitalocean_record.domain_caa
  ]
  provisioner "local-exec" {
    command = "sleep 10; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ${var.do_user} -i '${digitalocean_reserved_ip.domain_unciv_ip.ip_address},' --private-key ${var.do_ed25519_private} --tags 'common, unciv-server' ../ansible/site2.yml"
  }
}

resource "digitalocean_project_resources" "domain_project_resources" {
  project = digitalocean_project.domain_project.id
  resources = [
   digitalocean_domain.root_domain.urn,
   digitalocean_droplet.domain_unciv_droplet.urn,
  ] 
}

output "unciv_droplet_ip" {
  value = digitalocean_reserved_ip.domain_unciv_ip.ip_address
}
