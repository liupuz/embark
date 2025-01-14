#!/bin/bash

# EMBArk - The firmware security scanning environment
#
# Copyright 2020-2022 Siemens Energy AG
# Copyright 2020-2021 Siemens AG
#
# EMBArk comes with ABSOLUTELY NO WARRANTY.
#
# EMBArk is licensed under MIT
#
# Author(s): Michael Messner, Pascal Eckmann
# Contributor(s): Benedikt Kuehne

# Description: Installer for EMBArk

export DEBIAN_FRONTEND=noninteractive

DIR="$(realpath "$(dirname "$0")")"

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # no color

print_help() {
  echo -e "\\n""$CYAN""USAGE""$NC"
  echo -e "$CYAN-h$NC         Print this help message"
  echo -e "$CYAN-d$NC         EMBArk default installation"
  echo -e "$CYAN-F$NC         Installation of EMBArk for developers"
  echo -e "$CYAN-e$NC         Install EMBA only"
  echo -e "$CYAN-D$NC         Install for Docker deployment"
  echo -e "---------------------------------------------------------------------------"
  echo -e "$CYAN-U$NC         Uninstall EMBArk" # TODO
  echo -e "$CYAN-r$NC         Reinstallation of EMBArk with all dependencies"
  echo -e "$RED               ! Both options delete all Database-files as well !""$NC"
}

install_emba() {
  echo -e "\n$GREEN""$BOLD""Installation of the firmware scanner EMBA on host""$NC"

  if ! [[ -d ./emba ]]; then
    git clone https://github.com/e-m-b-a/emba.git
  else
    cd emba || exit 1
    git pull
    cd .. || exit 1
  fi

  cd emba || exit 1
  ./installer.sh -d
  cp ./config/emba_updater /etc/cron.daily/
  cd .. || exit 1
}

reset_docker() {
  echo -e "\n$GREEN""$BOLD""Reset EMBArk docker images""$NC"

  docker image ls -a

  docker container stop embark_db
  docker container stop embark_redis
  docker container stop embark_server
  docker container prune -f --filter "label=flag"

  if docker images | grep -qE "^embeddedanalyzer/emba"; then
    echo -e "\n$GREEN""$BOLD""Found EMBA docker environment - removing it""$NC"
    CONTAINER_ID=$(docker images | grep -E "embeddedanalyzer/emba" | awk '{print $3}')
    echo -e "$GREEN""$BOLD""Remove EMBA docker image""$NC"
    docker image rm "$IMAGE_ID" -f
  fi

  if docker images | grep -qE "^embark[[:space:]]*latest"; then
    echo -e "\n$GREEN""$BOLD""Found EMBArk docker environment - removing it""$NC"
    CONTAINER_ID=$(docker container ls -a | grep -E "embark_embark_1" | awk '{print $1}')
    echo -e "$GREEN""$BOLD""Stop EMBArk docker container""$NC"
    docker container stop "$CONTAINER_ID"
    echo -e "$GREEN""$BOLD""Remove EMBArk docker container""$NC"
    docker container rm "$CONTAINER_ID" -f
    echo -e "$GREEN""$BOLD""Remove EMBArk docker image""$NC"
    docker image rm embark:latest -f
  fi

  if docker images | grep -qE "^mysql[[:space:]]*latest"; then
    echo -e "\n$GREEN""$BOLD""Found mysql docker environment - removing it""$NC"
    CONTAINER_ID=$(docker container ls -a | grep -E "embark_db" | awk '{print $1}')
    echo -e "$GREEN""$BOLD""Stop mysql docker container""$NC"
    docker container stop "$CONTAINER_ID"
    echo -e "$GREEN""$BOLD""Remove mysql docker container""$NC"
    docker container rm "$CONTAINER_ID" -f
    echo -e "$GREEN""$BOLD""Remove mysql docker image""$NC"
    docker image rm mysql:latest -f
  fi

  if docker images | grep -qE "^redis[[:space:]]*5"; then
    echo -e "\n$GREEN""$BOLD""Found redis docker environment - removing it""$NC"
    CONTAINER_ID=$(docker container ls -a | grep -E "embark_redis" | awk '{print $1}')
    echo -e "$GREEN""$BOLD""Stop redis docker container""$NC"
    docker container stop "$CONTAINER_ID"
    echo -e "$GREEN""$BOLD""Remove redis docker container""$NC"
    docker container rm "$CONTAINER_ID" -f
    echo -e "$GREEN""$BOLD""Remove redis docker image""$NC"
    docker image rm redis:5 -f
  fi

  #networks

  if docker network ls | grep -E "embark_dev"; then
    echo -e "\n$GREEN""$BOLD""Found EMBArk_dev network - removing it""$NC"
    NET_ID=$(docker network ls | grep -E "embark_dev" | awk '{print $1}')
    echo -e "$GREEN""$BOLD""Remove EMBArk_dev network""$NC"
    docker network rm "$NET_ID" 
  fi

  if docker network ls | grep -E "embark_frontend"; then
    echo -e "\n$GREEN""$BOLD""Found EMBArk_frontend network - removing it""$NC"
    NET_ID=$(docker network ls | grep -E "embark_frontend" | awk '{print $1}')
    echo -e "$GREEN""$BOLD""Remove EMBArk_frontend network""$NC"
    docker network rm "$NET_ID" 
  fi

  if docker network ls | grep -E "embark_backend"; then
    echo -e "\n$GREEN""$BOLD""Found EMBArk_backend network - removing it""$NC"
    NET_ID=$(docker network ls | grep -E "embark_backend" | awk '{print $1}')
    echo -e "$GREEN""$BOLD""Remove EMBArk_backend network""$NC"
    docker network rm "$NET_ID" 
  fi
  
}

