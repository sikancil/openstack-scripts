#########################################################################################
#
#	Author. Tung Ns (tungns.inf@gmail.com)
#
#	This script will install an Openstack on Ubuntu 12.04LTS with these components:
#		- keystone
#		- glance
#		- nova : all components, nova-network uses VlanManager
#		- horizon
#	By default this script will use only single NIC eth0 if you have more than one	
#	feel free to change in the values below.
#   
#																				
#########################################################################################


#!/bin/bash

###############################################
# Change these values to fit your requirements
###############################################

IP=192.168.1.11             	# You public IP 
PUBLIC_IP_RANGE=192.168.1.64/27 # The floating IP range
PUBLIC_NIC=eth0             	# The public NIC, floating network, allow instance connect to Internet
PRIVATE_NIC=eth0            	# The private NIC, fixed network. If you have more than 2 NICs specific it ex: eth1
MYSQL_PASS=root             	# Default password of mysql-server
CLOUD_ADMIN=admin           	# Cloud admin of Openstack
CLOUD_ADMIN_PASS=password   	# Password will use to login into Dashboard later
TENANT=demoProject          	# The name of tenant (project)
REGION=RegionOne            	# You must specific it. Imagine that you have multi datacenter. Not important, just keep it by default
HYPERVISOR=qemu             	# if your machine support KVM (check by run $ kvm-ok), change QEMU to KVM
NOVA_VOLUME=/dev/sdb        	# Partition to use with nova-volume, here I have 2 HDD then it is sdb

################################################

# Check if user is root

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   echo "Please run $ sudo bash then rerun this script"
   exit 1
fi

# Create ~/openrc

cat > ~/openrc <<EOF
export OS_USERNAME=$CLOUD_ADMIN
export OS_TENANT_NAME=$TENANT
export OS_PASSWORD=$CLOUD_ADMIN_PASS
export OS_AUTH_URL=http://$IP:5000/v2.0/
export OS_REGION_NAME=$REGION
export SERVICE_ENDPOINT="http://$IP:35357/v2.0"
export SERVICE_TOKEN=012345SECRET99TOKEN012345
EOF

source ~/openrc

cat >> ~/.bashrc <<EOF
source ~/openrc
EOF

source ~/.bashrc

echo "
######################################
	Content of ~/openrc
######################################
"
cat ~/openrc
sleep 2

echo "
######################################
	Install ntp server
######################################
"
sleep 2

apt-get install -y ntp

cat >> /etc/ntp.conf <<EOF
server 127.127.1.0
fudge 127.127.1.0 stratum 10
EOF

service ntp restart

echo "
######################################
	Install Mysql Server
######################################
"
sleep 2

# Store password in /var/cache/debconf/passwords.dat

cat <<MYSQL_PRESEED | debconf-set-selections
mysql-server-5.5 mysql-server/root_password password $MYSQL_PASS
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASS
mysql-server-5.5 mysql-server/start_on_boot boolean true
MYSQL_PRESEED

apt-get -y install python-mysqldb mysql-server

sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/my.cnf
service mysql restart
sleep 1

mysql -u root -p$MYSQL_PASS -e 'CREATE DATABASE keystone_db;'
mysql -u root -p$MYSQL_PASS -e "GRANT ALL ON keystone_db.* TO 'keystone'@'%' IDENTIFIED BY 'keystone';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL ON keystone_db.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone';"

mysql -u root -p$MYSQL_PASS -e 'CREATE DATABASE glance_db;'
mysql -u root -p$MYSQL_PASS -e "GRANT ALL ON glance_db.* TO 'glance'@'%' IDENTIFIED BY 'glance';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL ON glance_db.* TO 'glance'@'localhost' IDENTIFIED BY 'glance';"

mysql -u root -p$MYSQL_PASS -e 'CREATE DATABASE nova_db;'
mysql -u root -p$MYSQL_PASS -e "GRANT ALL ON nova_db.* TO 'nova'@'%' IDENTIFIED BY 'nova';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL ON nova_db.* TO 'nova'@'localhost' IDENTIFIED BY 'nova';"

