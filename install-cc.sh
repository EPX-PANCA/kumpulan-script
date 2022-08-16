#!/usr/bin/env bash

# vim:foldmarker={,}
# vim:foldmethod=marker
# vim: ts=4 sw=4 et

#
# ClusterControl is a management and monitoring application for your database infrastructure.
# The installation script installs the frontend, backend and a LAMP stack.
#

ask() {
    if [[ ! -z $PROMPT_USER ]]; then
        read -p "$1" x
        [[ -z "$x" ]] || [[ "$x" == ["$2${2^^}"] ]] && return 0

        return 1
    else
        # always return true when prompt user is off
        return 0
    fi
}

ask_p() {
    [[ ! -z $S9S_CMON_PASSWORD ]] && return 0
    read -p "$1" x
    [[ -z "$x" ]] || [[ "$x" == ["$2${2^^}"] ]] && return 0

    return 1
}

confirm() {
    read -p "$1" x
    [[ -z "$x" ]] || [[ "$x" == ["$2${2^^}"] ]] && return 0

    return 1
}

ask_generic_distro() {
    PS3="Please select a generic distribution or exit the installation: "
    #options=("redhat" "suse" "debian" "exit")
    options=("redhat" "debian" "exit")
    select opt in "${options[@]}"
    do
        case $opt in
            "redhat")
                dist="redhat"
                break
                ;;
            #"suse")
                #    dist="suse"
                #    break
                #    ;;
            "debian")
                dist="debian"
                break
                ;;
            "exit")
                exit 1
                ;;
            *) echo invalid option;;
        esac
    done
}

do_lsb() {
    os_codename=$(lsb_release -sc)
    os_release=$(lsb_release -rs)
    if [[ -f /etc/centos-release || -f /etc/redhat-release ]]; then
        $(echo $os_release | grep -q "7.")
        [[ $? -eq 0 ]] && rhel_version=7
        $(echo $os_release | grep -q "8.")
        [[ $? -eq 0 ]] && rhel_version=8

        [[ -f /etc/centos-release ]] && CENTOS=1
        [[ -f /etc/oracle-release ]] && ORACLE=1 && yum install -y oraclelinux-release-el${rhel_version}
    fi

    lsb=$(lsb_release -d)
    [[ $lsb =~ $regex_lsb ]] && dist=${BASH_REMATCH[1]} ; return 0
    return 1
}

