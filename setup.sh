#!/bin/bash

# check that we are running as root
if [ "$EUID" -ne 0 ]; then
    printf "The setup.sh script must be run as root! Try 'sudo ./setup.sh'\n"
    exit 1
fi

# test internet connection
wget -q --spider http://google.com
if [ $? -ne 0 ]; then
    printf "An internet connection is required to run this script! Use 'raspi-config' to connect to WiFi or use USB tethering from a phone.\n"
    exit 1
fi

# Source config
git_location="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"

# Check if config.sh exists
if [ ! -f "$git_location/config.sh" ]; then
    printf "config.sh not found! Please create a config.sh file in the root of the repository.\n"
    exit 1
fi

cd $git_location
source config.sh

# set git location
chown $box_user:$box_user -R $git_location

# enable SPI bus on taspberry pi
printf "[SYSTEM] Enabling SPI Bus...\n"
raspi-config nonint do_spi 0
if [ $? -ne 0 ]; then
    printf "[SYSTEM] Unable to enable SPI bus\n"
    exit 1
fi

# installing apt prerequisites
if [[ "$*" == *"--skip-apt"* ]]; then
    printf "[APT] Skipping installing APT prerequisites\n"
else
    printf "[APT] Installing APT Prerequisites...\n"
    apt-get update
    apt-get install -y python3-pip python3-smbus i2c-tools usbmuxd libatlas-base-dev
    if [ $? -ne 0 ]; then
        printf "[APT] Error installing apt packages\n"
        exit 1
    fi
fi

# installing pypi prerequisites
if [[ "$*" == *"--skip-pip"* ]]; then
    printf "[PIP] Skipping installing Python packages\n"
else
    printf "[PIP] Installing Python Packages...\n"
    pip install pySerial pandas influxdb-client
    if [ $? -ne 0 ]; then
        printf "[PIP] Error installing PyPI packages\n"
        exit 1
    fi
fi

if [ "$baro" = "y" ]; then
    baro_cmd="python3 ${git_location}/src/baroLogger/baroLogger.py -d ${baro_log_loc} -n ${baro_num}"

    printf "[BARO] Creating run files...\n"
    echo "#!/bin/bash" > $git_location/run/baro.sh
    echo "${baro_cmd}" >> $git_location/run/baro.sh
    chmod +x $git_location/run/baro.sh
    chown $box_user:$box_user $baro_log_loc

    # deploy service files
    printf "[BARO] Deploying systemd service files...\n"
    cp $git_location/services/baro-logger.service /etc/systemd/system/baro-logger.service
    systemctl daemon-reload
    systemctl enable baro-logger

    # creating logging directories
    printf "[BARO] Creating log directory...\n"
    mkdir -p $baro_log_loc
    chown $box_user:$box_user $baro_log_loc
fi

if [ "$anem" = "y" ]; then
    wind_cmd="python3 ${git_location}/src/windLogger/windLogger.py -d ${anem_log_loc}"

    printf "[ANEMOMETER] Creating run files...\n"
    echo "#!/bin/bash" > $git_location/run/wind.sh
    echo "${wind_cmd}" >> $git_location/run/wind.sh
    chmod +x $git_location/run/wind.sh

    # deploy service files
    printf "[ANEMOMETER] Deploying systemd service files...\n"
    cp $git_location/services/wind-logger.service /etc/systemd/system/wind-logger.service
    systemctl daemon-reload
    systemctl enable wind-logger

    printf "[ANEMOMETER] Creating log directory...\n"
    mkdir -p $anem_log_loc
    chown $box_user:$box_user $anem_log_loc
fi

# check if influxdb posting is required
if [ "$influxdb" = "y" ]; then
    datasender_cmd="python3 ${git_location}/src/dataSender/dataSender.py"

    influxdb_cmd="${influxdb_hostname} ${influxdb_org} ${influxdb_token} ${influxdb_bucket}"
    
    if [ "$baro" = "y" ]; then
        influxdb_cmd="$influxdb_cmd -l ${baro_log_loc}"
    fi

    if [ "$anem" = "y" ]; then
        influxdb_cmd="$influxdb_cmd -l ${anem_log_loc}"
    fi

    printf "[INFLUXDB] Creating run files...\n"
    echo "#!/bin/bash" > $git_location/run/datasender.sh
    echo "${datasender_cmd} ${influxdb_cmd}" >> $git_location/run/datasender.sh
    chmod +x $git_location/run/datasender.sh
    chown $box_user:$box_user $git_location/run/datasender.sh

    printf "[INFLUXDB] Deploying systemd service files...\n"
    cp $git_location/services/datasender* /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable datasender.timer
fi

if [ "$frp" = "y" ]; then
    # Install FRPC
    if [ ! -f "/usr/local/bin/frpc" ]; then
        printf "[FRP] Installing FRPC...\n"
        wget -nv $frp_download -O /tmp/frp.tar.gz
        tar -xf /tmp/frp.tar.gz -C /tmp
        cp /tmp/frp*/frpc /usr/local/bin/frpc
        chmod +x /usr/local/bin/frpc
        rm -rf /tmp/frp*
    fi

    frpc_cmd="frpc tcp --server_addr=${frp_hostname}:${frp_port} --token=${frp_token} --local_port=22 --local_ip=127.0.0.1 --remote_port=${frp_bind_port} --proxy_name=${box_name} --tls_enable"

    printf "[FRP] Creating run files...\n"
    echo "#!/bin/bash" > $git_location/run/frpc.sh
    echo "${frpc_cmd}" >> $git_location/run/frpc.sh
    chmod +x $git_location/run/frpc.sh
    chown $box_user:$box_user $git_location/run/frpc.sh

    printf "[FRP] Deploying systemd service files...\n"
    cp $git_location/services/frpc* /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable frpc.service
fi

printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Setup script complete!"
echo ""
echo "For barometer logging control, use 'systemctl start baro-logger' or 'systemctl stop baro-logger'"
echo "To view logs for baro-logger, use 'journalctl -eu baro-logger'"
echo ""
echo "For wind speed logging control, use 'systemctl start wind-logger' or 'systemctl stop wind-logger'"
echo "To view logs for wind-logger, use 'journalctl -eu wind-logger'"
echo ""
echo "You can rerun this script anytime to change parameters of the deployment"
echo "If this is the first time this script was run, you'll need to reboot"
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