install_debs() {
  echo -e "\n$GREEN""$BOLD""Install debian packages for EMBArk installation""$NC"
  apt-get update -y
  if ! command -v git > /dev/null ; then
    apt-get install -y -q git
  fi
  if ! command -v docker > /dev/null ; then
    apt-get install -y -q docker.io
  fi
  if ! command -v docker-compose > /dev/null ; then
    apt-get install -y -q docker-compose
  fi
  # we need the django package on the host for generating the django SECRET_KEY and pip
  apt-get install -y -q python3-django python3-pip
}

install_daemon() {
  sed -i "s|BASEDIR|$DIR|g" ./embark.service
  ln -s /app/embark.service /etc/systemd/system/embark.service
  systemctl enable embark.service
}

install_embark_default() {
  echo -e "\n$GREEN""$BOLD""Installation of the firmware scanning environment EMBArk""$NC"
  apt-get install -y -q python3-dev default-libmysqlclient-dev build-essential pipenv

  #Add user for server
  useradd www-embark -G sudo -c "embark-server-user" -M -r --shell=/usr/sbin/nologin -d /app/www/
  echo 'www-embark ALL=(ALL) NOPASSWD: /app/emba/emba.sh' | EDITOR='tee -a' visudo

  #Add Symlink
  if ! [[ -d /app ]]; then
    ln -s "$PWD" /app || exit 1
  fi

  # daemon
  install_daemon

  #make dirs
  if ! [[ -d ./www ]]; then
    mkdir ./www
    mkdir ./www/media
    mkdir ./www/emba_logs
    mkdir ./www/static
    mkdir ./www/conf
  fi
  
  #install packages
  PIPENV_VENV_IN_PROJECT=1 pipenv install

  # download externals
  if ! [[ -d ./embark/static/external ]]; then
    echo -e "\n$GREEN""$BOLD""Downloading of external files, e.g. jQuery, for the offline usability of EMBArk""$NC"
    mkdir -p ./embark/static/external/{scripts,css}
    wget -O ./embark/static/external/scripts/jquery.js https://code.jquery.com/jquery-3.6.0.min.js
    wget -O ./embark/static/external/scripts/confirm.js https://cdnjs.cloudflare.com/ajax/libs/jquery-confirm/3.3.2/jquery-confirm.min.js
    wget -O ./embark/static/external/scripts/bootstrap.js https://cdn.jsdelivr.net/npm/bootstrap@5.1.1/dist/js/bootstrap.bundle.min.js
    wget -O ./embark/static/external/scripts/datatable.js https://cdn.datatables.net/v/bs5/dt-1.11.2/datatables.min.js
    wget -O ./embark/static/external/scripts/charts.js https://cdn.jsdelivr.net/npm/chart.js@3.5.1/dist/chart.min.js
    wget -O ./embark/static/external/css/confirm.css https://cdnjs.cloudflare.com/ajax/libs/jquery-confirm/3.3.2/jquery-confirm.min.css
    wget -O ./embark/static/external/css/bootstrap.css https://cdn.jsdelivr.net/npm/bootstrap@5.1.1/dist/css/bootstrap.min.css
    wget -O ./embark/static/external/css/datatable.css https://cdn.datatables.net/v/bs5/dt-1.11.2/datatables.min.css
    find ./embark/static/external/ -type f -exec sed -i '/sourceMappingURL/d' {} \;
  fi

  # setup .env
  DJANGO_SECRET_KEY=$(python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')
  RANDOM_PW=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 10 | head -n 1)
  echo -e "$ORANGE""$BOLD""Creating a Developer EMBArk configuration file .env""$NC"
  export DATABASE_NAME="embark"
  export DATABASE_USER="embark"
  export DATABASE_PASSWORD="$RANDOM_PW"
  export DATABASE_HOST="127.0.0.1"
  export DATABASE_PORT="3306"
  export MYSQL_PASSWORD="$RANDOM_PW"
  export MYSQL_USER="embark"
  export MYSQL_DATABASE="embark"
  export REDIS_HOST="127.0.0.1"
  export REDIS_PORT="7777"
  export SECRET_KEY="$DJANGO_SECRET_KEY"
  # this is for pipenv/django # TODO change after 
  {
    echo "DATABASE_NAME=$DATABASE_NAME"
    echo "DATABASE_USER=$DATABASE_USER" 
    echo "DATABASE_PASSWORD=$DATABASE_PASSWORD"
    echo "DATABASE_HOST=$DATABASE_HOST"
    echo "DATABASE_PORT=$DATABASE_PORT"
    echo "MYSQL_PASSWORD=$MYSQL_PASSWORD"
    echo "MYSQL_USER=$MYSQL_USER"
    echo "MYSQL_DATABASE=$MYSQL_DATABASE"
    echo "REDIS_HOST=$REDIS_HOST"
    echo "REDIS_PORT=$REDIS_PORT"
    echo "SECRET_KEY=$DJANGO_SECRET_KEY"
    echo "PYTHONPATH=${PYTHONPATH}:${PWD}"
  } > .env

  # download images for container
  docker-compose -f ./docker-compose.yml up --no-start
  docker-compose -f ./docker-compose.yml up &>/dev/null &
  sleep 30
  kill %1

  # activate daemon
  systemctl start embark.service

  echo -e "$GREEN""$BOLD""Ready to use \$sudo ./run-server.sh ""$NC"
  echo -e "$GREEN""$BOLD""Which starts the server on (0.0.0.0) port 80 ""$NC"
}