do_release_file() {
    etc_files=$(ls /etc/*[-_]{release,version} 2>/dev/null)
    for file in $etc_files; do
        # /etc/SuSE-release is deprecated and will be removed in the future, use /etc/os-release instead
        if [[ $file == "/etc/os-release" ]]; then
            continue
        fi
        if [[ $file =~ $regex_etc ]]; then
            dist=${BASH_REMATCH[1]}
            # tolower. bash subs only in bash 4.x
            #dist=${dist,,}
            dist=$(echo $dist | tr '[:upper:]' '[:lower:]')
            if [[ $dist == "redhat" || $dist == "red" || $dist == "fedora" ]]; then
                $(grep -q " 7." $file)
                [[ $? -eq 0 ]] && rhel_version=7 && break
                $(grep -q " 8." $file)
                [[ $? -eq 0 ]] && rhel_version=8 && break
                break
            fi
        fi
    done
    [[ -f /etc/centos-release ]] && CENTOS=1
    [[ -f /etc/oracle-release ]] && ORACLE=1 && yum install -y oraclelinux-release-el${rhel_version}
}

add_s9s_apt () {
    repo="deb [arch=amd64] ${repo_http_protocol}://repo.severalnines.com/deb ubuntu main"
    repo_source_file=/etc/apt/sources.list.d/s9s-repo.list
    if [[ ! -e $repo_source_file ]]; then
        wget ${repo_http_protocol}://repo.severalnines.com/severalnines-repos.asc -O- | apt-key add - && log_msg "$repo" | tee -a $repo_source_file
        log_msg "=> Added ${repo_source_file}"
        log_msg "=> Updating repo ..."
        waitForLocks
        apt-get update
    else
        log_msg "=> Repo file $repo_source_file already exists"
        waitForLocks
        apt-get update
    fi
}

start_cmon_services() {

    if [[ "$dist" == "debian" ]]; then
        # apt-get purge -y clustercontrol-nodejs &>/dev/null
        :
    else
        # yum remove -y clustercontrol-nodejs &>/dev/null
        :
    fi

    if [[ $systemd == 1 ]]; then
        pidof -s cmon-events &>/dev/null || systemctl start cmon-events
        systemctl enable cmon-events
        pidof -s cmon-ssh &>/dev/null || systemctl start cmon-ssh
        systemctl enable cmon-ssh
        pidof -s cmon-cloud &>/dev/null || systemctl start cmon-cloud
        systemctl enable cmon-cloud
    else
        pidof -s cmon-events &>/dev/null || service cmon-events start
        pidof -s cmon-ssh &>/dev/null || service cmon-ssh start
        pidof -s cmon-cloud &>/dev/null || service cmon-cloud start

        if [[ "$dist" == "debian" ]]; then
            update-rc.d cmon-events defaults
            update-rc.d cmon-ssh defaults
            update-rc.d cmon-cloud defaults
        else
            chkconfig --levels 235 cmon-ssh on
            chkconfig --levels 235 cmon-events on
            chkconfig --levels 235 cmon-cloud on
        fi
    fi
}

add_s9s_commandline_apt() {
    # Available distros: wheezy, jessie, precise, trusty, xenial, yakkety, zesty
    repo_source_file=/etc/apt/sources.list.d/s9s-tools.list
    if [[ ! -e $repo_source_file ]]; then
        wget -qO - ${repo_http_protocol}://repo.severalnines.com/s9s-tools/${os_codename}/Release.key | apt-key add -
        echo "deb ${repo_http_protocol}://repo.severalnines.com/s9s-tools/${os_codename}/ ./" | tee /etc/apt/sources.list.d/s9s-tools.list
    else
        log_msg "=> Repo file $repo_source_file already exists"
    fi
}

add_s9s_yum () {
    repo_source_file=/etc/yum.repos.d/s9s-repo.repo
    if [[ ! -e $repo_source_file ]]; then
        cat > $repo_source_file << EOF
[s9s-repo]
name=Severalnines Repository
baseurl = ${repo_http_protocol}://repo.severalnines.com/rpm/os/x86_64
enabled = 1
gpgkey = ${repo_http_protocol}://repo.severalnines.com/severalnines-repos.asc
gpgcheck = 1
EOF
    log_msg "=> Added ${repo_source_file}"
    else
        log_msg "=> Repo file $repo_source_file already exists"
    fi
}

add_s9s_commandline_yum() {
    repo_source_file=/etc/yum.repos.d/s9s-tools.repo
    if [[ ! -e $repo_source_file ]]; then
        if [[ -z $CENTOS ]]; then
            REPO="RHEL_6"
            [[ $rhel_version == "7" ]] && REPO="RHEL_7"
            [[ $rhel_version == "8" ]] && REPO="RHEL_8"
        else
            REPO="CentOS_6"
            [[ $rhel_version == "7" ]] && REPO="CentOS_7"
            [[ $rhel_version == "8" ]] && REPO="CentOS_8"
        fi
        cat > $repo_source_file << EOF
[s9s-tools]
name=s9s-tools (${REPO})
type=rpm-md
baseurl=${repo_http_protocol}://repo.severalnines.com/s9s-tools/${REPO}
gpgcheck=1
gpgkey=${repo_http_protocol}://repo.severalnines.com/s9s-tools/${REPO}/repodata/repomd.xml.key
enabled=1
EOF
    log_msg "=> Added ${repo_source_file}"
    else
        log_msg "=> Repo file $repo_source_file already exists"
    fi
}

find_mysql() {
    mysql_bin="/usr/bin/mysql"
    if ! command -v mysql &>/dev/null; then
        log_msg "=> Cannot find a mysql client in your PATH!"
        log_msg "=> Provide the full path to your mysql client, for example /opt/mysql/bin/mysql"
        read -p "=> Absolute path to the MySQL client: " x
        [[ ! -z $x ]] && mysql_bin="$x"
        [[ ! -f $mysql_bin ]] && { log_msg "Cannot find ${mysql_bin}. ..."; exit 1; }
    fi
}

add_apt_repo_percona () {
    $(grep -q "repo.percona.com" /etc/apt/sources.list)
    if [[ $? -eq 1 ]]; then
        repo_source_file=/etc/apt/sources.list.d/percona-release.list
        if [ ! -e $repo_source_file ]; then
            log_msg "=> Adding Percona apt Repository ..."
            dist_name="$(lsb_release -sc)"
            [[ -z $dist_name ]] && log_msg "=> Distro name is empty. ..." && exit 1

            wget https://repo.percona.com/apt/percona-release_0.1-4.$(lsb_release -sc)_all.deb
            dpkg -i percona-release_0.1-4.$(lsb_release -sc)_all.deb
            log_msg "=> Updating repository ..."
            apt-get update
            [[ $? -ne 0 ]] && log_msg "=> Unable to update the repository. ..." && exit 1
        else
            log_msg "=> Percona repo ${repo_source_file} already exists. Skipping .."
        fi
    fi
}

add_yum_repo_percona () {
    log_msg "=> Adding Percona yum Repository ..."
    if [[ ! -f /etc/yum.repos.d/percona-release.repo ]]; then
        yum install http://www.percona.com/downloads/percona-release/redhat/0.1-4/percona-release-0.1-4.noarch.rpm
        log_msg "=> Verifing repository ..."
        yum list | grep percona
    else
        log_msg "=> Percona repo already exists. Skipping .."
    fi
}

add_yum_repo_oracle () {
    log_msg "=> Adding Oracle MySQL yum Repository ..."
    if [[ ! -f /etc/yum.repos.d/Oracle.repo ]]; then
        rpm -Uvh http://dev.mysql.com/get/mysql-community-release-el7-5.noarch.rpm
        log_msg "=> Verifing repository ..."
        yum list | grep mysql
    else
        log_msg "=> Oracle MySQL repo already exists. Skipping .."
    fi
}

install_percona_server() {
    mysql_basedir="/usr"
    mysql_datadir="/var/lib/mysql"
    if [[ $dist == "debian" ]]; then
        add_apt_repo_percona
        log_msg "=> Installing Percona Server ..."
        apt-get -yq install percona-server-server-5.6
        my_cnf=/etc/mysql/my.cnf
        mysql_socket="/var/lib/mysql/mysql.sock"
    elif [[ "$dist" == "redhat" ]]; then
        add_yum_repo_percona
        log_msg "=> Installing Percona Server ..."
        yum -y install Percona-Server-client-56 Percona-Server-server-56
        my_cnf=/etc/my.cnf
        mysql_socket="/var/lib/mysql/mysql.sock"
        service mysql restart
        chkconfig --levels 235 mysql on
        log_msg "=> Secure your Percona Server!"
        until set_root_password; do
            log_msg ""
            log_msg "=> Password mismatch! Try again."
            sleep 1
        done
        log_msg ""
        log_msg "=> Setting MySQL root password ..."
        mysqladmin -uroot password ''"$root_password"'' &>/dev/null
    fi
    log_msg "=> Creating/replacing ${my_cnf}..."
    create_my_cnf /tmp/my.cnf
    cp -f /tmp/my.cnf $my_cnf
    rm -f /tmp/my.cnf
    #killall -15 mysqld mysqld_safe &>/dev/null
    service mysql stop
    rm -rf $mysql_datadir/ib_log* $mysql_datadir/mysqld.pid $mysql_datadir/cmon $mysql_datadir/dcps
    service mysql start
    return $?
}

install_ui_packages_debian() {
    apache_conf=/etc/apache2/sites-available/default
    apache_conf_ssl=/etc/apache2/sites-available/default-ssl
    www_user=www-data
    install_packages="apt-get -y install mysql-server mysql-client apache2 php5-mysql php5-gd libapache2-mod-php5 php5-curl php5-ldap wget"
    [[ -n $use_existing_mysql ]] && install_packages="apt-get -y install apache2 php5-mysql php5-gd libapache2-mod-php5 php5-curl php5-ldap wget"
    enable_mods="ssl rewrite headers"
    cert_file="/etc/ssl/certs/s9server.crt"
    key_file="/etc/ssl/private/s9server.key"
    restart_apache="service apache2 restart"
    stop_mysql="service mysql stop"
    start_mysql="service mysql start"
    update_repo="apt-get update"
    mysql_basedir=/usr
    mysql_datadir=/var/lib/mysql
    my_cnf=/etc/mysql/my.cnf
    mysql_socket="/var/run/mysqld/mysqld.sock"

    if ask "=> Do $update_repo? (Y/n): " "y"; then
        $update_repo
    fi
    # fix for Ubuntu 14.x
    if [[ ! -z $use_apache24 ]]; then
        [[ $install_packages == "" ]] && install_packages="apt-get -y install"
        install_packages="${install_packages} php5-json"
    fi

    case "${os_codename}" in
        'focal' | 'disco' | 'bionic' | 'xenial' | 'stretch')
            # prefixes packages simply with 'php'
            install_packages="${install_packages} php-xml"
            install_packages="`echo $install_packages | sed 's/php5/php/g'`"
            ;;
        'buster')
            # prefixes packages simply with 'php'
            install_packages="${install_packages} php-xml"
            install_packages="`echo $install_packages | sed 's/php5/php/g'`"
            install_packages="`echo $install_packages | sed 's/mysql-/default-mysql-/g'`"
            ;;
    esac

    if [[ -n $install_packages ]]; then
        waitForLocks
        LC_ALL=en_US.utf8 DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true $install_packages
        [[ $? -ne 0 ]] && log_msg "=> Installing packages ${install_packages}, failed" && exit 1
    fi

    if [[ ! -z $use_apache24 ]]; then
        # default web root for clustercontrol is /var/www. apache 2.2 legacy
        if [[ -d /var/www/html ]] && [[ -d /var/www/clustercontrol ]]; then
            ln -sfn /var/www/clustercontrol /var/www/html
        fi
        apache_sites_available_dir="/etc/apache2/sites-available"
        apache_sites_enabled_dir="/etc/apache2/sites-enabled"
        apache_conf="${apache_sites_available_dir}/s9s.conf"
        apache_conf_ssl="${apache_sites_available_dir}/s9s-ssl.conf"
        apache_conf_orig="000-default.conf"
        apache_conf_ssl_orig="default-ssl.conf"

        if [[ -f $wwwroot/clustercontrol/app/tools/apache2/s9s.conf ]]; then
            cp -f $wwwroot/clustercontrol/app/tools/apache2/s9s.conf ${apache_sites_available_dir}/
            cp -f $wwwroot/clustercontrol/app/tools/apache2/s9s-ssl.conf ${apache_sites_available_dir}/
        else
            # create our configs
            create_apache24_configs
        fi

        rm -f $apache_sites_enabled_dir/$apache_conf_orig
        # just in case
        rm -f $apache_sites_enabled_dir/$apache_conf_ssl_orig
        rm -f $apache_sites_enabled_dir/001-$apache_conf_ssl_orig

        ln -sfn $apache_conf $apache_sites_enabled_dir/001-s9s.conf
        ln -sfn $apache_conf_ssl $apache_sites_enabled_dir/001-s9s-ssl.conf

        # enable sameorigin header
        if [[ -f /etc/apache2/conf-available/security.conf ]]; then
            # enable for header
            sed -ibak "s|^#Header set X-Frame-Options: \"sameorigin\"|Header set X-Frame-Options: \"sameorigin\"|g" /etc/apache2/conf-available/security.conf
            ln -sfn /etc/apache2/conf-available/security.conf /etc/apache2/conf-enabled/security.conf
            a2enmod headers &>/dev/null || log_msg "Failed to enable apache headers module!"
        fi
    fi
}

install_ui_packages_redhat() {
    apache_conf=/etc/httpd/conf/httpd.conf
    apache_conf_ssl=/etc/httpd/conf.d/ssl.conf
    www_user=apache
    install_packages="yum -y install mysql-server mysql httpd php php-mysql php-gd mod_ssl php-curl php-ldap php-xml wget"
    enable_mods=""
    cert_file="/etc/pki/tls/certs/s9server.crt"
    key_file="/etc/pki/tls/private/s9server.key"
    restart_apache="service httpd restart"
    update_repo="yum update"
    mysql_basedir=/usr
    mysql_datadir=/var/lib/mysql
    my_cnf=/etc/my.cnf
    mysql_socket="/var/run/mysqld/mysqld.sock"
    stop_mysql=""
    start_mysql="service mysqld start"
    chkconfig="chkconfig --levels 235 mysqld on"
    chkconfig_apache="chkconfig --levels 235 httpd on"
    mysql_socket="/var/lib/mysql/mysql.sock"

    if [[ ! -z $rhel_version ]]; then
        case "$rhel_version" in
            7)
                install_packages="yum -y install mariadb-server httpd php php-mysql php-gd mod_ssl php-curl php-ldap php-xml wget"
                [[ -n $use_existing_mysql ]] && install_packages="yum -y install httpd php php-mysql php-gd mod_ssl php-curl php-ldap php-xml wget"
                ;;
            8)
                install_packages="yum -y install mariadb-server httpd php php-mysqlnd php-gd mod_ssl php-curl php-ldap php-xml php-json wget"
                [[ -n $use_existing_mysql ]] && install_packages="yum -y install httpd php php-mysqlnd php-gd mod_ssl php-curl php-ldap php-xml php-json wget"
                ;;
            *)
                log_msg "=> Unknown/Unsupported Centos/Red Hat version $rhel_version"
                exit 1
                ;;
        esac
    fi

    if ! ask "=> Do $update_repo? (y/N): " "n"; then
        $update_repo
    fi
    if [[ -n $install_packages ]]; then
        $install_packages
        [[ $? -ne 0 ]] && log_msg "=> Installing packages ${install_packages}, failed" && exit 1
    fi

    if [[ ! -z $rhel_version ]]; then
        case "$rhel_version" in
            '7'|'8')
                yum list installed | grep -q mariadb-server
                if [[ $? -eq 0 ]]; then
                    start_mysql="service mariadb start"
                    chkconfig="chkconfig --levels 235 mariadb on"
                fi
                ;;
        esac
    fi
    # workaround for mysql 8, not safe
    $(yum list installed | grep mysql | grep -q mysql80)
    if [[ $? -eq 0 ]]; then
        mysqld8="mysqld --initialize-insecure --user=mysql --basedir=/usr --datadir=/var/lib/mysql"
    fi
    $chkconfig_apache

    apache_version=$(apachectl -v | grep -i "server version" | cut -d' ' -f3)
    [[ "${apache_version%.*}" == "Apache/2.4"  ]] && use_apache24=1

    if [[ ! -z $use_apache24 ]]; then
        # default web root for clustercontrol is /var/www. apache 2.2 legacy
        if [[ -d /var/www/html ]] && [[ -d /var/www/clustercontrol ]]; then
            ln -sfn /var/www/clustercontrol /var/www/html
        fi
        apache_sites_enabled_dir="/etc/httpd/conf.d"
        apache_conf="${apache_sites_enabled_dir}/s9s.conf"
        apache_conf_ssl="${apache_sites_enabled_dir}/ssl.conf"
        apache_conf_orig="default.conf"
        apache_conf_ssl_orig="ssl.conf"

        rm -f $apache_sites_enabled_dir/$apache_conf_orig
        # just in case
        rm -f $apache_sites_enabled_dir/$apache_conf_ssl_orig
        rm -f $apache_sites_enabled_dir/001-$apache_conf_ssl_orig

        cp -f $wwwroot/clustercontrol/app/tools/apache2/s9s.conf ${apache_sites_enabled_dir}/
        cp -f $wwwroot/clustercontrol/app/tools/apache2/s9s-ssl.conf ${apache_sites_enabled_dir}/${apache_conf_ssl_orig}

        # AWS Amazon AMI 2014.09, Apache 2.4/PHP 5.5
        # - /var/lib/php5.5/session does not exist as default
        # - https is not enabled by default
        if [[ -d /var/lib/php/5.5 ]]; then
            [[ ! -d /var/lib/php/5.5/session ]] && mkdir -p /var/lib/php/5.5/session && chmod og=+wxt /var/lib/php/5.5/session
        fi
        if [[ -d /var/lib/php ]]; then
            [[ ! -d /var/lib/php/session ]] && mkdir -p /var/lib/php/session && chmod og=+wxt /var/lib/php/session
        fi
        grep -q "Listen 443" /etc/httpd/conf/httpd.conf
        [[ $? -eq 1 ]] && sed -i '1s/^/Listen 443\n/' /etc/httpd/conf/httpd.conf &>/dev/null
        grep -q "ServerName 127.0.0.1" /etc/httpd/conf/httpd.conf
        [[ $? -eq 1 ]] && sed -i '1s/^/ServerName 127.0.0.1\n/' /etc/httpd/conf/httpd.conf &>/dev/null

        # enable sameorigin header
        if [[ ! -f /etc/httpd/conf.d/security.conf ]]; then
            # enable for header
            cat > /etc/httpd/conf.d/security.conf << EOF
Header set X-Frame-Options: "sameorigin"
EOF
        fi

        service httpd restart
    fi
}

install_ui_packages_suse() {
    apache_conf=/etc/apache2/httpd.conf
    apache_conf_ssl=/etc/apache2/ssl.conf
    www_user=wwwrun
    install_packages="yum -y install mysql-server mysql httpd php php-mysql php-gd mod_ssl php-curl php-ldap php-xml wget"
    restart_mysql="systemctl restart mysql.service"
    chkconfig="systemctl enable mysql.service"
    enable_mods=""
    cert_file="/etc/ssl/certs/s9server.crt"
    key_file="/etc/ssl/private/s9server.key"
    restart_apache="systemctl restart apache2.service"
    update_repo="zypper refresh"
    mysql_basedir=/usr
    mysql_datadir=/var/lib/mysql
    my_cnf=/etc/my.cnf
    mysql_socket="/var/lib/mysql/mysql.sock"

    [[ -n $use_existing_mysql ]] && install_packages="yum -y install httpd php php-mysql php-gd mod_ssl php-curl php-ldap php-xml wget"

    if ! ask "=> Do $update_repo? (y/N): " "n"; then
        $update_repo
    fi
    if [[ -n $install_packages ]]; then
        $install_packages
        [[ $? -ne 0 ]] && log_msg "=> Installing packages failed" && exit 1
    fi
    systemctl enable apache2.service
    apache_version=$(apache2ctl -v | grep -i "server version" | cut -d' ' -f3)
    [[ "${apache_version%.*}" == "Apache/2.4"  ]] && use_apache24=1

    if [[ ! -z $use_apache24 ]]; then
        # default web root for clustercontrol is /var/www. apache 2.2 legacy
        if [[ -d /var/www/html ]] && [[ -d /var/www/clustercontrol ]]; then
            ln -sfn /var/www/clustercontrol /var/www/html
        fi
        apache_sites_enabled_dir="/etc/apache2/vhosts.d"
        apache_conf="${apache_sites_enabled_dir}/s9s.conf"
        apache_conf_ssl="${apache_sites_enabled_dir}/ssl.conf"
        apache_conf_orig="vhost.conf"
        apache_conf_ssl_orig="ssl.conf"

        rm -f $apache_sites_enabled_dir/$apache_conf_orig
        # just in case
        rm -f $apache_sites_enabled_dir/$apache_conf_ssl_orig
        rm -f $apache_sites_enabled_dir/001-$apache_conf_ssl_orig

        cp -f $wwwroot/clustercontrol/app/tools/apache2/s9s.conf ${apache_sites_enabled_dir}/
        cp -f $wwwroot/clustercontrol/app/tools/apache2/s9s-ssl.conf ${apache_sites_enabled_dir}/${apache_conf_ssl_orig}

        # - /var/lib/php5.5/session does not exist as default
        # - https is not enabled by default
        if [[ -d /var/lib/php/5.5 ]]; then
            [[ ! -d /var/lib/php/5.5/session ]] && mkdir -p /var/lib/php/5.5/session && chmod og=+wxt /var/lib/php/5.5/session
            (grep -q "Listen 443" /etc/apache2/httpd.conf)
            [[ $? -eq 1  ]] && log_msg "Listen 443" | tee -a /etc/apache2/httpd.conf &>/dev/null
            (grep -q "ServerName 127.0.0.1" /etc/apache2/httpd.conf)
            [[ $? -eq 1  ]] && log_msg "ServerName 127.0.0.1" | tee -a /etc/apache2/httpd.conf &>/dev/null
            service apache2 restart
        fi
    fi
}

install_ui_packages() {
    case $dist in
        debian) install_ui_packages_debian;;
        redhat) install_ui_packages_redhat;;
        suse) install_ui_packages_suse;;
        *) log_msg "Unknown $dist. "; exit 1
    esac

    sed -ibak "s|AllowOverride None|AllowOverride All|g" $apache_conf
    sed -ibak "s|AllowOverride None|AllowOverride All|g" $apache_conf_ssl

    # Apache's default cert's lifespan is  1-10y depending on distro
    sed -ibak "s|^[ \t]*SSLCertificateFile.*|	        SSLCertificateFile ${cert_file}|g" $apache_conf_ssl
    sed -ibak "s|^[ \t]*SSLCertificateKeyFile.*|	        SSLCertificateKeyFile ${key_file}|g" $apache_conf_ssl
    [[ -n ${rhel_version} && ${rhel_version} == "7" ]] && sed -ibak "s|^[ \t]*#SSLCertificateChainFile.*|	        SSLCertificateChainFile ${cert_file}|g" $apache_conf_ssl

    for m in $enable_mods; do
        a2enmod $m
        # Enable Web SSH
        [[ ! -z $use_apache24 ]] && a2enmod proxy proxy_http proxy_wstunnel
    done

    [[ $dist == "debian" ]] && [[ -z $need_apache24 ]] &&  ln -sf $apache_conf_ssl /etc/apache2/sites-enabled/001-${apache_conf_ssl##*/}

    mkdir -p $wwwroot/cmon/upload/schema
    cat > $wwwroot/cmon/.htaccess << EOF
Options -Indexes
EOF
    chmod -R 770 $wwwroot/clustercontrol/app/tmp $wwwroot/clustercontrol/app/upload $wwwroot/cmon
    if [[ $dist == "suse" ]]; then
        chown -R $www_user $wwwroot/clustercontrol/app/tmp $wwwroot/clustercontrol/app/upload $wwwroot/cmon
    else
        chown -R $www_user.$www_user $wwwroot/clustercontrol/app/tmp $wwwroot/clustercontrol/app/upload $wwwroot/cmon
    fi
    if [[ -d $wwwroot/clustercontrol/ssl ]]; then
        # generate new cert
        if command -v openssl &>/dev/null; then
            create_cert
        fi
        # copy the files from the clustercontrol package
        cp -f $wwwroot/clustercontrol/ssl/server.crt ${cert_file} &>/dev/null
        cp -f $wwwroot/clustercontrol/ssl/server.key ${key_file} &>/dev/null
        rm -rf $wwwroot/clustercontrol/ssl &>/dev/null
    fi

    $restart_apache

    if [[ -z $use_existing_mysql ]]; then
        log_msg "Stoppping MySQL Server before updating configuration ..."
        #killall -15 mysqld mysqld_safe &>/dev/null
        $stop_mysql
        [[ $? -ne 0 ]] && [[ $stop_mysql != "" ]] && log_msg "=> Failed to stop the MySQL Server. ..." && exit 1

        create_my_cnf /tmp/my.cnf
        cp -f /tmp/my.cnf $my_cnf
        rm -f /tmp/my.cnf
        rm -rf $mysql_datadir/ib_log* $mysql_datadir/mysqld.pid $mysql_datadir/cmon $mysql_datadir/dcps

        echo -e "\n=> Starting database. This may take a couple of minutes. Do NOT press any key."
        if [[ ! -z $mysqld8 ]]; then
            # initialize-insecure for centos/rhel
            $mysqld8
        fi
        $start_mysql
        [[ $? -ne 0 ]] && log_msg "=> Failed to start the MySQL Server. ..." && exit 1

        log_msg "=> Securing the MySQL Server ..."
        log_msg "=> !! In order to complete the installation you need to set a MySQL root password !!"
        log_msg "=> Supported special password characters: ~!@#$%^&*()_+{}<>?"
        [[ -z $S9S_ROOT_PASSWORD ]] && read -n 1 -s -r -p "=> Press any key to proceed ..."
        echo ""

        case "${os_codename}" in
            'focal' | 'disco' | 'bionic' | 'xenial')
                $mysql_basedir/bin/mysql -uroot -P${db_port} -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY ''"
                ;;
        esac

        if [[ -z ${S9S_CMON_PASSWORD} ]]; then
            mysql_secure_installation
            [[ $? -ne 0 ]] && log_msg "=> Unable to secure the MySQL server running mysql_secure_installation, exiting ..." && exit 1
            echo -e "\n=> Please enter the MySQL root password that was set to continue!"
            until set_root_password; do
                log_msg ""
                log_msg "=> Password mismatch! Try again."
                sleep 1
            done
        else
            log_msg "=> !! Setting MySQL root user password !!"
            $mysql_basedir/bin/mysqladmin -uroot -P${db_port} password "${S9S_ROOT_PASSWORD}"
            log_msg "=> !! Please run mysql_secure_installation after the setup !!"
        fi
    fi

    if [[ $dist = "redhat" ]]; then
        [[ -z $use_existing_mysql ]] && $chkconfig
        setenforce 0
        sed -i s/SELINUX=enforcing/SELINUX=disabled/g /etc/selinux/config &>/dev/null
        cat << EOF
