#!/bin/bash
#Created by Russ Long, see README for further information
#This file is part of TFMM's Home Server Installation Script.

#TFMM's Home Server Installation Script is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

#TFMM's Home Server Installation Script is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

#You should have received a copy of the GNU General Public License along with TFMM's Home Server Installation Script.  If not, see <http://www.gnu.org/licenses/>.
# ©2014 Russ Long, TFMM
#Determine if OS is RedHat Based
if [ -e /etc/redhat-release ]; then

#Determine which major version of the OS is on the machine
	if [ $(cat /etc/redhat-release | cut -d" " -f4 | cut -d "." -f1) = "7" ]; then

#If Centos7, continue, else, we will fail at the end.

#Setting up Repos

#Remi
rpm -Uvh http://download.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-2.noarch.rpm

#Epel
rpm -Uvh http://rpms.famillecollet.com/enterprise/remi-release-7.rpm

#Nginx

cat > /etc/yum.repos.d/nginx.repo <<EOF
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/7/x86_64/
gpgcheck=0
enabled=1
EOF

#Create /data mountpoint
mkdir /data

#Find out what device should be mounted on the mountpoint
echo
echo -n "Which Device should be mounted at /data?  "
read var_device
echo
echo -n "$var_device will be mounted on /data"

#Add entry to fstab
echo "$var_device    /data    ext4    defaults    0    0" >> /etc/fstab

#mount the new device
mount -a

#Install NGINX, PHP-FPM, and MariaDB

yum -y install nginx php-fpm mariadb-server psmisc

yum --enablerepo=remi,remi-php55 -y install php-opcache php-pecl-apcu php-cli php-pear php-pdo php-mysqlnd php-pgsql php-pecl-mongo php-sqlite php-pecl-memcache php-pecl-memcached php-gd php-mbstring php-mcrypt php-xml

#start mariadb
systemctl start mariadb

#pull string from /dev/urandom to make a MySQL root pass
var_mysqlrootpass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

#set mariadb root pass
mysql -e "SET PASSWORD FOR 'root'@'localhost'  = PASSWORD(\"${var_mysqlrootpass}\")"

#create /root/.my.cnf to enable mysql autologins as root user
cat > /root/.my.cnf <<EOF
[client]
user=root
password=PASSHERE
EOF

#sub in the actual new root mysql pass in /root/.my.cnf
sed -i "s/^password=PASSHERE/password=$var_mysqlrootpass/" /root/.my.cnf

#Setup needed directory structure for NGINX and PHP-FPM
mkdir /etc/nginx/sites-available
mkdir /etc/nginx/sites-enabled
mkdir /home/ssl

#Generate CSR and self-signed SSL
echo -n "We will now generate an SSL CSR, Private Key, and Self-signed certificate, and store them in /home/ssl/.  Do not set a passphrase for the certificate or private key, as this will cause NGINX to not be able to restart without entering the passphrase."
echo
openssl req -out /home/ssl/CSR.csr -new -newkey rsa:2048 -nodes -keyout /home/ssl/privatekey.key
echo
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /home/ssl/privatekey.key -out /home/ssl/certificate.crt
echo
echo -n "If you wish to purchase an SSL Certificate from a known signing authority, please use the CSR in /home/ssl/CSR.csr"
echo

#Find out domain name of server
echo
echo -n "What is the Fully Qualified Domain Name of this server?  "
read var_fqdn
echo

#create NGINX files directory
mkdir -p /srv/www/$var_fqdn/public_html

#create NGINX server definition
cp ./files/nginxvhost /etc/nginx/sites-available/$var_fqdn

#replace nginxconf with included
cat ./files/nginxconf > /etc/nginx/nginx.conf

#Insert the FQDN into the nginxvhost

sed -i 's/FQDN/'$var_fqdn'/' /etc/nginx/sites-available/$var_fqdn

#symlink your new vhost to sites-enabled to let NGINX know to serve it

ln -s /etc/nginx/sites-available/$var_fqdn /etc/nginx/sites-enabled/

#Enable NGINX PHP-FPM and MariaDB so they will start on boot
systemctl enable nginx
systemctl enable php-fpm
systemctl enable mariadb

#start NGINX and php-fpm
systemctl start nginx
systemctl start php-fpm

#Allow HTTP and HTTPS through firewalld
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --reload

#SETUP OWNCLOUD
#Install unzip
yum -y install unzip

#Make a working directory in /home/temp
mkdir /home/temp

#download ownCloud
wget -P /home/temp/ https://download.owncloud.org/community/owncloud-7.0.3.zip

#Unzip ownCloud
unzip /home/temp/owncloud-7.0.3.zip -d /home/temp

#Move ownCloud files to the NGINX service directory
rsync -avHP /home/temp/owncloud/ /srv/www/$var_fqdn/public_html

#Change permissions on the new files
chown -R apache:apache /srv/www/$var_fqdn

#Setup DB for ownCloud
#ask for owncloud DB password
echo
echo -n "Please enter a password for the ownCloud Database user, you will need this password when conifguring ownCloud from the browser:  "
read var_dbpass
mysql -e "CREATE USER 'owncloud'@'localhost' IDENTIFIED BY \"${var_dbpass}\""
mysql -e "CREATE DATABASE  owncloud"
mysql -e "GRANT ALL PRIVILEGES ON owncloud.* TO 'owncloud'@'localhost' IDENTIFIED BY \"${var_dbpass}\""

#Create the ownCloud Directory on the /data partition
mkdir /data/owncloud
chown -R apache:apache /data/owncloud

