#!/bin/bash


# Stop this script on any error.
set -e


# Pull in the mustache template library for bash
source lib/mo


# Set some variables for the test of the file
## TODO! Dont hard code these values.
export ldap_host="192.168.1.55"
export ldap_base_dn="dc=theta42,dc=com"

export ldap_admin_dn="cn=admin,dc=theta42,dc=com"
export ldap_admin_password=$1

export ldap_bind_dn="cn=ldapclient service,ou=people,dc=theta42,dc=com"
export ldap_bind_password=$2

export current_host=`hostname`


# Configure the options for the LDAP packages based on debian or ubuntu
if grep -qiE "^NAME=\"debian" /etc/os-release; then

	echo "libnss-ldap libnss-ldap/rootbindpw string $ldap_admin_password" | debconf-set-selections
	echo "libnss-ldap libnss-ldap/bindpw string $ldap_bind_password" | debconf-set-selections
	echo "libnss-ldap libnss-ldap/dbrootlogin boolean true" | debconf-set-selections
	echo "libnss-ldap libnss-ldap/binddn string $ldap_bind_dn" | debconf-set-selections
	echo "libnss-ldap libnss-ldap/confperm boolean false" | debconf-set-selections
	echo "libnss-ldap libnss-ldap/rootbinddn string $ldap_admin_dn" | debconf-set-selections
	echo "libnss-ldap libnss-ldap/dblogin boolean false" | debconf-set-selections
	echo "libnss-ldap libnss-ldap/override boolean true" | debconf-set-selections
	echo "shared shared/ldapns/ldap-server string ldap://$ldap_host" | debconf-set-selections
	echo "shared shared/ldapns/base-dn string $ldap_base_dn" | debconf-set-selections
	echo "shared shared/ldapns/ldap_version string 3" | debconf-set-selections
	echo "libpam-ldap libpam-ldap/bindpw string $ldap_bind_password" | debconf-set-selections
	echo "libpam-ldap libpam-ldap/rootbindpw string $ldap_admin_password" | debconf-set-selections
	echo "libpam-ldap libpam-ldap/dblogin boolean true" | debconf-set-selections
	echo "libpam-ldap libpam-ldap/pam_password string crypt" | debconf-set-selections
	echo "libpam-ldap libpam-ldap/rootbinddn string $ldap_admin_dn" | debconf-set-selections
	echo "libpam-ldap libpam-ldap/override boolean true" | debconf-set-selections
	echo "libpam-ldap libpam-ldap/binddn string $ldap_bind_dn" | debconf-set-selections
	echo "libpam-ldap libpam-ldap/dbrootlogin boolean true" | debconf-set-selections

else
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
fi


# Install the requires packages for LDAP PAM telling apt to ignore any interactive options
DEBIAN_FRONTEND=noninteractive apt install -y libnss-ldap libpam-ldap ldap-utils nscd


# Configure the system to use LDAP for PAM. Some versions include `auth-client-config` and others dont.
# `auth-client-config` requires python2.x, so support for it is dropping.
if which auth-client-config >/dev/null; then
	auth-client-config -t nss -p lac_ldap
else
	sed -i '/passwd/ s/$/ ldap/' /etc/nsswitch.conf
	sed -i '/group/ s/$/ ldap/' /etc/nsswitch.conf
	sed -e s/use_authtok//g -i /etc/pam.d/common-password
fi
pam-auth-update --enable ldap


# Enable the system to create home directories for LDAP users who do not have one on first login 
pam-auth-update --enable mkhomedir
echo "session required pam_mkhomedir.so skel=/etc/skel umask=077" >> /etc/pam.d/common-session


# Restart the Name Service cache daemon, unsure if this is required.
systemctl restart nscd
systemctl enable nscd


# Apply LDAP group filter for PAM LDAP login
# Different distros/versions read the filter from different places.
PAM_LDAP_filter="pam_filter &(|(memberof=cn=host_access,ou=groups,dc=theta42,dc=com)(memberof=cn=host_`hostname`_access,ou=groups,dc=theta42,dc=com))"

if grep -qiE "^NAME=\"debian" /etc/os-release; then
	echo "$PAM_LDAP_filter" >> /etc/pam_ldap.conf
else
echo "$PAM_LDAP_filter" >> /etc/ldap/ldap.conf
echo "$PAM_LDAP_filter" >> /etc/ldap.conf


## Set up sudo-ldap
apt install -y sudo-ldap
sudo_ldap_template="$(cat files/sudo-ldap.conf)"
echo "$sudo_ldap_template" | mo > /etc/sudo-ldap.conf


## Set up SSHkey via LDAP
sudo_ldap_template="$(cat files/ldap-ssh-key.sh)"
echo "$sudo_ldap_template" | mo > /usr/local/bin/ldap-ssh-key
chmod +x /usr/local/bin/ldap-ssh-key

echo "AuthorizedKeysCommand /usr/local/bin/ldap-ssh-key" >> /etc/ssh/sshd_config
echo "AuthorizedKeysCommandUser nobody" >> /etc/ssh/sshd_config

service ssh restart

exit 0