echo "
#####################################
	Install Keystone
#####################################
"
sleep 2

apt-get install -y keystone python-keystone python-keystoneclient

rm /var/lib/keystone/keystone.db

sed -i 's/admin_token = ADMIN/admin_token = 012345SECRET99TOKEN012345/g' /etc/keystone/keystone.conf
sed -i "s|connection = sqlite:////var/lib/keystone/keystone.db|connection = mysql://keystone:keystone@$IP/keystone_db|g" /etc/keystone/keystone.conf

service keystone restart
sleep 2
keystone-manage db_sync
sleep 2
service keystone restart
sleep 3

KEYSTONE_IP=$IP
SERVICE_ENDPOINT=http://$IP:35357/v2.0/
SERVICE_TOKEN=012345SECRET99TOKEN012345

NOVA_IP=$IP
VOLUME_IP=$IP
GLANCE_IP=$IP
EC2_IP=$IP

NOVA_PUBLIC_URL="http://$NOVA_IP:8774/v2/%(tenant_id)s"
NOVA_ADMIN_URL=$NOVA_PUBLIC_URL
NOVA_INTERNAL_URL=$NOVA_PUBLIC_URL

VOLUME_PUBLIC_URL="http://$VOLUME_IP:8776/v1/%(tenant_id)s"
VOLUME_ADMIN_URL=$VOLUME_PUBLIC_URL
VOLUME_INTERNAL_URL=$VOLUME_PUBLIC_URL

GLANCE_PUBLIC_URL="http://$GLANCE_IP:9292/v1"
GLANCE_ADMIN_URL=$GLANCE_PUBLIC_URL
GLANCE_INTERNAL_URL=$GLANCE_PUBLIC_URL
 
KEYSTONE_PUBLIC_URL="http://$KEYSTONE_IP:5000/v2.0"
KEYSTONE_ADMIN_URL="http://$KEYSTONE_IP:35357/v2.0"
KEYSTONE_INTERNAL_URL=$KEYSTONE_PUBLIC_URL

EC2_PUBLIC_URL="http://$EC2_IP:8773/services/Cloud"
EC2_ADMIN_URL="http://$EC2_IP:8773/services/Admin"
EC2_INTERNAL_URL=$EC2_PUBLIC_URL

# Define services

keystone service-create --name keystone --type identity --description 'OpenStack Identity Service'
keystone service-create --name nova --type compute --description 'OpenStack Compute Service' 
keystone service-create --name volume --type volume --description 'OpenStack Volume Service' 
keystone service-create --name glance --type image --description 'OpenStack Image Service'
keystone service-create --name ec2 --type ec2 --description 'EC2 Service'

# Create endpoints to these services

ID=$(keystone service-list | grep -i compute | awk '{print $2}')
keystone endpoint-create --region $REGION --service_id $ID --publicurl $NOVA_PUBLIC_URL --adminurl $NOVA_ADMIN_URL --internalurl $NOVA_INTERNAL_URL

ID=$(keystone service-list | grep -i volume | awk '{print $2}')
keystone endpoint-create --region $REGION --service_id $ID --publicurl $VOLUME_PUBLIC_URL --adminurl $VOLUME_ADMIN_URL --internalurl $VOLUME_INTERNAL_URL

ID=$(keystone service-list | grep -i identity | awk '{print $2}')
keystone endpoint-create --region $REGION --service_id $ID --publicurl $KEYSTONE_PUBLIC_URL --adminurl $KEYSTONE_ADMIN_URL --internalurl $KEYSTONE_INTERNAL_URL

ID=$(keystone service-list | grep -i image | awk '{print $2}')
keystone endpoint-create --region $REGION --service_id $ID --publicurl $GLANCE_PUBLIC_URL --adminurl $GLANCE_ADMIN_URL --internalurl $GLANCE_INTERNAL_URL

