#!/bin/bash

sudo apt remove --purge mysql-server

sudo apt purge mysql-server

sudo apt autoremove

sudo apt autoclean

sudo apt remove dbconfig-mysql

sudo rm -rf /etc/mysql /var/lib/mysql 

sudo rm -rf /var/log/mysql
