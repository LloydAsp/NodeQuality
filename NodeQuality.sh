#!/bin/bash

current_time="$(date +%Y_%m_%d_%H_%M_%S)"
work_dir=".nodequality$current_time"
bench_os_url="https://github.com/LloydAsp/NodeQuality/releases/download/v0.0.1/BenchOs.tar.gz"
raw_file_prefix="https://raw.githubusercontent.com/LloydAsp/NodeQuality/refs/heads/main"

if uname -m | grep -Eq 'arm|aarch64'; then
    bench_os_url="https://github.com/LloydAsp/NodeQuality/releases/download/v0.0.1/BenchOs-arm.tar.gz"
fi

header_info_filename=header_info.log
basic_info_filename=basic_info.log
yabs_json_filename=yabs.json
ip_quality_filename=ip_quality.log
ip_quality_json_filename=ip_quality.json
net_quality_filename=net_quality.log
net_quality_json_filename=net_quality.json
backroute_trace_filename=backroute_trace.log
backroute_trace_json_filename=backroute_trace.json
port_filename=port.log

function start_ascii(){
    echo -ne "\e[1;36m"
    cat <<- EOF


███╗   ██╗ ██████╗ ██████╗ ███████╗ ██████╗ ██╗   ██╗ █████╗ ██╗     ██╗████████╗██╗   ██╗
████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔═══██╗██║   ██║██╔══██╗██║     ██║╚══██╔══╝╚██╗ ██╔╝
██╔██╗ ██║██║   ██║██║  ██║█████╗  ██║   ██║██║   ██║███████║██║     ██║   ██║    ╚████╔╝ 
██║╚██╗██║██║   ██║██║  ██║██╔══╝  ██║▄▄ ██║██║   ██║██╔══██║██║     ██║   ██║     ╚██╔╝  
██║ ╚████║╚██████╔╝██████╔╝███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗██║   ██║      ██║   
╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝      ╚═╝   
                                                                                          
                                                                             
Benchmark script for server, collects basic hardware information, IP quality and network quality

The benchmark will be performed in a temporary system, and all traces will be deleted after that.
Therefore, it has no impact on the original environment and supports almost all linux systems.

Author: Lloyd@nodeseek.com
Github: github.com/LloydAsp/NodeQuality
Command: bash <(curl -sL https://run.NodeQuality.com)

	EOF
    echo -ne "\033[0m"
}

function _red() {
    echo -e "\033[0;31m$1\033[0m"
}

function _yellow() {
    echo -e "\033[0;33m$1\033[0m"
}

function _blue() {
    echo -e "\033[0;36m$1\033[0m"
}

function _green() {
    echo -e "\033[0;32m$1\033[0m"
}

function _red_bold() {
    echo -e "\033[1;31m$1\033[0m"
}

function _yellow_bold() {
    echo -e "\033[1;33m$1\033[0m"
}

function _blue_bold() {
    echo -e "\033[1;36m$1\033[0m"
}

function _green_bold() {
    echo -e "\033[1;32m$1\033[0m"
}



function pre_init(){
    mkdir -p "$work_dir"
    cd $work_dir
    work_dir="$(pwd)"
}

function pre_cleanup(){
    # incase interupted last time
    clear_mount
    if [[ "$work_dir" == *"nodequality"* ]]; then
        rm -rf "${work_dir}"/*
    else
        echo "Error: work_dir does not contain 'nodequality'!"
        exit 1
    fi
}

function clear_mount(){
    swapoff $work_dir/swap 2>/dev/null

    umount $work_dir/BenchOs/proc/ 2> /dev/null
    umount $work_dir/BenchOs/sys/ 2> /dev/null
    umount -R $work_dir/BenchOs/dev/ 2> /dev/null
    umount "$work_dir/BenchOs/hostinfo/os-release" 2> /dev/null
}

function load_bench_os(){
    cd $work_dir
    rm -rf BenchOs

    curl "-L#o" BenchOs.tar.gz $bench_os_url
    tar -xzf BenchOs.tar.gz     
    cd $work_dir/BenchOs

    mount -t proc /proc proc/
    mount --bind /sys sys/
    mount --rbind /dev dev/
    mount --make-rslave dev

    rm etc/resolv.conf 2>/dev/null
    cp /etc/resolv.conf etc/resolv.conf

    mkdir hostinfo
    touch hostinfo/os-release
    mount --bind /etc/os-release hostinfo/os-release
}

function chroot_run(){
    chroot $work_dir/BenchOs /bin/bash -c "$*"
}

function load_part(){
    # gb5-test.sh, swap part
    . <(curl -sL "$raw_file_prefix/part/swap.sh")
}

function load_3rd_program(){
    chroot_run wget https://github.com/nxtrace/NTrace-core/releases/download/v1.3.7/nexttrace_linux_amd64 -qO /usr/local/bin/nexttrace
    chroot_run chmod u+x /usr/local/bin/nexttrace
}

function run_header(){
    chroot_run bash <(curl -Ls "$raw_file_prefix/part/header.sh")
}

yabs_url="$raw_file_prefix/part/yabs.sh"
function run_yabs(){
    if ! curl -s 'https://browser.geekbench.com' --connect-timeout 5 >/dev/null; then
        chroot_run bash <(curl -sL $yabs_url) -s -- -gi -w /result/$yabs_json_filename
        echo -e "对 IPv6 单栈的服务器来说进行测试没有意义，\n因为要将结果上传到 browser.geekbench.com 后才能拿到最后的跑分，\n但 browser.geekbench.com 仅有 IPv4、不支持 IPv6，测了也是白测。"
    else
        virt=$(dmidecode -s system-product-name 2> /dev/null || virt-what | grep -v redhat | head -n 1 || echo "none")
        if [[ "${virt,,}" != "lxc" ]]; then
            check_swap 1>&2
        fi
        # 服务器一般测geekbench5即可
        chroot_run bash <(curl -sL $yabs_url) -s -- -5i -w /result/$yabs_json_filename
    fi

    chroot_run bash <(curl -sL $raw_file_prefix/part/sysbench.sh)
}

function run_ip_quality(){
    chroot_run bash <(curl -Ls IP.Check.Place) -n -o /result/$ip_quality_json_filename
}

function run_net_quality(){
    local params=""
    [[ "$run_net_quality_test" =~ ^[Ll]$ ]] && params=" -L"
    chroot_run bash <(curl -Ls Net.Check.Place) $params -n -o /result/$net_quality_json_filename
}

function run_net_trace(){
    chroot_run bash <(curl -Ls Net.Check.Place) -R -n -S 123 -o /result/$backroute_trace_json_filename
}

uploadAPI="https://api.nodequality.com/api/v1/record"
function upload_result(){

    chroot_run zip -j - "/result/*" > $work_dir/result.zip

    base64 $work_dir/result.zip | curl -X POST  --data-binary @- $uploadAPI

    echo
}

function post_cleanup(){
    chroot_run umount -R /dev &> /dev/null
    clear_mount

    post_check_mount

    rm -rf $work_dir/BenchOs

    if [[ "$work_dir" == *"nodequality"* ]]; then
        rm -rf "${work_dir}"/
    else
        echo "Error: work_dir does not contain 'nodequality'!"
        exit 1
    fi

    exit 1
}

function sig_cleanup(){
    trap '' INT TERM SIGHUP EXIT
    _red "Cleaning, please wait a moment."
    post_cleanup
}

function post_check_mount(){
    if mount | grep nodequality$current_time ; then
        echo "出现了预料之外的情况，BenchOs目录的挂载未被清理干净，保险起见请重启后删除该目录" | tee $work_dir/error.log >&2
        exit
    fi
}


function ask_question(){
    yellow='\033[1;33m'  # Set yellow color
    reset='\033[0m'      # Reset to default color

    echo -en "${yellow}Run Basic Info test? (Enter for default 'y') [y/n]: ${reset}"
    read run_yabs_test
    run_yabs_test=${run_yabs_test:-y}

    echo -en "${yellow}Run IPQuality test? (Enter for default 'y') [y/n]: ${reset}"
    read run_ip_quality_test
    run_ip_quality_test=${run_ip_quality_test:-y}

    echo -en "${yellow}Run NetQuality test? (Enter for default 'y', 'l' for low-data mode) [y/l/n]: ${reset}"
    read run_net_quality_test
    run_net_quality_test=${run_net_quality_test:-y}

    echo -en "${yellow}Run Backroute Trace test? (Enter for default 'y') [y/n]: ${reset}"
    read run_net_trace_test
    run_net_trace_test=${run_net_trace_test:-y}
}

function main(){
    trap 'sig_cleanup' INT TERM SIGHUP EXIT

    start_ascii

    ask_question

    _green_bold 'Clean Up before Installation'
    pre_init
    pre_cleanup
    _green_bold 'Load BenchOs'
    load_bench_os

    load_part
    load_3rd_program
    _green_bold 'Basic Info'

    result_directory=$work_dir/BenchOs/result
    mkdir -p $result_directory
    run_header > $result_directory/$header_info_filename

    if [[ "$run_yabs_test" =~ ^[Yy]$ ]]; then
        _green_bold 'Running Basic Info Test...'
        run_yabs | tee $result_directory/$basic_info_filename
    fi

    if [[ "$run_ip_quality_test" =~ ^[Yy]$ ]]; then
        _green_bold 'Running IP Quality Test...'
        run_ip_quality | tee $result_directory/$ip_quality_filename
    fi

    if [[ "$run_net_quality_test" =~ ^[YyLl]$ ]]; then
        _green_bold 'Running Network Quality Test...'
        run_net_quality | tee $result_directory/$net_quality_filename
    fi

    if [[ "$run_net_trace_test" =~ ^[Yy]$ ]]; then
        _green_bold 'Running Backroute Trace...'
        run_net_trace | tee $result_directory/$backroute_trace_filename
    fi

    upload_result
    _green_bold 'Clean Up after Installation'
    post_cleanup
}

main
