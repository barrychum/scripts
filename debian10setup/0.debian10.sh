#!/bin/bash

timestamp=$(date +"%Y-%m-%d_%H-%M-%S")

add_change_log_label() {
    if [ -z "$(grep -R '## Change log ##' $1)" ]
    then
        rand=$(openssl rand -hex 4)
#        rand=$(shuf -zer -n10 {A..Z} {a..z} {0..9})
        cat $1 | sed -e "\$a|## Change log ##" | tr '|##' '\n##' > /tmp/outfile.$rand
        mv /tmp/outfile.$rand $1
    fi
}

mask2cdr ()
{
   # Assumes there's no "255." after a non-255 byte in the mask
   local x=${1##*255.}
   set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1} - ${#x})*2 )) ${x%%.*}
   x=${1%%$3*}
   echo $(( $2 + (${#x}/4) ))
}


cdr2mask ()
{
   # Number of args to shift, 255..255, first non-255 byte, zeroes
   set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
   [ $1 -gt 1 ] && shift $1 || shift
   echo ${1-0}.${2-0}.${3-0}.${4-0}
}


################# edit network interfaces
file=/etc/network/interfaces
s=($(ip r | grep default))
ifa=${s[4]}
defaultroute=${s[2]}

echo "Enter interface name to modify, or press enter to set default \"$ifa\""
read ifname

if [ -z "$ifname"]
then
    ifname=$ifa
fi
echo "Setting interface $ifname"

t=($(ip r | grep $ifname | grep src))
b=($(echo ${t[0]} | awk '{split($0,a,"/");print a[2]}'))
c=($(cdr2mask $b))

if [ -z "$(grep -R 'changed interface' $file)" ]
then
    # https://stackoverflow.com/questions/7815989/need-to-break-ip-address-stored-in-bash-variable-into-octets
    echo "Please enter new IP"
    read ip

    IFS=. read ip1 ip2 ip3 ip4 <<< "$ip"
    # if=ens192

    # dns server is configured in /etc/resolv.conf
    # sed -i -e "/iface $ifname inet dhcp/ a dns-nameservers $ip1.$ip2.$ip3.1" $file
    # sed -i -e "/iface $ifname inet dhcp/ a dns-domain home.arpa" $file
    # sed -i -e "/iface $ifname inet dhcp/ a gateway $ip1.$ip2.$ip3.1" $file
    # sed -i -e "/iface $ifname inet dhcp/ a netmask 255.255.255.0" $file

    sed -i -e "/iface $ifname inet dhcp/ a gateway $defaultroute" $file
    sed -i -e "/iface $ifname inet dhcp/ a netmask $c" $file
    sed -i -e "/iface $ifname inet dhcp/ a address $ip" $file
    sed -i -e "s/iface $ifname inet dhcp/iface $ifname inet static/g" $file

    ip addr flush $ifname && systemctl restart networking
    # ifdown $ifname &&  ifup $ifname
    ifup $ifname

    add_change_log_label $file
    sed -i -e "/## Change log ##/ a # $timestamp *changed interface*" $file
fi

##################### disable ipv6
# if grep -Fxq "ipv6" /etc/sysctl.conf
file2=/etc/sysctl.conf
if [ -z "$(grep -R '*ipv6disabled*' $file2)" ]
then
  sed -i -e "\$anet.ipv6.conf.$ifname.disable_ipv6=1" $file2
  sed -i -e "\$anet.ipv6.conf.lo.disable_ipv6=1" $file2
  sed -i -e "\$anet.ipv6.conf.default.disable_ipv6=1" $file2
  sed -i -e "\$anet.ipv6.conf.all.disable_ipv6=1" $file2
  sed -i -e "\$a#ipv6disabled" $file2

  sysctl -p

  add_change_log_label $file2
  sed -i -e "/## Change log ##/ a # $timestamp *ipv6disabled*" $file2
fi

###################### enable remote ssh
file3=/etc/ssh/sshd_config
if [ -z "$(grep -R '*PermitRootLoginChanged*' $file3)" ]
then
  sed -i -e "/#PermitRootLogin/ a PermitRootLogin yes" $file3

  add_change_log_label $file3
  sed -i -e "/## Change log ##/ a # $timestamp *PermitRootLoginChanged*" $file3

  systemctl restart sshd
fi

