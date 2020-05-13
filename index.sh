#!/bin/bash

export ldap_host="192.168.1.54"
export ldap_base_dn="dc=theta42,dc=com"

export ldap_admin_dn="cn=admin,dc=theta42,dc=com"
export ldap_admin_password=$1

export ldap_bind_dn="cn=ldapclient service,ou=people,dc=theta42,dc=com"
export ldap_bind_password=$2

export current_host=`hostname`

echo "ldap-auth-config ldap-auth-config/ldapns/ldap-server string ldap://$ldap_host" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/bindpw string $ldap_bind_password" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/rootbindpw string $ldap_admin_password" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/dbrootlogin boolean true" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/dblogin boolean true" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/ldapns/ldap_version string 3" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/pam_password string md5" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/ldapns/base-dn string $ldap_base_dn" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/move-to-debconf boolean true" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/rootbinddn string $ldap_admin_dn" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/binddn string $ldap_bind_dn" | debconf-set-selections
echo "ldap-auth-config ldap-auth-config/override boolean true" | debconf-set-selections

DEBIAN_FRONTEND=noninteractive apt install -y libnss-ldap libpam-ldap ldap-utils nscd
auth-client-config -t nss -p lac_ldap
pam-auth-update --enable ldap
pam-auth-update --enable mkhomedir
echo "session required pam_mkhomedir.so skel=/etc/skel umask=077" >> /etc/pam.d/common-session
systemctl restart nscd
systemctl enable nscd

## filter PAM login for only group members
echo "pam_filter &(|(memberof=cn=host_access,ou=groups,dc=theta42,dc=com)(memberof=cn=host_`hostname`_access,ou=groups,dc=theta42,dc=com))" >> /etc/ldap.conf

## Set up sudo-ldap

apt install -y sudo-ldap
sudo_ldap_template="$(cat files/sudo-ldap.conf)"
echo "$sudo_ldap_template" | mo > /etc/sudo-ldap.conf

## Set up SSHkey via LDAP
sudo_ldap_template="$(cat files/ldap-ssh-key)"
echo "$sudo_ldap_template" | mo > /usr/local/bin/ldap-ssh-key
chmod +x /usr/local/bin/ldap-ssh-key

echo "AuthorizedKeysCommand /usr/local/bin/ldap-ssh-key" >> /etc/ssh/sshd_config
echo "AuthorizedKeysCommandUser nobody" >> /etc/ssh/sshd_config
