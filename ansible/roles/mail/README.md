# mail

mail Ansible role sets up an email server on debian linux. It is based on lukesmith.xyz's emailwiz scripts, and is opinionated and biased in that direction. Tweaks and changes could be made as needed.

## Needed Variables

* ```subdom```: short domain under the top level domain (TLD)
* ```domain```: the TLD of the server
* ```maildomain```: combined ```subdom``` and ```domain```
