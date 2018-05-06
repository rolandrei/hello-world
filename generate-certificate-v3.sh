#!/bin/bash

if [ `id | sed -e s/uid=//g -e s/\(.*//g` -ne 0 ]; then
  echo "Error: This script requires root privileges to run, please run it using admin privileges." >&2
  exit 5
fi

usage() {
    echo "Bitnami script to generate the SSL certificates and configure the web server."
    echo
    echo "Usage: $0"
    echo "  -h --help"
    echo "  -m your_email"
    echo "  -d your_domain"
    echo "  -s your_secondary_domain (optional)"
    echo
    exit 0
}

documentation_support_message() {
    documentation_url="https://docs.bitnami.com/"
    support_url="https://community.bitnami.com/"
    echo  >&2
    echo "Please check our documentation or open a ticket in our community forum, our team will be more than happy to help you!" >&2
    echo "Documentation: $documentation_url" >&2
    echo "Support: $support_url" >&2
    echo  >&2
}

accept() {
    while true; do
        read -p "" yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit 2;;
            * ) echo "Please answer yes [y] or no [n].";;
        esac
    done
}

stop_server() {
    if [ -d "/opt/bitnami/apache2" ]; then
        /opt/bitnami/ctlscript.sh stop apache
    else
        /opt/bitnami/ctlscript.sh stop nginx
    fi
}

start_server() {
    if [ -d "/opt/bitnami/apache2" ]; then
        /opt/bitnami/ctlscript.sh start apache
    else
        /opt/bitnami/ctlscript.sh start nginx
    fi
}

restart_server() {
    if [ -d "/opt/bitnami/apache2" ]; then
        /opt/bitnami/ctlscript.sh restart apache
    else
        /opt/bitnami/ctlscript.sh restart nginx
    fi
}

backup_configuration() {
    if [ -d "/opt/bitnami/apache2" ]; then
        cp -rp /opt/bitnami/apache2/conf/bitnami/bitnami.conf{,.back}
    else
        cp -rp /opt/bitnami/nginx/conf/bitnami/bitnami.conf{,.back}
    fi
}

modify_configuration() {
    if [ -d "/opt/bitnami/apache2" ]; then
        sed -i "s;\s*SSLCertificateFile\s.*;  SSLCertificateFile \"/opt/bitnami/apache2/conf/${domain}.crt\";g" /opt/bitnami/apache2/conf/bitnami/bitnami.conf
        sed -i "s;\s*SSLCertificateKeyFile\s.*;  SSLCertificateKeyFile \"/opt/bitnami/apache2/conf/${domain}.key\";g" /opt/bitnami/apache2/conf/bitnami/bitnami.conf
    else
        sed -i "s;\s*ssl_certificate\s.*;\tssl_certificate\t${domain}.crt\;;g" /opt/bitnami/nginx/conf/bitnami/bitnami.conf
        sed -i "s;\s*ssl_certificate_key\s.*;\tssl_certificate_key\t${domain}.key\;;g" /opt/bitnami/nginx/conf/bitnami/bitnami.conf
    fi
}
restore_configuration() {
    if [ -d "/opt/bitnami/apache2" ]; then
        echo
        echo "We are going to try to recover the Apache configuration now..."
        echo
        if [ -e "/opt/bitnami/apache2/conf/bitnami/bitnami.conf.back" ]; then
            cp -rp /opt/bitnami/apache2/conf/bitnami/bitnami.conf{.back,}
        fi
        restart_server
    else
        echo
        echo "We are going to try to recover the Nginx configuration now..."
        echo
        if [ -e "/opt/bitnami/nginx/conf/bitnami/bitnami.conf.back" ]; then
            cp -rp /opt/bitnami/nginx/conf/bitnami/bitnami.conf{.back,}
        fi
        restart_server
    fi
}

create_certificate_symlink() {
    if [ -d "/opt/bitnami/apache2" ]; then
        ln -s /opt/bitnami/letsencrypt/certificates/${domain}.crt /opt/bitnami/apache2/conf/
        ln -s /opt/bitnami/letsencrypt/certificates/${domain}.key /opt/bitnami/apache2/conf/
    else
        ln -s /opt/bitnami/letsencrypt/certificates/${domain}.crt /opt/bitnami/nginx/conf/
        ln -s /opt/bitnami/letsencrypt/certificates/${domain}.key /opt/bitnami/nginx/conf/
    fi
}