#tell user to visit their server in a browser to complete ownCloud installation
echo
echo
echo -n "Now, visit $var_fqdn in your browser to complete installation and setup of ownCloud.  The database name and database username are both 'owncloud', and the database password is what you entered previously. ownCloud setup MUST be completed before proceeding!!"
echo

#make user press a key to confirm Owncloud is setup
read -p "Press any key after you have setup ownCloud in your browser... " -n1 -s

#SETUP TRANSMISSION
#Install Transmission-daemon
yum install -y transmission-daemon

#copy included systemd service file to /etc/systemd/system to overrride transmission user
cp ./files/transmissionservice /etc/systemd/system/transmission-daemon.service

#Create apache user's homedir
mkdir /usr/share/httpd
chown apache:apache /usr/share/httpd

#start, then stop transmission to create config files.
systemctl start transmission-daemon
killall transmission-daemon

#backup original conf before adding our values
cp /usr/share/httpd/.config/transmission-daemon/settings.json{,.bak}

#Ask a few necessary questions
echo -n "Please enter the desired transmission login username:  "
read var_xmituser
echo
echo -n "Please enter the desired transmission login password. (This will show as plain text, but will be hashed in the file):  "
read var_xmitpass
echo
echo -n "Please enter the ownCloud username of the account where you would like Transmission's downloads to be stored:  "
read var_ocuser
echo

#create the downloads dir for transmission inside the ownCloud storage
mkdir /data/owncloud/$var_ocuser/files/downloads

#Set var_xmitconf
var_xmitconf=/usr/share/httpd/.config/transmission-daemon/settings.json

#chown it to proper ownership
chown -R apache:apache /data/owncloud/

#adjust transmission config
sed -i "s/.*\"download-dir\".*/\ \"download\-dir\"\: \"\/data\/owncloud\/${var_ocuser}\/files\/downloads\"\,/" $var_xmitconf
sed -i "s/.*\"rpc-authentication-required\".*/\ \"rpc\-authentication\-required\"\:\ true\,/" $var_xmitconf
sed -i "s/.*\"rpc-bind-address\".*/\ \"rpc\-bind\-address\"\:\ \"0\.0\.0\.0\"\,/" $var_xmitconf
sed -i "s/.*\"rpc-enabled\".*/\ \"rpc\-enabled\"\:\ true\,/" $var_xmitconf
sed -i "s/.*\"rpc-password\".*/\ \"rpc\-password\"\:\ \"${var_xmitpass}\"\,/" $var_xmitconf
sed -i "s/.*\"rpc-port\".*/\ \"rpc\-port\"\:\ 9091\,/" $var_xmitconf
sed -i "s/.*\"rpc-url\".*/\ \"rpc\-url\"\:\ \"\/transmission\/\"\,/" $var_xmitconf
sed -i "s/.*\"rpc-username\".*/\ \"rpc\-username\"\:\ \"${var_xmituser}\"\,/" $var_xmitconf
sed -i "s/.*\"rpc-whitelist-enabled\".*/\ \"rpc\-whitelist\-enabled\"\:\ false\,/" $var_xmitconf

#start transmission, and enable it to start on boot
systemctl start transmission-daemon
systemctl enable transmission-daemon

#allow transmission's web interface through firewalld
firewall-cmd --permanent --add-port=9091/tcp
firewall-cmd --reload

#Echo message to user letting them know where to login
echo
echo -n "Transmission can now be reached at $var_fqdn:9091 in a web browser!"
echo

#SETUP PLEX
#Install Plex from rpm
rpm -Uvh https://downloads.plex.tv/plex-media-server/0.9.11.4.739-a4e710f/plexmediaserver-0.9.11.4.739-a4e710f.x86_64.rpm

#Setup Plex storage dirs in ownCloud User's directory

mkdir /data/owncloud/$var_ocuser/files/videos
mkdir /data/owncloud/$var_ocuser/files/videos/movies
mkdir /data/owncloud/$var_ocuser/files/videos/TV
mkdir /data/owncloud/$var_ocuser/files/music

#chown these dirs
chown -R apache:apache /data/owncloud

#Add plex user to the apache group, so plex can access files in owncloud
usermod -a -G apache plex

#start Plex, and set it to run on boot
systemctl start plexmediaserver
systemctl enable plexmediaserver

#allow plex through firewalld
firewall-cmd --permanent --add-port=32400/tcp
firewall-cmd --reload

#Tell user where to configure plex in browser
echo
echo -n "Plex is now able to be reached in your browser, at $var_fqdn:32400/web , see the tutorial here for more info tfmm.co/TaPw1"
echo

#SETUP CRASHPLAN
#create crashplan storage dir in /data
mkdir /data/crashplan

#fetch crashplan
wget -P /home/temp/ http://download.code42.com/installs/linux/install/CrashPlan/CrashPlan_3.6.3_Linux.tgz

#untar crashplan
tar -zxf /home/temp/CrashPlan_3.6.3_Linux.tgz -C /home/temp

#Let user know what's up
echo
echo -n "the CrashPlan install script will now run, be sure to change the backup storage directory to /data/crashplan"
echo

#run the crashplan installer
sh /home/temp/CrashPlan-install/install.sh

#allow crashplan through firewalld
firewall-cmd --permanent --add-port=4200/tcp
firewall-cmd --permanent --add-port=4242/tcp
firewall-cmd --permanent --add-port=4243/tcp
firewall-cmd --reload

#Fix no space left on device errors
echo "fs.inotify.max_user_watches=262144" >> /etc/sysctl.conf
sysctl -p

#tell user they are done
echo
echo -n "You are done!"
echo

else echo -n "This only works on CentOS7"
fi
else echo -n "This only works on CentOS"

fi