ID=$(keystone service-list | grep -i ec2 | awk '{print $2}')
keystone endpoint-create --region $REGION --service_id $ID --publicurl $EC2_PUBLIC_URL --adminurl $EC2_ADMIN_URL --internalurl $EC2_INTERNAL_URL

# Define roles, users

TENANT_ID=$(keystone tenant-create --name $TENANT | grep id | awk '{print $4}')
ADMIN_ROLE=$(keystone role-create --name Admin|grep id| awk '{print $4}')
KEYSTONE_ADMIN_ROLE=$(keystone role-create --name KeystoneServiceAdmin|grep id| awk '{print $4}')
MEMBER_ROLE=$(keystone role-create --name Member|grep id| awk '{print $4}')

keystone user-create --name $CLOUD_ADMIN --tenant_id $TENANT_ID --pass $CLOUD_ADMIN_PASS --email root@localhost --enabled true

keystone user-create --name ubuntu --tenant_id $TENANT_ID --pass password --email ubuntu@localhost --enabled true


ADMIN_USER=$(keystone user-list | grep $CLOUD_ADMIN | awk '{print $2}')

for ROLE in Admin KeystoneServiceAdmin Member
do 
ROLE_ID=$(keystone role-list | grep "\ $ROLE\ " | awk '{print $2}')
keystone user-role-add --user $ADMIN_USER --role $ROLE_ID --tenant_id $TENANT_ID
done


UBUNTU_USER=$(keystone user-list | grep ubuntu | awk '{print $2}')
	
for ROLE in Admin Member
do
ROLE_ID=$(keystone role-list | grep "\ $ROLE\ " | awk '{print $2}')
keystone user-role-add --user $UBUNTU_USER --role $ROLE_ID --tenant_id $TENANT_ID
done

echo "
####################################
	Install Glance
####################################
"
sleep 2

apt-get install -y glance glance-api glance-client glance-common glance-registry python-glance

rm /var/lib/glance/glance.sqlite

# Update /etc/glance/glance-api-paste.ini, /etc/glance/glance-registry-paste.ini

sed -i "s/%SERVICE_TENANT_NAME%/$TENANT/g" /etc/glance/glance-api-paste.ini /etc/glance/glance-registry-paste.ini
sed -i "s/%SERVICE_USER%/$CLOUD_ADMIN/g" /etc/glance/glance-api-paste.ini /etc/glance/glance-registry-paste.ini
sed -i "s/%SERVICE_PASSWORD%/$CLOUD_ADMIN_PASS/g" /etc/glance/glance-api-paste.ini /etc/glance/glance-registry-paste.ini

# Update /etc/glance/glance-registry.conf

sed -i "s|sql_connection = sqlite:////var/lib/glance/glance.sqlite|sql_connection = mysql://glance:glance@$IP/glance_db|g" /etc/glance/glance-registry.conf

# Add to the and of /etc/glance/glance-registry.conf and /etc/glance/glance-api.conf

cat >> /etc/glance/glance-registry.conf <<EOF
[paste_deploy]
flavor = keystone
EOF

cat >> /etc/glance/glance-api.conf <<EOF
[paste_deploy]
flavor = keystone
EOF

# Sync glance_db

restart glance-api
restart glance-registry

sleep 2

glance-manage version_control 0
glance-manage db_sync

sleep 2

restart glance-api
restart glance-registry

echo "
#####################################
	Install Nova
#####################################
"
sleep 1

# Check to install nova-compute-kvm or nova-compute-qemu

if [ $HYPERVISOR == "qemu" ]; then
	apt-get -y install nova-compute nova-compute-qemu
else
	apt-get -y install nova-compute nova-compute-kvm
fi

apt-get install -y nova-api nova-cert nova-doc nova-network nova-objectstore nova-scheduler nova-volume rabbitmq-server nova-consoleauth nova-common novnc

# Change owner and permission for /etc/nova/