#install as docker-service
install_embark_docker(){
  echo -e "\n$GREEN""$BOLD""Installing EMBArk as docker-container""$NC"

  echo -e "\n$GREEN""$BOLD""Downloading of external files, e.g. jQuery, for the offline usability of EMBArk""$NC"
  mkdir -p ./embark/static/external/{scripts,css}
  wget -O ./embark/static/external/scripts/jquery.js https://code.jquery.com/jquery-3.6.0.min.js
  wget -O ./embark/static/external/scripts/confirm.js https://cdnjs.cloudflare.com/ajax/libs/jquery-confirm/3.3.2/jquery-confirm.min.js
  wget -O ./embark/static/external/scripts/bootstrap.js https://cdn.jsdelivr.net/npm/bootstrap@5.1.1/dist/js/bootstrap.bundle.min.js
  wget -O ./embark/static/external/scripts/datatable.js https://cdn.datatables.net/v/bs5/dt-1.11.2/datatables.min.js
  wget -O ./embark/static/external/scripts/charts.js https://cdn.jsdelivr.net/npm/chart.js@3.5.1/dist/chart.min.js
  wget -O ./embark/static/external/css/confirm.css https://cdnjs.cloudflare.com/ajax/libs/jquery-confirm/3.3.2/jquery-confirm.min.css
  wget -O ./embark/static/external/css/bootstrap.css https://cdn.jsdelivr.net/npm/bootstrap@5.1.1/dist/css/bootstrap.min.css
  wget -O ./embark/static/external/css/datatable.css https://cdn.datatables.net/v/bs5/dt-1.11.2/datatables.min.css
  find ./embark/static/external/ -type f -exec sed -i '/sourceMappingURL/d' {} \;

  # generating dynamic authentication for backend
  # for MYSQL root pwd check the logs of the container
  DJANGO_SECRET_KEY=$(python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')
  PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 )
  echo -e "$ORANGE""$BOLD""Creating a container EMBArk configuration file .env""$NC"
  export DATABASE_NAME="embark"
  export DATABASE_USER="embark"
  export DATABASE_PASSWORD="$PASSWORD"
  export DATABASE_HOST="172.23.0.5"
  export DATABASE_PORT="3306"
  export MYSQL_PASSWORD="$PASSWORD"
  export MYSQL_USER="embark"
  export MYSQL_DATABASE="embark"
  export REDIS_HOST="172.23.0.8"
  export REDIS_PORT="7777"
  export SECRET_KEY="$DJANGO_SECRET_KEY"
  # this is for pipenv/django # TODO change/lock after deploy
  {
    echo "DATABASE_NAME=$DATABASE_NAME"
    echo "DATABASE_USER=$DATABASE_USER" 
    echo "DATABASE_PASSWORD=$DATABASE_PASSWORD"
    echo "DATABASE_HOST=$DATABASE_HOST"
    echo "DATABASE_PORT=$DATABASE_PORT"
    echo "MYSQL_PASSWORD=$MYSQL_PASSWORD"
    echo "MYSQL_USER=$MYSQL_USER"
    echo "MYSQL_DATABASE=$MYSQL_DATABASE"
    echo "REDIS_HOST=$REDIS_HOST"
    echo "REDIS_PORT=$REDIS_PORT"
    echo "SECRET_KEY=$DJANGO_SECRET_KEY"
    echo "PYTHONPATH=${PYTHONPATH}:${PWD}:${PWD}/embark/"
  } > .env

  # setup dbs-container and detach build could be skipt
  echo -e "\n$GREEN""$BOLD""Building EMBArk docker images""$NC"
  docker-compose -f ./docker-compose-docker.yml build
  DB_RETURN=$?
  if [[ $DB_RETURN -eq 0 ]] ; then
    echo -e "$GREEN""$BOLD""Finished building EMBArk docker images""$NC"
  else
    echo -e "$ORANGE""$BOLD""Failed building EMBArk docker images""$NC"
  fi

  echo -e "\n$GREEN""$BOLD""Starting EMBArk docker images""$NC"
  docker-compose -f ./docker-compose-docker.yml up -d
  DS_RETURN=$?
  if [[ $DS_RETURN -eq 0 ]] ; then
    echo -e "$GREEN""$BOLD""Finished starting EMBArk""$NC"
  else
    echo -e "$ORANGE""$BOLD""Failed starting EMBArk""$NC"
  fi

  echo -e "$GREEN""$BOLD""Testing EMBArk installation""$NC"
  # need to wait a few seconds until everyting is up and running
  sleep 5
  if ! curl -XGET 'http://0.0.0.0:80' | grep -q embark; then
    echo -e "$ORANGE""$BOLD""Failed installing EMBArk - check the output from the installation process""$NC"
  fi

  echo -e "$GREEN""$BOLD""Server ready to use""$NC"
  echo -e "$GREEN""EMBArk is on (0.0.0.0) port 80 ""$NC"
}