=> NOTE: Stopping and disabling firewall...manually re-enable and add rules if required.
Required ports to be opened, http://support.severalnines.com/entries/22654676-Firewall-ports-
EOF
        if [[ $systemd == 1 ]]; then
            systemctl stop firewalld
            systemctl disable firewalld
        else
            service iptables stop
            chkconfig iptables off
        fi
    fi
}

create_my_cnf() {

    cat > $1 << EOF
[mysqld]
user = mysql
#basedir = $mysql_basedir
datadir = $mysql_datadir
pid_file = $mysql_datadir/mysqld.pid
socket = $mysql_socket
port = ${db_port}
#log_error = error.log
max_allowed_packet = 128M
#event_scheduler = 1
innodb_buffer_pool_size = ${INNODB_BUFFER_POOL_SIZE}M
innodb_flush_log_at_trx_commit = 2
innodb_file_per_table = 1
#innodb_data_file_path = ibdata1:100M:autoextend
innodb_log_file_size = 512M
innodb_log_files_in_group = 2
#innodb_buffer_pool_instances = 4
innodb_thread_concurrency = 0
innodb_flush_method = O_DIRECT
sysdate_is_now = 1
max_connections = 512
thread_cache_size = 128
#table_open_cache=512
lower_case_table_names = 0
#skip_name_resolve
skip-log-bin
EOF

    case "${os_codename}" in
        'disco' | 'bionic' | 'xenial' | 'stretch' | 'buster')
            cat >> $1 << EOF
