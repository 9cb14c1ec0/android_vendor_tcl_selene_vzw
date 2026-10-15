#!/vendor/bin/sh
OFFSET=30610
CN=15
CN_TCL_FLAG=6
CN_BITMAP=8
OFFSET_BITMAP=""
TCL_FLAG="TCL_KO"
module_disabled=""
module_enabled=""
operate_param=""

module_array=(
"all_ko"
"tcl_uxthread"
"process_reclaim"
"tkperf"
"tcl_limit_mediascanner"
"tcl_mm_reclaim_opt"
"iolimit"
"cpu_perf_monitor"
"tcl_perf_bdt"
)

function wr_block(){
    echo -n "${TCL_FLAG}$1" | dd of=/dev/block/by-name/oembin seek=$OFFSET bs=1 conv=notrunc
    log -t perf_ko_ctrl  "$2 ${module_disabled} ${module_enabled} ko done, block data ${TCL_FLAG}$1 written"
}

function check_reset(){
    local tcl_ko_flag=`dd if=/dev/block/by-name/oembin  skip=$OFFSET bs=1 count=$CN_TCL_FLAG  of=/dev/stdout;`
    local tcl_bitmap=`dd if=/dev/block/by-name/oembin  skip=$OFFSET_BITMAP bs=1 count=$CN_BITMAP  of=/dev/stdout`


    if [[ "$tcl_ko_flag" != "$TCL_FLAG" ]]; then
        log -t perf_ko_ctrl  "oembin no data of TCL_KO, first time operate"
        tcl_ko_flag=$TCL_FLAG
        tcl_bitmap="00000000" #hex 32 bit
        echo -n "${TCL_FLAG}${tcl_bitmap}" | dd of=/dev/block/by-name/oembin seek=$OFFSET bs=1 conv=notrunc
        log -t perf_ko_ctrl  "reset oembblock as ${TCL_FLAG}${tcl_bitmap} in offset $OFFSET"
    fi
}


function prepare_param(){
    local  enbale="`echo $operate_param|grep enable`"
    local  disable="`echo $operate_param|grep disable`"

    if [[  "${enbale}W" == "W" ]]; then
        log -t perf_ko_ctrl "enable  module name none"
        module_enabled=""
    else
        module_enabled=`echo  $operate_param |cut  -d ":" -f 2`
    fi

    if [[  "${disable}W" == "W" ]]; then
        log -t perf_ko_ctrl "disable  module name none"
        module_disabled=""
    else
        module_disabled=`echo $operate_param  | cut  -d ":" -f 2`
    fi

    log -t perf_ko_ctrl  "operate_param:$operate_param,disable module name:$module_disabled, enbale  module name:$module_enabled"

    if [[  "${disable}W" == "W" ]]  && [[  "${enbale}W" == "W" ]]; then 
        log -t perf_ko_ctrl  "no param found, nothing to do!"
        return 1
    fi

}

function check_ko_set(){
    local tcl_bitmap=`dd if=/dev/block/by-name/oembin  skip=$OFFSET_BITMAP bs=1 count=$CN_BITMAP  of=/dev/stdout`
    local  enable="0"

    #tcl_bitmap="`printf '%08x\n' $tcl_bitmap`"
    log -t perf_ko_ctrl  "read emmc, tcl_bitmap:0x${tcl_bitmap} for check_ko is set?"

    for i in "${!module_array[@]}";
    do
        if [[ $i -gt 31 ]]; then
            log -t perf_ko_ctrl "err:modules is bigger than 32"
            exit 0
        fi

        enable="0"
        let  enable="0x${tcl_bitmap}&1<<$i"

        if [[ "${module_disabled}W" == "${module_array[$i]}W"  ]] && [[ $enable != "0" ]]; then
            log -t perf_ko_ctrl "disable ${module_disabled} is same as emmc, bye!"
            return 1
        fi

        if [[ "${module_enabled}W" == "${module_array[$i]}W"  ]] && [[ $enable == "0"  ]]; then
            log -t perf_ko_ctrl "enable ${module_enabled} is same as emmc, bye!"
            return 1
        fi

    done
}