configure_crontab() {
    ##Check if the bitnami user exists. If the user exists,
    ##this command will return an exit code equal to 0
    set +e
    id -u bitnami > /dev/null 2>&1
    ec=$?
    set -e
    if [ $ec -eq 0 ]; then
        USER="-u bitnami"
        SUDO="sudo"
    else
        USER=""
        SUDO=""
    fi

    set +e
    crontab $USER -l 2> /dev/null | grep "/opt/bitnami/letsencrypt/lego" > /dev/null 2>&1
    ec=$?
    set -e
    if [ $ec -eq 0 ]; then
        echo
        echo "It seems that there is already at least one job to renew the certificates in cron. This can affect the security of the application."
        echo "As you are configuring new certificates, we suggest you removing it automatically now, do you want to do it? [y/n]"
        while true; do
            read -p "" yn
            case $yn in
                [Yy]* )
                    crontab $USER -l | grep -v '/opt/bitnami/letsencrypt/lego'  | crontab $USER -
                    break
                    ;;
                [Nn]* )
                    documentation_support_message
                    break
                    ;;
                * ) echo "Please answer yes [y] or no [n].";;
            esac
        done
    fi

    if [ -d "/opt/bitnami/apache2" ]; then
        crontab $USER -l 2> /dev/null | { cat; echo "0 0 1 * * $SUDO /opt/bitnami/letsencrypt/lego --path=\"/opt/bitnami/letsencrypt\" --email=\"${email}\" --domains=\"${domain}\" --domains=\"${domain2}\" renew && $SUDO /opt/bitnami/apache2/bin/httpd -f /opt/bitnami/apache2/conf/httpd.conf -k graceful"; } | crontab $USER - 2> /dev/null
    else
        crontab $USER -l 2> /dev/null | { cat; echo "0 0 1 * * $SUDO /opt/bitnami/letsencrypt/lego --path=\"/opt/bitnami/letsencrypt\" --email=\"${email}\" --domains=\"${domain}\" --domains=\"${domain2}\" renew && $SUDO /opt/bitnami/nginx/sbin/nginx -s reload"; } | crontab $USER - 2> /dev/null
    fi
}

cleanup() {
    echo  >&2
    echo "Error: Something went wrong when running the following command:" >&2
    echo  >&2
    echo " \$ ${previous_command}" >&2
    echo  >&2
    documentation_support_message
    restore_configuration
    exit 1
}

enable_exit_trap() {
    set -e
    trap 'cleanup' EXIT
}

disable_exit_trap() {
    set +e
    trap - EXIT
}

trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG

while getopts "hm::d:s:" o; do
    case "${o}" in
        m)
            email=${OPTARG} ;;
        d)
            domain=${OPTARG} ;;
	s)
	    domain2=${OPTARG} ;;
        h)
            usage ;;
    esac
done
if [ -z "${email}" ] || [ -z "${domain}" ] ; then
    usage
fi

echo "This tool will now stop the web server and configure the required SSL certificate. It will also start it again once finished."
echo "It will create a certificate for the domain \"${domain},${domain2}}\" under the email \"${email}\". Do you want to continue? [y/n]"

accept

enable_exit_trap
backup_configuration
stop_server

# Generate certificate with the provided information
/opt/bitnami/letsencrypt/lego --path "/opt/bitnami/letsencrypt" --email="${email}" --domains="${domain}" --domains="${domain2}" run

# Configure WordPress with the provided domain
/opt/bitnami/apps/wordpress/bnconfig --machine_hostname ${domain}
disable_exit_trap

# Modify the permissions of the generated certificate
if [ ! -e "/opt/bitnami/letsencrypt/certificates/${domain}.crt" ]; then
    echo "Error: Something went wrong when creating the certificates and there is not any valid one in the \"/opt/bitnami/letsencrypt/.lego/certificates/\" folder" >&2
    documentation_support_message
    restore_configuration
    exit 3
fi

enable_exit_trap
chmod a+rx /opt/bitnami/letsencrypt/certificates
chmod a+r /opt/bitnami/letsencrypt/certificates/${domain}{.crt,.key}
disable_exit_trap

# Create links to the certificate
if [ -e "/opt/bitnami/apache2/conf/${domain}.crt" ] || [ -e "/opt/bitnami/apache2/conf/${domain}.key" ] ||
   [ -e "/opt/bitnami/nginx/conf/${domain}.crt" ] || [ -e "/opt/bitnami/nginx/conf/${domain}.key" ]; then
    echo "Error: It seems there is a valid certificate in the web server configuration folder. Please renew that certificate or generate new ones manually" >&2
    documentation_support_message
    restore_configuration
    exit 4
fi

enable_exit_trap
create_certificate_symlink

# Modify the web server configuration and start it again
modify_configuration
start_server
disable_exit_trap

# Configure the cronjob to renew the certificate every month

echo "Congratulations, the generation and configuration of your SSL certificate finished properly."
echo "You can now configure a cronjob to renew it every month. Do you want to proceed? [y/n]"

accept

enable_exit_trap
configure_crontab
disable_exit_trap
