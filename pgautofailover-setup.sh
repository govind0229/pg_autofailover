#!/bin/bash
#################################################################
#   Script for setup pgautofailover with pg_autoctl extention   #
#   Editor: Govind Sharma <govind.sharma@flexydial.com>         #
#################################################################
HOST_IP=$(ip route get 1 | sed 's/^.*src \([^ ]*\).*$/\1/;q')
PGPath='/var/lib/pgsql/'
filePath='/etc/environment'
pgautoctlpath=$(find /usr/ -type f -name 'pg_autoctl' -print | sed 's/pg_autoctl//g')

function install(){
   
   #checking available packages
   PG=$(dnf search pg-auto-failover | grep pg-auto-failover | awk 'NR>2 {print $1}');
   
   if [[ -z "${PG}" ]]; then

       curl https://install.citusdata.com/community/rpm.sh | sudo bash
   
   fi
   
    select pg in ${PG};
    do
        if [[ -z "${pg}" ]]; then
            echo "empty"
        else
            dnf -y install ${pg};
            break;
        fi
    done
}

function monitor(){

  URI=$(sudo -u postgres ${pgautoctlpath}pg_autoctl show uri | grep monitor | awk '{print $5}')
  
  if [[ -z "${URI}" ]]; then
        echo "empty string"
        rm -rvf ${PGPath}/* ${PGPath}.config &>/dev/null

        #setup PGDATA Env
        if [ -d "${PGPath}" ]; then
            echo "directory \"${PGPath}\" exists"
        else 
            echo "drectory creating"   
            install -d ${PGPath}
            chown -R postgres:postgres ${PGPath}
        fi

        if [ -s "${filePath}" ]; then
            echo "File \"${filePath}\" is not empty"
        else
            echo PGDATA="${PGPath}monitor" | tee -a ${filePath}
            source ${filePath}
        fi
  
        echo '-------------------------------------------------'; 
        echo '    Monitor intance installation in progress...' 
        echo '-------------------------------------------------';

        #Create monitor database intence 
        sudo -u postgres ${pgautoctlpath}pg_autoctl  create monitor --auth trust --ssl-self-signed --pgdata ${PGPath}monitor --hostname ${HOST_IP} --pgctl ${pgautoctlpath}pg_ctl
        
        #Create pgautodialover service file
        sudo -u postgres ${pgautoctlpath}pg_autoctl -q show systemd --pgdata ${PGPath}monitor | tee /etc/systemd/system/pgautofailover.service &>/dev/null
        
        #start pgautofailover server
        systemctl daemon-reload
        systemctl start pgautofailover
        
        echo '-------------------------------------------------'; 
        echo '    PG autofailover monitor setup completed!'
        echo '-------------------------------------------------';
        exit 0;
  else
      echo "Monitor is already exists: ${URI}"
  fi   
       
}

function uri(){
    sudo -u postgres ${pgautoctlpath}pg_autoctl show uri | grep monitor | awk '{print $5}'
}

function state(){

    sudo -u postgres ${pgautoctlpath}pg_autoctl show state
}

function postgres(){

    if [ $(ps aux | grep postgres | wc -l) -gt 0 ]; then
        
        #setup required environment

        read -p 'Enter monitor IPadress: ' monitor
        
        declare URI2=postgres://autoctl_node@${monitor}:5432/pg_auto_failover?sslmode=require;
        echo ${URI2} | tee -a ${filePath}
        echo PGDATA="${PGPath}postgres" | tee -a ${filePath}
        source ${filePath}

        #postgres intance setup

        echo '-------------------------------------------------'; 
        echo '    Postgres intance installation in progress...' 
        echo '-------------------------------------------------';

        sudo -u postgres ${pgautoctlpath}pg_autoctl create postgres --auth trust --ssl-self-signed --pgdata=${PGDATA} --hostname ${HOST_IP} --monitor $URI2 --pgctl ${pgautoctlpath}pg_ctl

        #Create pgautodialover service file
        sudo -u postgres ${pgautoctlpath}pg_autoctl -q show systemd --pgdata ${PGPath}postgres | tee /etc/systemd/system/pgautofailover.service &>/dev/null

        #start pgautofailover server
        systemctl daemon-reload
        systemctl start pgautofailover

        echo '-------------------------------------------------'; 
        echo '    PG autofailover postgres setup completed!'
        echo '-------------------------------------------------';
        return
    else

       echo 'pgautoctl is already running'
    fi
}

function nodes(){

        echo '';
        echo 'Nodes details';

        sudo -u postgres ${pgautoctlpath}pg_autoctl show state
        
        echo ''
        echo 'Nodes options'
        
        nodes=$(sudo -u postgres ${pgautoctlpath}pg_autoctl show state | awk 'NR>2 {print $1}')
        select node in $nodes
        do
            sudo -u postgres ${pgautoctlpath}pg_autoctl drop node --name $node --force
            break;
        done
        break;
}

function delete (){

    systemctl stop pgautofailover &>/dev/null
    rm -rvf ${PGPath}/* ${PGPath}.config ${PGPath}.local &>/dev/null
    systemctl unmask pgautofailover.service &>/dev/null
    cp -f /dev/null ${filePath}
    
    echo ''
    echo 'Node deleted successfully!'
    echo ''
    exit 0;
}

function firewall(){

        systemctl restart firewalld.service
        firewall-cmd --add-port=5432/tcp --permanent
        firewall-cmd --add-port=5432/udp --permanent
        firewall-cmd --reload
}

function md5(){

    #adding entery for allow flexydial connect with md5

    read -p "Do you want to add md5, please enter [y/n]: " ans
    case $ans in
        y )
         echo "host    all             all             all                     md5" >> ${PGPath}postgres/pg_hba.conf;
         echo  "successfully";;
        n )
        break;;
    esac
}

echo '';
PS3="Please Enter Number: "

echo -e 'Installation available options:\n'

select type in 'install pg_autoctl rpm' 'monitor node create' 'postgres node create' 'uri check' 'state check' 'nodes delete' 'delete installed pg' 'firewall enable port 5432' 'md5 enable for flexydial'
do 
    if [[ -n "${type}" ]]; then
        ${type}
    else
       echo 'Invalid selection!'
       exit 0;
    fi
done