chown -R nova:nova /etc/nova
chmod 644 /etc/nova/*

# Update /etc/nova/api-paste.ini

sed -i "s/127.0.0.1/$IP/g" /etc/nova/api-paste.ini
sed -i "s/%SERVICE_TENANT_NAME%/$TENANT/g" /etc/nova/api-paste.ini
sed -i "s/%SERVICE_USER%/$CLOUD_ADMIN/g" /etc/nova/api-paste.ini
sed -i "s/%SERVICE_PASSWORD%/$CLOUD_ADMIN_PASS/g" /etc/nova/api-paste.ini

# Update hypervisor in nova-compute.conf

if [ $HYPERVISOR == "qemu" ]; then
	sed -i 's/kvm/qemu/g' /etc/nova/nova-compute.conf
fi

# Update nova.conf

cat > /etc/nova/nova.conf <<EOF
#=rabbitmq
--rabbit_host=$IP

#=mysql
--sql_connection=mysql://nova:nova@$IP/nova_db

#=nova-api
--auth_strategy=keystone
--cc_host=$IP

#=nova-network
--network_manager=nova.network.manager.VlanManager
--public_interface=$PUBLIC_NIC
--vlan_interface=$PRIVATE_NIC
--fixed_range=10.0.0.0/8
--network_size=1024
--dhcpbridge_flagfile=/etc/nova/nova.conf
--dhcpbridge=/usr/bin/nova-dhcpbridge
--force_dhcp_release=True
--fixed_ip_disassociate_timeout=30
--ec2_url=http://$IP:8773/services/Cloud
--ec2_dmz_host=$IP
#--multi_host=True

#=nova-compute
--connection_type=libvirt
--libvirt_type=$HYPERVISOR
--libvirt_use_virtio_for_bridges=True
--use_cow_images=True
--snapshot_image_format=qcow2

#=nova-volume
--iscsi_ip_prefix=$IP
--num_targets=100
--iscsi_helper=tgtadm

#=glance
--image_service=nova.image.glance.GlanceImageService
--glance_api_servers=$IP:9292

#=vnc
--novnc_enabled=true
--novncproxy_base_url=http://$IP:6080/vnc_auto.html
--vncserver_proxyclient_address=$IP
--vncserver_listen=$IP

#=misc
--logdir=/var/log/nova
--state_path=/var/lib/nova
--lock_path=/var/lock/nova
--root_helper= nova-rootwrap
--root_helper=sudo nova-rootwrap
--verbose=False
EOF

# Config nova-volume

vgremove nova-volumes $NOVA_VOLUME # just for sure, if the 1st time this script failed, then rerun...

pvcreate -ff -y $NOVA_VOLUME # if rerun the script we need force option
vgcreate nova-volumes $NOVA_VOLUME

cat > ~/nova_restart <<EOF
sudo restart libvirt-bin
sudo /etc/init.d/rabbitmq-server restart
for i in nova-network nova-compute nova-api nova-objectstore nova-scheduler nova-volume nova-consoleauth nova-cert
do
sudo service "\$i" restart # need \ before $ to make it a normal charactor not variable
done
EOF

chmod +x ~/nova_restart

# Sync nova_db

~/nova_restart
sleep 2
nova-manage db sync
sleep 3
~/nova_restart
sleep 3
nova-manage service list

# Create fixed and floating ips

nova-manage network create --label vlan1 --fixed_range_v4 10.0.1.0/24 --num_networks 1 --network_size 256 --vlan 1 #--multi_host=T

nova-manage floating create --ip_range $PUBLIC_IP_RANGE

# Define security rules

nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0 
nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
nova secgroup-add-rule default tcp 80 80 0.0.0.0/0

# Create key pair

mkdir ~/key
cd ~/key
nova keypair-add mykeypair > mykeypair.pem
chmod 600 mykeypair.pem
cd

echo "
#####################################
	Install Horizon
#####################################
"
sleep 1

apt-get -y install openstack-dashboard

service apache2 restart

echo "
#################################################################
#
#    Now you can open your browser and enter IP $IP
#    Login with your user/password $CLOUD_ADMIN:$CLOUD_ADMIN_PASS
#    Enjoy!
#
#################################################################"

#===END===#