function prepare(){
    let OFFSET_BITMAP=$OFFSET+$CN_TCL_FLAG

    check_reset
    prepare_param
    if [[ $? -eq 1 ]]; then
       return 1
    fi
    check_ko_set
}

function deal_end(){
    log -t perf_ko_ctrl  "param:$operate_param finished!"
}

#data: TCL_KOxxxxxxxx
function update_bitmap(){

    local tcl_ko_flag=`dd if=/dev/block/by-name/oembin  skip=$OFFSET bs=1 count=$CN_TCL_FLAG  of=/dev/stdout;`
    local tcl_bitmap=`dd if=/dev/block/by-name/oembin  skip=$OFFSET_BITMAP bs=1 count=$CN_BITMAP  of=/dev/stdout`
    local  ko_found="0"

    log -t perf_ko_ctrl "read from oembin,tcl_ko_flag:$tcl_ko_flag at $OFFSET, bitmap:0x$tcl_bitmap at $OFFSET_BITMAP"


    for i in "${!module_array[@]}";
    do
        if [[ $i -gt 31 ]]; then
            log -t perf_ko_ctrl "err:modules is bigger than 32"
            exit 0
        fi

        if [[ "${module_disabled}W" == "${module_array[$i]}W"  ]]; then
             let "tcl_bitmap=0x${tcl_bitmap}|1<<$i"
             tcl_bitmap="`printf '%08x\n' $tcl_bitmap`"
             ko_found="disable"
             break;
        fi

        if [[ "${module_enabled}W" == "${module_array[$i]}W"  ]]; then
             let "tcl_bitmap=0x${tcl_bitmap}&~(1<<$i)"
             tcl_bitmap="`printf '%08x\n' $tcl_bitmap`"
             ko_found="enable"
             break;
        fi
    done

# if it is all_ko, close all bit
#    if [[ "${module_disabled}W" == "all_koW" ]] || [[ "${module_enabled}W" == "all_koW" ]]; then 
#        for i in "${!module_array[@]}";
#        do
#            if [[ $i -gt 31 ]]; then
#                log -t perf_ko_ctrl "err:modules is bigger than 32"
#                exit 0
#            fi
#
#            if [[ "${module_disabled}W" == "all_koW"  ]]; then
#                let "tcl_bitmap=0x${tcl_bitmap}|1<<$i"
#                tcl_bitmap="`printf '%08x\n' $tcl_bitmap`"
#                ko_found="disable"
#            fi
#
#            if [[ "${module_enabled}W" == "all_koW"  ]]; then
#                let "tcl_bitmap=0x${tcl_bitmap}&~(1<<$i)"
#                tcl_bitmap="`printf '%08x\n' $tcl_bitmap`"
#                ko_found="enable"
#            fi
#        done
#    fi

    if [[ $ko_found != "0" ]]; then
        wr_block $tcl_bitmap $ko_found 
    else
        log -t perf_ko_ctrl "not find:${module_disabled} ${module_enabled}, or param is none"
    fi
}

function ko_ctrl_loop() {
    while true;
    do
        if [[ ! -e /proc/tcl_modules_ctrl_msg ]]; then
            log -t perf_ko_ctrl "ko not load?"
            sleep 30
            continue
        fi

        log -t perf_ko_ctrl "param wait..."
        operate_param="`cat /proc/tcl_modules_ctrl_msg`"
        log -t perf_ko_ctrl "param:$operate_param got!"

        prepare
        if [[ $? -eq 1 ]];then
            continue
        fi
        update_bitmap
        deal_end
    done

    log -t perf_ko_ctrl "exit!"
}

ko_ctrl_loop