install_embark_dev(){
  echo -e "\n$GREEN""$BOLD""Building Developent-Enviroment for EMBArk""$NC"
  apt-get install -y -q npm pycodestyle python3-pylint-django python3-dev default-libmysqlclient-dev build-essential pipenv bandit
  npm install -g jshint dockerlinter
  PIPENV_VENV_IN_PROJECT=1 pipenv install --dev
  # download externals
  if ! [[ -d ./embark/static/external ]]; then
    echo -e "\n$GREEN""$BOLD""Downloading of external files, e.g. jQuery, for the offline usability of EMBArk""$NC"
    mkdir -p ./embark/static/external/{scripts,css}
    wget -O ./embark/static/external/scripts/jquery.js https://code.jquery.com/jquery-3.6.0.min.js
    wget -O ./embark/static/external/scripts/confirm.js https://cdnjs.cloudflare.com/ajax/libs/jquery-confirm/3.3.2/jquery-confirm.min.js
    wget -O ./embark/static/external/scripts/bootstrap.js https://cdn.jsdelivr.net/npm/bootstrap@5.1.1/dist/js/bootstrap.bundle.min.js
    wget -O ./embark/static/external/scripts/datatable.js https://cdn.datatables.net/v/bs5/dt-1.11.2/datatables.min.js
    wget -O ./embark/static/external/scripts/charts.js https://cdn.jsdelivr.net/npm/chart.js@3.5.1/dist/chart.min.js
    wget -O ./embark/static/external/css/confirm.css https://cdnjs.cloudflare.com/ajax/libs/jquery-confirm/3.3.2/jquery-confirm.min.css
    wget -O ./embark/static/external/css/bootstrap.css https://cdn.jsdelivr.net/npm/bootstrap@5.1.1/dist/css/bootstrap.min.css
    wget -O ./embark/static/external/css/datatable.css https://cdn.datatables.net/v/bs5/dt-1.11.2/datatables.min.css
    find ./embark/static/external/ -type f -exec sed -i '/sourceMappingURL/d' {} \;
  fi

  # setup .env with dev network
  DJANGO_SECRET_KEY=$(python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')
  echo -e "$ORANGE""$BOLD""Creating a Developer EMBArk configuration file .env""$NC"
  export DATABASE_NAME="embark"
  export DATABASE_USER="embark"
  export DATABASE_PASSWORD="embark"
  export DATABASE_HOST="127.0.0.1"
  export DATABASE_PORT="3306"
  export MYSQL_PASSWORD="embark"
  export MYSQL_USER="embark"
  export MYSQL_DATABASE="embark"
  export REDIS_HOST="127.0.0.1"
  export REDIS_PORT="7777"
  export SECRET_KEY="$DJANGO_SECRET_KEY"
  export PYTHONPATH="${PYTHONPATH}:${PWD}:${PWD}/embark/"
  {
    echo "DATABASE_NAME=$DATABASE_NAME"
    echo "DATABASE_USER=$DATABASE_USER" 
    echo "DATABASE_PASSWORD=$DATABASE_PASSWORD"
    echo "DATABASE_HOST=$DATABASE_HOST"
    echo "DATABASE_PORT=$DATABASE_PORT"
    echo "MYSQL_PASSWORD=$MYSQL_PASSWORD"
    echo "MYSQL_USER=$MYSQL_USER"
    echo "MYSQL_DATABASE=$MYSQL_DATABASE"
    echo "REDIS_HOST=$REDIS_HOST"
    echo "REDIS_PORT=$REDIS_PORT"
    echo "SECRET_KEY=$DJANGO_SECRET_KEY"
    echo "PYTHONPATH=${PYTHONPATH}:${PWD}"
  } > .env

  #Add Symlink
  if ! [[ -d /app ]]; then
    ln -s "$PWD" /app || exit 1
  fi

  # daemon
  install_daemon

  # download images for container
  docker-compose -f ./docker-compose-dev.yml up --no-start
  docker-compose -f ./docker-compose-dev.yml up &>/dev/null &
  sleep 30
  kill %1

  echo -e "$GREEN""$BOLD""Ready to use \$sudo ./dev-tools/debug-server-start.sh""$NC"
  echo -e "$GREEN""$BOLD""Or use otherwise""$NC"
}

uninstall (){
  echo -e "$ORANGE""$BOLD""Deleting Configuration and reseting""$NC"

  #1 delete symlink
  echo -e "$ORANGE""$BOLD""Delete Symlink?""$NC"
  rm -i /app

  #2 delete www
  echo -e "$ORANGE""$BOLD""Delete Apache Directory""$NC"
  rm -R ./www

  #3 delete user www-embark and reset visudo
  echo -e "$ORANGE""$BOLD""Delete user""$NC"
  # sed -i 's/www\-embark\ ALL\=\(ALL\)\ NOPASSWD\:\ \/app\/emba\/emba.sh//g' /etc/sudoers #TODO doesnt work yet
  userdel www-embark

  #4 delete venv
  echo -e "$ORANGE""$BOLD""Delete Venv""$NC"
  rm -R ./.venv

  #5 delete .env
  echo -e "$ORANGE""$BOLD""Delete env""$NC"
  rm -R ./.env

  #6 delete shared volumes
  echo -e "$ORANGE""$BOLD""Delete Database-files""$NC"
  rm -R ./embark_db

  #7 delete all docker interfaces and containers + images
  reset_docker
  echo -e "$ORANGE""$BOLD""Consider running \$docker system prune""$NC"

  #8 delete/uninstall EMBA
  echo -e "$ORANGE""$BOLD""Delete EMBA?""$NC"
  docker network rm emba_runs
  rm -R ./emba

  #9 stop daemon
  systemctl stop embark.service
  systemctl disable embark.service

  #10 reset ownership etc
  # TODO
}

echo -e "\\n$ORANGE""$BOLD""EMBArk Installer""$NC\\n""$BOLD=================================================================$NC"
echo -e "$ORANGE""$BOLD""WARNING: This script can harm your environment!""$NC\n"

if [ "$#" -ne 1 ]; then
  echo -e "$RED""$BOLD""Invalid number of arguments""$NC"
  print_help
  exit 1
fi

while getopts eFUrdDh OPT ; do
  case $OPT in
    e)
      export EMBA_ONLY=1
      echo -e "$GREEN""$BOLD""Install only emba""$NC"
      ;;
    F)
      export DEV=1
      echo -e "$GREEN""$BOLD""Building Development-Enviroment""$NC"
      ;;
    U)
      export UNINSTALL=1
      echo -e "$GREEN""$BOLD""Uninstall EMBArk""$NC"
      ;;
    r)
      export UNINSTALL=1
      export REFORCE=1
      echo -e "$GREEN""$BOLD""Install all dependecies including docker cleanup""$NC"
      ;;
    d)
      export DEFAULT=1
      echo -e "$GREEN""$BOLD""Default installation of EMBArk""$NC"
      ;;
    D)
      export DOCKER=1
      echo -e "$GREEN""$BOLD""Install all dependecies for EMBArk-docker-container""$NC"
      ;;
    h)
      print_help
      exit 0
      ;;
    *)
      echo -e "$RED""$BOLD""Invalid option""$NC"
      print_help
      exit 1
      ;;
  esac
done

if ! [[ $EUID -eq 0 ]] && [[ $LIST_DEP -eq 0 ]] ; then
  echo -e "\\n$RED""Run EMBArk installation script with root permissions!""$NC\\n"
  print_help
  exit 1
fi

if [[ $REFORCE -eq 1 ]] && [[ $UNINSTALL -eq 1 ]]; then
  uninstall
elif [[ $UNINSTALL -eq 1 ]]; then
  uninstall
  exit 0
fi

install_debs
install_emba

if [[ $DEFAULT -eq 1 ]]; then
  install_embark_default
elif [[ $DEV -eq 1 ]]; then
  install_embark_dev
elif [[ $DOCKER -eq 1 ]]; then
  install_embark_docker
fi

exit 0