plugin-load-add = auth_socket.so
EOF
        ;;
        esac

    cat >> $1 << EOF
[mysql]
socket=$mysql_socket

[client]
socket=$mysql_socket

[mysqld_safe]
pid-file=$mysql_datadir/mysqld.pid
#log-error=error.log
basedir=$mysql_basedir
datadir=$mysql_datadir
EOF

}

install_ui_database() {
    find_mysql
    echo -e "\n=> Importing the Web Application DB schema and creating the cmon user."

    if [[ $root_password == "" ]] || [[ -z $root_password ]]; then
        IFS="" read -s -p "=> Enter your MySQL root user's password: " x
        [[ ! -z $x ]] && root_password="$x"
    fi

    $mysql_bin -uroot -p''"${root_password}"'' -P${db_port} -e "SELECT USER();" &>/dev/null
    if [[ $? -ne 0 ]]; then
        log_msg "=> Cannot Connect! Try again."
        IFS="" read -s -p "=> Enter your MySQL root user's password: " x
        [[ ! -z $x ]] && root_password="$x"
        log_msg ""
    fi

    echo -e "\n=> Importing $wwwroot/clustercontrol/sql/dc-schema.sql"
    $mysql_bin -uroot -p''"${root_password}"'' -P${db_port} < $wwwroot/clustercontrol/sql/dc-schema.sql
    [[ $? -ne 0 ]] && log_msg "=> Failed to import the Web Application DB schema ($wwwroot/clustercontrol/sql/dc-schema.sql) ..." && exit 1

    log_msg "=> Set a password for ClusterControl's MySQL user (cmon) [${cmon_password}]"
    log_msg "=> Supported special characters: ~!@#$%^&*()_+{}<>?"
    until set_cmon_password; do
        log_msg ""
        log_msg "=> Password mismatch! Try again."
        sleep 1
    done

    cat > /tmp/ui.sql << EOF
USE dcps;
BEGIN;
CREATE USER 'cmon'@'localhost' identified by '${cmon_password}';
GRANT ALL PRIVILEGES ON *.* to 'cmon'@'localhost' WITH GRANT OPTION;
CREATE USER 'cmon'@'127.0.0.1' identified by '${cmon_password}';
GRANT ALL PRIVILEGES ON *.* to 'cmon'@'127.0.0.1' WITH GRANT OPTION;
CREATE USER 'cmon'@'${host}' identified by '${cmon_password}';
GRANT ALL PRIVILEGES ON *.* to 'cmon'@'${host}' WITH GRANT OPTION;
COMMIT;
EOF

    log_msg "=> Creating the MySQL cmon user ..."
    if [[ -z $use_existing_mysql ]]; then
        $mysql_bin -uroot -P${db_port} -p''"${root_password}"'' < /tmp/ui.sql
    else
        cat > /tmp/drop.sql << EOF
DROP USER 'cmon'@'localhost';
DROP USER 'cmon'@'127.0.0.1';
DROP USER 'cmon'@'${host}';
EOF
        $mysql_bin -f -uroot -P${db_port} -p''"${root_password}"'' < /tmp/drop.sql &>/dev/null
        [[ $? -ne 0 ]] && log_msg "Failed to drop cmon user! ..." && exit 1
        rm -f /tmp/drop.sql
        $mysql_bin -f -uroot -P${db_port} -p''"${root_password}"'' < /tmp/ui.sql &>/dev/null
    fi
    [[ $? -ne 0 ]] && log_msg "Failed to add cmon user! ..." && exit 1
    rm -f /tmp/ui.sql
}

