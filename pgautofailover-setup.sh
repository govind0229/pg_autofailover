#!/bin/bash
#################################################################
#   Script for setup pgautofailover with pg_autoctl extention   #
#   Author: Govind Sharma <govind_sharma@live.com>              #
#################################################################
# Colors
C='\033[0m'
R='\033[0;31m'          
G='\033[0;32m'        
Y='\033[0;33m'


HOST_IP=$(ip route get 1 | sed 's/^.*src \([^ ]*\).*$/\1/;q')
PGPath='/var/lib/pgsql/'
filePath='/etc/environment'
pgautoctlpath=$(find /usr/ -type f -name 'pg_autoctl' -print | sed 's/pg_autoctl//g')

echo '-------------------------------------------------'
echo -e "${Y}Pg_auto_failover Installation Script${C}"
echo -e '-------------------------------------------------\n'

function Install(){
   
    #checking available packages
    PG=$(dnf search pg-auto-failover | grep pg-auto-failover | awk 'NR>2 {print $1}');
    
    if [[ -z "${PG}" ]]; then

        echo -e "${Y}Citusdata.com repo installation in process...${C}" 
        curl https://install.citusdata.com/community/rpm.sh | sudo bash  
        echo -e "${G}Citusdata repo set up successfully!${C}"
        Install
    fi
    
    check_package=$(dnf list installed | grep pg-auto-failover | grep -v grep | awk '{print $1}');

    if [[ -z "${check_package}" ]]; then
        echo ''
        echo -e "${Y}Available packages list${R}!${C}"
        select pg in ${PG};
        do
            if [[ -z "${pg}" ]]; then
                echo -e "${R}Invalid selection!${C}"
            else
                dnf -y install ${pg};
                break;
            fi
        done
    else

       echo -e "Package ${R}${check_package}${C} is already installed."
       break;
    fi
          
}

function monitor(){

    #Check pg-auto-failover package installed status
    Install 
    pgautoctlpath=$(find /usr/ -type f -name 'pg_autoctl' -print | sed 's/pg_autoctl//g')
    #echo "${pgautoctlpath}"

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
        
        firewall &>/dev/null

        echo -e "${Y}Monitor HA node installation in progress...${C}"
	
        #Create monitor database intence 
        sudo -u postgres ${pgautoctlpath}pg_autoctl  create monitor --auth trust --ssl-self-signed --pgdata ${PGPath}monitor --hostname ${HOST_IP} --pgctl ${pgautoctlpath}pg_ctl 
        
        #Create pgautodialover service file
        sudo -u postgres ${pgautoctlpath}pg_autoctl -q show systemd --pgdata ${PGPath}monitor | tee /etc/systemd/system/pgautofailover.service &>/dev/null
        
        #start pgautofailover server
        systemctl daemon-reload
        systemctl start pgautofailover
        
        echo -e "${G}PG autofailover monitor setup completed!${C}"
        exit 0;
  else
      echo -e "${G}Monitor is already exists:${C} ${URI}"
  fi    
}

function uri(){
    sudo -u postgres ${pgautoctlpath}pg_autoctl show uri | grep monitor | awk '{print $5}'
}

function state(){

    sudo -u postgres ${pgautoctlpath}pg_autoctl show state
}

function postgres(){

    #Check pg-auto-failover package installed status
    Install
    pgautoctlpath=$(find /usr/ -type f -name 'pg_autoctl' -print | sed 's/pg_autoctl//g')
    #echo "${pgautctlpath}"

    if (( $(ps aux | grep pg_autoctl | grep -v grep | wc -l) == 0 )); then
        
        #setup required environment.
        read -p "Enter monitor IP Adress: " monitor
        
        declare URI2=postgres://autoctl_node@${monitor}:5432/pg_auto_failover?sslmode=require;
        echo "URI2=${URI2}" | tee -a ${filePath}
        echo "PGDATA=${PGPath}postgres" | tee -a ${filePath}
	source ${filePath}
		
	#setup PGDATA Env
        if [ -d "${PGPath}" ]; then
            echo "directory \"${PGPath}\" exists"
        else
            echo "drectory creating"
            install -d ${PGPath}
            chown -R postgres:postgres ${PGPath}
        fi

        firewall &>/dev/null
        #postgres HA node setup
        echo -e "${Y}Postgres HA node installation in progress...${C}"
        
        sudo -u postgres ${pgautoctlpath}pg_autoctl create postgres --auth trust --ssl-self-signed --pgdata=${PGDATA} --hostname ${HOST_IP} --monitor $URI2 --pgctl ${pgautoctlpath}pg_ctl 

        #Create pgautodialover service file
        sudo -u postgres ${pgautoctlpath}pg_autoctl -q show systemd --pgdata ${PGPath}postgres | tee /etc/systemd/system/pgautofailover.service &>/dev/null

        #start pgautofailover server
        systemctl daemon-reload
        systemctl start pgautofailover
         
        echo -e "${G}PG autofailover postgres setup completed!${C}"
        
        return
    else

       echo  -e "${G}Pg_autoctl is already running${C}"
    fi
}

function nodes(){

  if [ -d "${PGPath}monitor" ]; then
        echo '';
        echo -e "${Y}Nodes details${C}";

        sudo -u postgres ${pgautoctlpath}pg_autoctl show state
        
        echo ''
        echo -e "${Y}Nodes options${C}"
        
        nodes=$(sudo -u postgres ${pgautoctlpath}pg_autoctl show state | awk 'NR>2 {print $1}')
        select node in $nodes
        do
            sudo -u postgres ${pgautoctlpath}pg_autoctl drop node --name $node --force &>/dev/null
            echo -e "${R}${node} ${G}successfully deleted${R}!${C}"
            break;
        done
        break;
    else
        echo -e "${G}INFO: ${C}To drop any node, please use this command from the monitor node itself."
    fi 
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

    #adding entery for allow apps connect with md5

    read -p "Do you want to add md5, please enter [y/n]: " ans
    case $ans in
        y )
         echo "host    all             all             all                     md5" >> ${PGPath}postgres/pg_hba.conf;
         echo  "successfully";;
        n )
        break;;
    esac
}


PS3="Please Enter Number: "

echo -e "${Y}Installation available options!${C}"

select type in 'Install pg_autoctl rpm' 'monitor node create' 'postgres node create' 'uri check' 'state check' 'nodes delete' 'delete installed pg instance' 'firewall enable port 5432' 'md5 enable for flexydial'
do 
    if [[ -n "${type}" ]]; then
        ${type}
    else
       echo -e "${R}Invalid selection!${C}"
       exit 0;
    fi
done
