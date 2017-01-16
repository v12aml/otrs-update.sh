#!/bin/bash


if [[ ! $# -eq "1" ]]
then
    echo "USAGE: $0 NEW_OTRS_VERSION"
    echo "example: $0 5.0.15"
    exit 1
fi


NEW_VERSION=$1


echo "Checking current installation..."
if [[ -L /opt/otrs ]]
then
    INSTALLED_VERSION=`stat -c %N /opt/otrs | grep -oE '[[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*'`
    echo "Installed version: ${INSTALLED_VERSION}"
    echo "Requested version: ${NEW_VERSION}"
else
    echo "OTRS does not installed"
    exit 1
fi


TMP_DIR=`mktemp`
cd ${TMP_DIR}


echo "Downloading"
wget http://ftp.otrs.org/pub/otrs/otrs-${NEW_VERSION}.tar.bz2
if [[ ! $? -eq "0" ]]
then
    echo "Can't download requested version"
    rm -rf ${TMP_DIR}
    exit 1
fi


echo "Extracting..."
tar -jxvf otrs-${NEW_VERSION}.tar.bz2  -C /opt/


echo "Stoping services..."
systemctl stop cron.service postfix.service apache2.service

cd /opt/otrs-${INSTALLED_VERSION}
bin/Cron.sh stop
bin/otrs.Scheduler.pl -a stop
bin/otrs.Daemon.pl stop


echo "Copying configs and other stuff..."
cp ./Kernel/Config.pm /opt/otrs-${NEW_VERSION}/Kernel/
cp ./Kernel/Config/GenericAgent.pm /opt/otrs-${NEW_VERSION}/Kernel/Config/
cp ./Kernel/Config/Files/ZZZAuto.pm /opt/otrs-${NEW_VERSION}/Kernel/Config/Files/
cp ./var/log/TicketCounter.log /opt/otrs-${NEW_VERSION}/var/log/TicketCounter.log


echo "Setting permissions..."
cd /opt/otrs-${NEW_VERSION}/
bin/otrs.SetPermissions.pl --otrs-user=otrs --web-group=www-data


echo "Linking..."
cd /opt
rm -f /opt/otrs
ln -sf otrs-${NEW_VERSION} otrs
chown -R otrs /opt/otrs/otrs-${NEW_VERSION}


echo "Migrating..."
cd /opt/otrs
bin/otrs.CheckModules.pl
su -c "scripts/DBUpdate-to-5.pl" -s /bin/bash otrs
su -c "bin/otrs.Console.pl Maint::Database::Check" -s /bin/bash otrs
su -c "bin/otrs.Console.pl Maint::Config::Rebuild" -s /bin/bash otrs
su -c "bin/otrs.Console.pl Maint::Cache::Delete" -s /bin/bash otrs


echo "Starting up..."
systemctl start cron.service postfix.service apache2.service
su -c "bin/otrs.Daemon.pl start" -s /bin/bash otrs


echo "Activating cron..."
cd /opt/otrs/var/cron
for foo in *.dist
do
    cp $foo `basename $foo .dist`
done
su -c "bin/Cron.sh start" -s /bin/bash otrs
cd /opt/otrs/
su -c "bin/otrs.Console.pl Maint::Registration::UpdateSend --force" -s /bin/bash otrs
su -c "bin/otrs.Console.pl Maint::Cache::Delete" -s /bin/bash otrs
su -c "perl -cw /opt/otrs/bin/cgi-bin/index.pl" -s /bin/bash otrs
su -c "perl -cw /opt/otrs/bin/cgi-bin/customer.pl" -s /bin/bash otrs
su -c "perl -cw /opt/otrs/bin/otrs.Console.pl" -s /bin/bash otrs


echo "Cleaning up..."
rm -rf ${TMP_DIR}
echo "Finished."


#EOF