create_ui_configuration() {
    log_msg "=> Creating UI configuration ..."
    cp -f $wwwroot/clustercontrol/bootstrap.php.default $wwwroot/clustercontrol/bootstrap.php &>/dev/null
    PASS="${cmon_password}" perl -p -i -e "s|^define\('DB_PASS'.*|define('DB_PASS', '\$ENV{PASS}');|g" $wwwroot/clustercontrol/bootstrap.php
    sed -i "s|^define('DB_PORT'.*|define('DB_PORT', '${db_port}');|g" $wwwroot/clustercontrol/bootstrap.php
    sed -i "s|^define('RPC_TOKEN'.*|define('RPC_TOKEN', '${cc_api_token}');|g" $wwwroot/clustercontrol/bootstrap.php
    # sed -i "s|^define('WEBSOCKET_HOST'.*|define('WEBSOCKET_HOST', 'ws://${host}:1337');|g" $wwwroot/clustercontrol/bootstrap.php
    # Add container env
    echo "define('CONTAINER', '${CONTAINER}');" >> $wwwroot/clustercontrol/bootstrap.php
}

check_emailaddress() {
    if [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]]; then
        return 0
    else
        log_msg "=> Invalid email address"
        return 1
    fi
}

set_cmon_password() {
    [[ ! -z $S9S_CMON_PASSWORD ]] && return 0
    IFS="" read -s -p "=> Enter a CMON user password: " x
    if [[ -z $x ]]; then
        log_msg "=> The password cannot be blank. Try again."
        IFS="" read -s -p "=> Enter a CMON user password: " x
    fi
    cmon_password="$x"
    log_msg ""
    IFS="" read -s -p "=> Enter the CMON user password again: " x
    if [[ "$cmon_password" == "$x" ]]; then
        return 0
    else
        return 1
    fi
}

set_root_password() {
    [[ ! -z $S9S_ROOT_PASSWORD ]] && return 0
    IFS="" read -s -p "=> Enter the MySQL root password: " x
    while [[ -z $x ]]; do
        log_msg "=> The password cannot be blank. Try again."
        IFS="" read -s -p "=> Enter the MySQL root password: " x
    done
    root_password="$x"
    log_msg ""
    IFS="" read -s -p "=> Enter the MySQL root password again: " x
    if [[ "$root_password" == "$x" ]]; then
        return 0
    else
        return 1
    fi
}

install_controller() {
    cmon_controller="clustercontrol-controller"
    cmon_basedir="/usr"
    [[ ! -z ${CONTROLLER_BUILD} ]] && cmon_controller=${CONTROLLER_BUILD}
    if [[ $dist == "redhat" ]]; then
        enable_service="chkconfig --levels 235 cmon on"
        yum -y install $cmon_controller
        [[ $? -ne 0 ]] && exit 1
    elif [[ $dist == "debian" ]]; then
        enable_service="update-rc.d cmon defaults"
        waitForLocks
        apt-get -y install $cmon_controller
        [[ $? -ne 0 ]] && exit 1
    elif [[ $dist == "suse" ]]; then
        enable_service="chkconfig --add cmon"
        zypper install $cmon_controller
        [[ $? -ne 0 ]] && exit 1
    fi

    cat >> /etc/default/cmon << EOF
# New events client http callback as of v1.4.2!
EVENTS_CLIENT="http://127.0.0.1:${cmon_events_port}"
CLOUD_SERVICE="http://127.0.0.1:${cmon_cloud_port}"
EOF

    # use the cmon token for the global rcp_token
    rpc_key=${cc_api_token}

    # import cmon schema using cmon --init
    cmon --init \
        --mysql-hostname="127.0.0.1" \
        --mysql-port="${db_port}" \
        --mysql-username="${cmon_user}" \
        --mysql-password="${cmon_password}" \
        --mysql-database="cmon" \
        --hostname="${host}" \
        --rpc-token="${rpc_key}" \
        --controller-id="clustercontrol"
    [[ $? -ne 0 ]] && log_msg "Unable to init cmon! Exiting ..." && exit 1

    $enable_service
    log_msg "=> Starting the Controller process."
    if [[ $systemd == 1 ]]; then
        systemctl restart cmon
        systemctl enable cmon
    else
        service cmon restart
    fi

    if [[ $dist == "redhat" ]]; then
        if [[ $rhel_version != "8" ]]; then
            yum install -y ntp ntpdate
            chkconfig ntpd on
            ntpdate pool.ntp.org
            service ntpd start
        fi
    fi
}

