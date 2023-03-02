# Ansible

Ansible is a tool that is a very general and flexible configuration management tool that can be shoe-horned into many patterns that it may not be the best for, but can tackle with some work. 

## Using these Roles

1. Create an inventory file
    - Example: ```touch inventory ; echo $'[minecraft]\n192.168.0.5' > inventory```
2. Create a site playbook, which calls the roles based on how the inventory file is setup
    - Example: ```touch site.yml ; echo $'- name: common config\n  hosts: all\n  remote_user: root\n  roles:\n    - common\n\n- name: minecraft config\n  hosts: minecraft\n  remote_user: root\n  roles:\n    - minecraft' ```
3. Run the plays using ansible
    - Example: ```ansible-playbook -i inventory site.yml```

## Role Structure
```
 roles/
 ├── common
     ├── tasks
     │   └── main.yml
     └── templates
         └── fail2ban.ssh.conf.j2
```