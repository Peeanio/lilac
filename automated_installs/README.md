# Automated Installs

Each platform uses different ways to use a file at initiation to provide answers to installer questions or changes post-boot. Here is a collection of examples.

## Linux

### General 

##### cloud-init

Cloud-init is usually used to customise an install after taking an image and spinning it up. Typically, it is used to configure users and access to get a system customised enough for normal configuration management to kick in.

### Debian

#### Debian Preseed

Debian preseed is a file containing the answers to the installer questions to preform unattended installs. Works best when given via PXE as from ISO to login it is hands off. When installing from a clean manual ISO, then the file needs to be added in somehow.

## Windows

### unattended xml

more to come...