install_s9s_commandline() {
    s9s_tools=s9s-tools
    [[ ! -z ${S9S_TOOLS_BUILD} ]] && s9s_tools=${S9S_TOOLS_BUILD}
    if [[ $dist == "redhat" ]]; then
        yum -y install $s9s_tools
    elif [[ $dist == "debian" ]]; then
        waitForLocks
        apt-get -y install $s9s_tools
    fi
    [[ $? -ne 0 ]] && log_msg "Unable to install s9s-tools"

    export S9S_USER_CONFIG=$HOME/.s9s/ccrpc.conf
    s9s user --create --generate-key --new-password=${rpc_key} --group=admins --controller="https://localhost:9501" ccrpc
    if [[ $? -ne 0 ]]; then
        echo "*** Unable to create a 'ccrpc' user! Please check your s9s command line installation! ***" 
        echo "*** Please see https://docs.severalnines.com/docs/clustercontrol/troubleshooting/common-issues/#clustercontrol-controller-cmon on how fix a suspended s9s admin user."
        echo "*** Re-install the ClusterControl package again after checking the s9s command line installation."
        exit 1
    fi

    s9s user --set --first-name=RPC --last-name=API &>/dev/null
    unset S9S_USER_CONFIG

    log_msg "*** Restarting the Controller process to generate the rpc_tls files."
    if [[ $systemd == 1 ]]; then
        systemctl restart cmon
    else
        service cmon restart
    fi
}

create_s9s_user() {
    local email="##__EMAIL__##"
    if [[ ! -z ${S9S_ADMIN_EMAIL} ]]; then
        email="${S9S_ADMIN_EMAIL}"
    else
        return 0
    fi

    if [[ "$email" == *"@"* ]]; then
        local username="${email%%@*}"
        echo "=> Your login username is set to ${username} ..."

        cat > /tmp/login.sql << EOF
USE dcps;
BEGIN;
INSERT INTO settings(name, type) VALUES ('email', 'login');
INSERT INTO settings_items(setting_id, item) VALUES (LAST_INSERT_ID(),'${email}');
INSERT INTO settings(name, type) VALUES ('username', 'login');
INSERT INTO settings_items(setting_id, item) VALUES (LAST_INSERT_ID(),'${username}');
COMMIT;
EOF

        $mysql_bin -f -uroot -P${db_port} -p''"${root_password}"'' < /tmp/login.sql &>/dev/null
        rm -f /tmp/login.sql
    fi
}

create_apache24_configs() {
    rm -f $apache_conf
    cat > $apache_conf << EOF
<VirtualHost *:80>
    ServerName localhost

    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    RedirectMatch ^/$ /clustercontrol/

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    <Directory />
            Options +FollowSymLinks
            AllowOverride All
    </Directory>
    <Directory /var/www/html>
            Options +Indexes +FollowSymLinks +MultiViews
            AllowOverride All
            Require all granted
    </Directory>

</VirtualHost>
EOF
    rm -f $apache_conf_ssl
    cat > $apache_conf_ssl << EOF
<IfModule mod_ssl.c>
        <VirtualHost _default_:443>
                ServerName localhost
                ServerAdmin webmaster@localhost

                DocumentRoot /var/www/html
                RedirectMatch ^/$ /clustercontrol/

                <Directory />
                        Options +FollowSymLinks
                        AllowOverride All
                </Directory>
                <Directory /var/www/html>
                        Options +Indexes +FollowSymLinks +MultiViews
                        AllowOverride All
                        Require all granted
                </Directory>

                ErrorLog \${APACHE_LOG_DIR}/error.log
                CustomLog \${APACHE_LOG_DIR}/access.log combined

                #LogLevel info ssl:warn

                SSLEngine on
                SSLCertificateFile      /etc/ssl/certs/ssl-cert-snakeoil.pem
                SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
                #SSLCertificateChainFile /etc/apache2/ssl.crt/server-ca.crt
                #SSLCACertificatePath /etc/ssl/certs/
                #SSLCACertificateFile /etc/apache2/ssl.crt/ca-bundle.crt
                #SSLCARevocationPath /etc/apache2/ssl.crl/
                #SSLCARevocationFile /etc/apache2/ssl.crl/ca-bundle.crl
                #SSLVerifyClient require
                #SSLVerifyDepth  10
                #SSLOptions +FakeBasicAuth +ExportCertData +StrictRequire
                <FilesMatch "\.(cgi|shtml|phtml|php)$">
                                SSLOptions +StdEnvVars
                </FilesMatch>
                <Directory /usr/lib/cgi-bin>
                                SSLOptions +StdEnvVars
                </Directory>

                BrowserMatch "MSIE [2-6]" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0
                # MSIE 7 and newer should be able to use keepalive
                BrowserMatch "MSIE [17-9]" ssl-unclean-shutdown
        </VirtualHost>
</IfModule>

EOF

}

uninstall_packages() {
    log_msg "=> Please follow the uninstall instructions outlined here, https://severalnines.com/docs/administration.html#uninstall"
}

log_msg() {
    LAST_MSG="$1"
    echo "${LAST_MSG}"
}

checkLock() {
    if command -v fuser >/dev/null 2>/dev/null; then
        fuser $@ 2>/dev/null >/dev/null
        return $?
    fi
    # fuser (psmisc) not installed, go with lsof
    if [ "`lsof $@ 2>/dev/null >/dev/null`x" != "x" ]; then
        return 0
    fi
    return 1
}

waitForLocks() {
    if checkLock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock; then
        echo -n "=> Waiting for APT/DPKG locks."
    else
        return
    fi
    while checkLock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
        echo -n .
        sleep 1
    done
    echo .
}

cleanup() {

    if [[ ! -z ${SEND_DIAGNOSTICS} && ${SEND_DIAGNOSTICS} == 1 ]]; then
        [[ $(command -v cmon) ]] && VERSION=$(cmon --version | awk '/version/ {print $3}')
        if [[ $CONTAINER != "" ]]; then
            UUID=$(hostname | md5sum | cut -d' ' -f1)
        else
            UUID=$(dmidecode --string system-uuid 2>/dev/null | sed 's#-##g' | sha256sum | awk '{print $1}')
        fi
        OS=$(cat /proc/version)
        MEM=$(free -m | awk '/Mem:/ { print "T:" $2, "F:" $4}')
        if [[ -z $PYTHON3 ]]; then
            OS=$(python -c "import sys,urllib; print urllib.quote('${OS}')")
            MEM=$(python -c "import sys,urllib; print urllib.quote('${MEM}')")
            LAST_MSG=$(python -c "import sys,urllib; print urllib.quote('${LAST_MSG}')")
        else
            OS=$(python -c "import sys,urllib.parse; print(urllib.parse.quote('${OS}'))")
            MEM=$(python -c "import sys,urllib.parse; print(urllib.parse.quote('${MEM}'))")
            LAST_MSG=$(python -c "import sys,urllib.parse; print(urllib.parse.quote('${LAST_MSG}'))")
        fi

        wget -qO- --post-data="version=${VERSION:=NA}&uuid=${UUID}&os=${OS}&mem=${MEM}&rc=${INSTALLATION_STATUS}&msg=${LAST_MSG}&container=${CONTAINER}" https://severalnines.com/service/diag.php &>/dev/null

        [[ ${INSTALLATION_STATUS} == "1" ]] && echo "Please contact Severalnines support at http://support.severalnines.com if you have installation issues that cannot be resolved."
    fi
}

