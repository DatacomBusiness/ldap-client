#!/bin/bash

ldapsearch -h {{ldap_host}} -D "{{ldap_bind_dn}}" -w "{{ldap_bind_password}}" '(&(|(memberof=cn=host_access,ou=groups,dc=theta42,dc=com)(memberof=cn=host_{{current_host}}_access,ou=groups,dc=theta42,dc=com))(uid='"$1"'))' 'sshPublicKey' | sed -n '/^ /{H;d};/sshPublicKey:/x;$g;s/\n *//g;s/sshPublicKey: //gp'
