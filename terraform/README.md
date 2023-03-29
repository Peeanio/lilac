## Terraform

Terraform is a good tool to declaratively manintain or create infrastructure, and knows its place in the landscape with the problems it optimizes for. Much of terraform comes down to the quality of the provider, which works better in API driven cloud environments than libvirt or docker daemons.

### Using Terraform

* Have at least one .tf file with providers and resources defined
* storing variables in ```terraform.tfvars```
* ```terraform init``` to start the state and package managing
** Keep in mind there other ways to store state and variables than just plaintext files, but that's outside scope for now
* ```terraform apply``` to kick off the automation