check_os() {
    dist="Unknown"
    regex_lsb="Description:[[:space:]]*([^ ]*)"
    regex_etc="/etc/(.*)[-_]"
    systemd=0
    [[ $(readlink /sbin/init) == *"systemd"* ]] && systemd=1

    # install lsb-release on debian|ubuntu
    if apt-get --version >/dev/null 2>/dev/null; then
        log_msg "=> Installing lsb-release ..."
        waitForLocks
        apt-get update -qq
        apt-get install -yq lsb-release
    fi

    if command -v lsb_release &>/dev/null; then
        do_lsb
        [[ $? -ne 0 ]] && do_release_file
    else
        do_release_file
    fi

    dist=$(echo $dist | tr '[:upper:]' '[:lower:]')
    [[ ! -z $CENTOS ]] && dist="centos"
    case $dist in
        debian) dist="debian";;
        ubuntu) dist="debian";;
        red)    dist="redhat";;
        redhat) dist="redhat";;
        centos) dist="redhat";;
        fedora) dist="redhat";;
        suse) dist="suse";;
        oracle) dist="redhat";;
        system)
            dist="redhat" # amazon ami
            log_msg "This distro is not supported! Supported OS, https://severalnines.com/docs/requirements.html#operating-system"
            exit 1
            ;; # amazon ami
        *) log_msg "=> This script couldn't detect a supported distriution (dists parsed: ''$dist')."; ask_generic_distro
    esac
}

create_cert() {
    cd $wwwroot/clustercontrol/ssl

    local domain=*.severalnines.local
    local commonname=$domain
    local san=dev.severalnines.local
    local country=SE
    local state=Stockholm
    local locality=Stockholm
    local organization='Severalnines AB'
    local organizationalunit=Severalnines
    local email=support@severalnines.com
    local keylength=2048
    local expires=1825
    local keyname=server.key
    local certname=server.crt
    local csrname=server.csr

    cat > /tmp/v3.ext << EOF
basicConstraints = CA:FALSE
#authorityKeyIdentifier=keyid,issuer
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = clientAuth, serverAuth
subjectAltName = DNS:${san}
EOF

    echo "==> Generating tls certificate for $domain"
    # ubunutu 18.0x workaround
    touch $HOME/.rnd
    openssl genrsa -out $keyname $keylength

    openssl req -new -key $keyname -out $csrname \
        -addext "subjectAltName = DNS:${san}" \
        -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email" &>/dev/null

    if [[ $? -ne 0 ]]; then
        # centos 6 -addtext is not avaiable
        openssl req -new -key $keyname -out $csrname \
            -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email"
    fi
    openssl x509 -req -extfile /tmp/v3.ext -days $expires -sha256 -in $csrname -signkey $keyname -out $certname

    rm -f /tmp/v3.ext
    cd - &>/dev/null
}

# check distro
check_os

trap cleanup EXIT
INSTALLATION_STATUS=1
LAST_MSG=""
repo_http_protocol="http"
[[ ! -z $REPO_USE_TLS ]] && repo_http_protocol="https"
message="This script will add Severalnines repository server for deb and rpm packages and  \
    \ninstall the ClusterControl Web Applicaiton and Controller. \
    \nAn Apache and MySQL server will also be installed. An existing MySQL Server on this host can be used."

[[ `whoami` != "root" ]] && echo -e "Do: sudo $(basename $0) or run as root\n" && echo -e "$message" && exit 1

# Check if the OS is a 64 bit one. If it's a 32 bit, the installation fails
# with a non'very descriptive message
if [[ "$(uname -m)" != 'x86_64'  ]]; then
    log_msg "ClusterControl is only compatible with x86_64 systems" && exit 1
fi

if [[ ! -z $NO_INET ]]; then
    log_msg ""
    log_msg "=> Detected NO_INET is set, i.e., OFFLINE install."
    log_msg "=> Please follow the instructions in the online manual, https://severalnines.com/docs/installation.html#offline-installation"
    exit 0
fi

while [[ $# > 0  ]]; do
    arg="$1"
    case "$arg" in
        -v|--verbose)
            PROMPT_USER=1
            shift
            ;;
        -p|--percona)
            PROMPT_PERCONA=1
            shift
            ;;
        -u|--uninstall)
            uninstall_packages
            exit 0
            ;;
        *)
            log_msg "=> Unknown option $arg"
            exit 1
            ;;
    esac
    shift
done

echo "!!"
log_msg "Only RHEL/Centos 7|8, Debian 8|9|10, Ubuntu 18.04|20.04 LTS versions are supported"

cc_api_token=$(cat /proc/sys/kernel/random/uuid | sha1sum | cut -f1 -d' ')
CONTAINER="NA"
[[ -f /.dockerenv ]] && CONTAINER="docker"
grep -qa container=lxc /proc/1/environ &>/dev/null
[[ $? -eq 0 ]] && CONTAINER="lxc"

running_mysql=1
if [[ -f /usr/libexec/mysqld || -f /usr/sbin/mysqld ]]; then
    ps -C mysqld &>/dev/null
    running_mysql=$?
elif [[ -f /usr/sbin/mariadbd ]]; then
    ps -C mariadbd &>/dev/null
    running_mysql=$?
fi

if [[ $running_mysql -eq 1 ]]; then
    MEM_TOTAL=$(free -m | awk '/Mem:/ { print $2}')
    MEM_FREE=$(free -m | awk '/Mem:/ { print $ 4}')
    # default 512M
    if (( ${MEM_TOTAL} < 1500 )); then
        log_msg "Minimum system requirements: 2GB+ RAM, 2+ CPU cores"
        log_msg "Server Memory: ${MEM_TOTAL}M total, ${MEM_FREE}M free"
        INNODB_BUFFER_POOL_SIZE=${INNODB_BUFFER_POOL_SIZE:-512}
    else
        SIZE=$((50*${MEM_TOTAL}/100))
        INNODB_BUFFER_POOL_SIZE=${INNODB_BUFFER_POOL_SIZE:-${SIZE}}
        log_msg "System RAM is > 1.5G"
        log_msg "Setting MySQL innodb_buffer_pool_size to 50% of system RAM"
    fi
    log_msg "MySQL innodb_buffer_pool_size set to ${INNODB_BUFFER_POOL_SIZE}M"
    echo ""

    MIN_FREE_MEMORY=${MIN_FREE_MEMORY:-100}
    if (( ${INNODB_BUFFER_POOL_SIZE} + ${MIN_FREE_MEMORY} > ${MEM_FREE} )); then
        log_msg "You do not have enough free memory ${MEM_FREE}M available to set innodb_buffer_pool_size=${INNODB_BUFFER_POOL_SIZE}M"
        log_msg "Need at least 100M or more free memory in addition to what innodb_buffer_pool_size will allocate."
        log_msg "You can set a custom size for example with 'INNODB_BUFFER_POOL_SIZE=512 ./install-cc' and try again."
        if [[ -z $S9S_CMON_PASSWORD ]]; then
            read -p "=> Enter new innodb_buffer_pool_size (in MB, e.g, 512): " x
            [[ ! -z $x ]] && INNODB_BUFFER_POOL_SIZE=$x
            log_msg "=> Using new innodb_buffer_pool_size ${INNODB_BUFFER_POOL_SIZE}M"
            echo ""
        else
            exit 1
        fi
    fi
fi

log_msg "Severalnines would like your help improving our installation process."
log_msg "Information such as OS, memory and install success helps us improve how we onboard our users."
log_msg "None of the collected information identifies you personally."
log_msg "!!"
if [[ ! -z ${SEND_DIAGNOSTICS} ]] || confirm "=> Would you like to help us by sending diagnostics data for the installation? (Y/n): " "y"; then
    SEND_DIAGNOSTICS=${SEND_DIAGNOSTICS:-1}
fi
echo ""

[[ ! -z $message ]] && echo -e $message
echo ""

if [[ "$dist" == "debian" ]]; then
    waitForLocks
    log_msg "=> Installing required packages ..."
    apt-get install -yq wget bc gnupg dmidecode
    case "${os_codename}" in
        'focal' | 'bionic')
            log_msg "=> Installing python ..."
            apt-get install -yq python3
            update-alternatives --install /usr/bin/python python /usr/bin/python3 1
            ;;
        *)
            log_msg "=> Installing python ..."
            apt-get install -yq python
            ;;
    esac
    python --version | grep -q 3.
    [[ $? -eq 0 ]] && PYTHON3=1

    if ! command -v add-apt-repository &>/dev/null; then
        if [[ ${os_codename} == "stretch" || ${os_codename} == "buster" ]]; then
            log_msg "=> Installing software-properties-common ..."
            apt-get install -yq software-properties-common
        else
            log_msg "=> Installing python-software-properties ..."
            apt-get install -yq python-software-properties
        fi
    fi
fi

if [[ "$dist" == "redhat" ]]; then
    log_msg "=> Installing required packages ..."
    yum install -yq wget dmidecode hostname
    log_msg "=> Installing python ..."
    if [[ $rhel_version == "8" ]]; then
        yum install -y python36
        alternatives --set python /usr/bin/python3
    else
        yum install -y python
    fi
    python --version | grep -q 3.
    [[ $? -eq 0 ]] && PYTHON3=1
fi

wwwroot="/var/www/html"
if [[ "$dist" == "debian" ]]; then
    wwwroot="/var/www"

    distro_id=$(lsb_release -s -i)
    distro_release=$(lsb_release -s -r)
    if [[ $? -eq 0 ]]; then
        distro_release=${distro_release%%.*}
        # Apache 2.4 uses new config
        if [[ ${distro_id} == "Ubuntu" ]]; then
            if (( $(log_msg "$distro_release > 12" | bc) )); then
                use_apache24=1
            fi
        elif [[ ${distro_id} == "Debian" ]]; then
            if (( $(log_msg "$distro_release > 7" | bc) )); then
                use_apache24=1
            fi
        fi
    else
        log_msg "=> Unable to determine distro release number ..."
        log_msg "=> Assuming > apache 2.4..."
        use_apache24=1
    fi
    [[ ! -z $use_apache24 ]] && wwwroot="/var/www/html"
fi

if [[ $dist == "debian" ]]; then
    waitForLocks
    add_s9s_commandline_apt
    add_s9s_apt
    log_msg "=> Installing the ClusterControl package ..."
    clustercontrol_build=clustercontrol
    [[ ! -z ${CLUSTERCONTROL_BUILD} ]] && clustercontrol_build=${CLUSTERCONTROL_BUILD}
    waitForLocks
    apt-get -y install ${clustercontrol_build} || { log_msg "=> Failed to install clustercontrol packages. (apt-get -y install clustercontrol)"; exit 1; }
else
    add_s9s_commandline_yum
    add_s9s_yum
    log_msg "=> Installing the ClusterControl package ..."
    clustercontrol_build=clustercontrol
    [[ ! -z ${CLUSTERCONTROL_BUILD} ]] && clustercontrol_build=${CLUSTERCONTROL_BUILD}
    yum -y install ${clustercontrol_build} || { log_msg "=> Failed to install clustercontrol packages. (yum -y install clustercontrol)"; exit 1; }
fi

hostname_cmd="hostname -I"
$hostname_cmd &>/dev/null
[[ $? -ne 0 ]] && hostname_cmd="hostname -i"

ip=($($hostname_cmd))
host=${ip[0]}
[[ ! -z $HOST ]] && host=$HOST

message="Finalizing the ClusterControl Web Application and Controller (CMON process) installation.\n"

[[ ${#ip[@]} > 1 ]] && message="$message\nNOTE: Detected more than one IP: ${ip[@]}\nUsing hostname ${host} or do 'export HOST=<hostname>' to explicitly set a host"
echo -e $message

log_msg ""
if ! ask_p "=> The Controller hostname will be set to $host. Do you want to change it? (y/N): " "n"; then
    read -p "=> Enter the hostname: " x
    [[ ! -z $x ]] && host="$x"
    log_msg "=> The hostname is now set to $host"
fi

log_msg "=> Creating temporary staging dir s9s_tmp"
mkdir -p s9s_tmp

db_port=3306
cmon_user="cmon"
cmon_password="cmon"
cmon_events_port=9510
cmon_cloud_port=9518
[[ ! -z $S9S_CMON_PASSWORD ]] && cmon_password="$S9S_CMON_PASSWORD"
[[ ! -z $S9S_ROOT_PASSWORD ]] && root_password="$S9S_ROOT_PASSWORD"
[[ ! -z $S9S_DB_PORT ]] && db_port=$S9S_DB_PORT

log_msg ""
log_msg "=> Setting up the ClusterControl Web Application ..."
log_msg "=> Using web document root $wwwroot"
mkdir -p $wwwroot

if [[ $running_mysql -eq 0  ]]; then
    if ask_p "=> Detected a running MySQL server. Should I use your existing MySQL server? (Y/n): " "y"; then
        use_existing_mysql=1
    fi
fi

if [[ -z $use_existing_mysql ]]; then
    log_msg "=> No running MySQL server detected"
    if [[ -z $PROMPT_PERCONA ]]; then
        log_msg "=> Installing the default distro MySQL Server ..."
    else
        if ask "=> Install a Percona Server? (Y/n): " "y"; then
            [[ $dist == "debian" ]] && log_msg "=> Note: On AWS for Ubuntu you need at least a small instance to install the default Percona Server."
            install_percona=1
        else
            log_msg "=> Installing the default distro MySQL Server ..."
        fi
    fi
fi

if [[ ! -z $install_percona ]]; then
    use_existing_mysql=1
    install_percona_server
    [[ $? -ne 0 ]] && log_msg "=> Unable to install a MySQL Server. ..." && exit 1
fi

install_cmon=0
if ask "=> Install the ClusterControl Controller? (Y/n): " "y"; then
    install_cmon=1
    if [[ -z ${S9S_CMON_PASSWORD} && -f /etc/cmon.cnf ]]; then
        log_msg "=> An existing Controller installation detected!"
        log_msg "=> A re-installation of the Controller will overwrite the /etc/cmon.cnf file"
        if ask_p "=> Install the Controller? (y/N): " "n"; then
            install_cmon=0
        fi
    fi
fi

# Intall ClusterControl UI
install_ui_packages
install_ui_database
create_ui_configuration
# reset permissions
chmod -R ugo-w ${wwwroot}/clustercontrol &>/dev/null
chmod -R ug+w ${wwwroot}/clustercontrol/app/tmp &>/dev/null
chown -R ${www_user}.${www_user} $wwwroot/clustercontrol/
log_msg "=> ClusterControl Web Application setup completed!"

# Install Controller
if [[ $install_cmon -eq 1 ]]; then
    log_msg "=> Installing ClusterControl Controller ..."
    install_controller
    install_s9s_commandline
    create_s9s_user
fi

# start events and ssh services
start_cmon_services

echo -e "=> ClusterControl installation completed!"
echo -e "Open your web browser to http://${host}/clustercontrol and\nenter an email address and new password for the default Admin User.\n"

# success
INSTALLATION_STATUS=0

if command -v dig &>/dev/null; then
    echo -e "\nDetermining network interfaces. This may take a couple of minutes. Do NOT press any key."
    ext_ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    [[ ! -z $ext_ip ]] && log_msg "Public/external IP => http://${ext_ip}/clustercontrol"
    [[ ${#ip[@]} > 1 ]] && log_msg "NOTE: Detected more than one IP: ${ip[@]}"
fi

log_msg "Installation successful. If you want to uninstall ClusterControl then run ${0##*/} --uninstall."
exit 0
