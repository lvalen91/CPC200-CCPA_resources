#!/bin/sh
########################
#File:    getFuncModule.sh
#author:  hcw
#version: 1.0.0
#date:    17May23
########################

getA15MdLinkModule() {
    if [ -e /etc/mdlink_modules ]; then
        MDLINK=$(cat /etc/mdlink_modules)
    fi
}

STARTMODULE='Boot128'
USBMODULE='USBDrv'
COMMODULE='Common'
SERMODULE='Service'
UPGMODULE='Upg'
WIFICHIPPATH='/sys/bus/sdio/devices/mmc0:0001:1/device'
CUSVERPATH='/etc/box_version'
WEBMODULE='WebPUBLIC'

for line in $(cat "$WIFICHIPPATH")
do
    CHIPTYPE=$line
done

case $CHIPTYPE in
    0xb822)
        WIFIMODULE='RTL8822BS' #wifi驱动模块
    ;;
    0x4354)
        WIFIMODULE='BCM4354'
    ;;
    0x9149)
        WIFIMODULE='SD8987'
    ;;
    0x4358 | 0xaa31)
        WIFIMODULE='BCM4358'
    ;;
    0x4335)
        WIFIMODULE='BCM4335'
    ;;
    0xc822)
        WIFIMODULE='RTL8822CS'
    ;;
    0x9159)
        WIFIMODULE='IW416'
    ;;
esac

INPARA=$(cat /etc/box_product_type)
#product_type没有下划线的客制化版本加上PUBLIC
if [ -n "$(echo "$INPARA" | grep "_")" ]; then
    CUSMODULE="Cus_${INPARA}"
else
    CUSMODULE="Cus_${INPARA}_PUBLIC" #客户UI模块,A15系列是客制化文件，没有UI，可能含有APK
fi

#get Web module
Cusver=$(hexdump "$CUSVERPATH" | awk '{print $2}' | sed -n '1p') #获取客户版本
case $Cusver in
    00ff)
        WEBMODULE='WebPUBLIC'
    ;;
    0002)
        case "$INPARA" in
            *JUPAZIP*)
                WEBMODULE='WebJUPAZIP'
            ;;
            *)
                WEBMODULE='WebAUTOKIT'
            ;;
        esac
    ;;
    0005)
        WEBMODULE='WebDDDCAT'
	;;
esac

ISA15=$(printf '%.1s' "$INPARA") #是否为A15系列
if [ "$ISA15" = "A" ]
then
    if [ -z "${INPARA##*A15X*}" ] #A15X 国内支持ICCOA
    then
            MDLINK='CarPlay,HiCar,ICCOA,AndroidAuto,CarLife'
    else
        if [ -z "${INPARA##*Auto_Box*}" ]
        then
		MDLINK='CarPlay,AndroidAuto,AndroidMirror,iOSMirror' #手机互联模块
        elif [ -z "${INPARA##*A15W*}" ] #A15W
        then
		MDLINK='CarPlay,AndroidAuto,AndroidMirror,iOSMirror,HiCar'
        elif [ -z "${INPARA##*A15H*}" ] #A15H
        then
            MDLINK='CarPlay,HiCar'
        elif [ -z "${INPARA##*A15U*}" ] #A15U
        then
            MDLINK='CarPlay,HiCar,AndroidAuto'
        fi
    fi
    getA15MdLinkModule
else
    HUType=${INPARA%%2*} #判定第一个'2'前面的字符以获取车机互联类型
#   echo ${HUType}
    case $HUType in
    U)
        HULINK='HUCP' #车机互联模块
        if [ -z "${INPARA##*U2AC*}" ] #U2AC支持两种车机互联
        then
            HULINK='HUCP,HUAA'
            MDLINK='CarPlay,AndroidAuto'
        elif [ -z "${INPARA##*U2AW*}" ] #U2AW
        then
            MDLINK='CarPlay,AndroidAuto'
        elif [ -z "${INPARA##*U2W*}" ] #U2W
        then
            MDLINK='CarPlay'
        elif [ -z "${INPARA##*U2HC*}" ] #U2HC
        then
            MDLINK='CarPlay,HiCar'
        elif [ -z "${INPARA##*U2HW*}" ] #U2HW
        then
            MDLINK='HiCar'
        elif [ -z "${INPARA##*U2HP*}" ] #U2HP
        then
            MDLINK='HiCar'
        elif [ -z "${INPARA##*U2IW*}" ] #U2IW
        then
            MDLINK='ICCOA'
        elif [ -z "${INPARA##*U2OW*}" ] #U2OW
        then
            MDLINK='AndroidAuto'
        elif [ -z "${INPARA##*U2HI*}" ] #U2HI
        then
            MDLINK='HiCar,ICCOA'
        elif [ -z "${INPARA##*U2D*}" ] #U2D
        then
            MDLINK='CarLife'
        elif [ -z "${INPARA##*U2F*}" ] #U2F
        then
            MDLINK='CarPlay'
        fi
    ;;
    UC)
        WEBMODULE='WebC2X'
        #${INPARA} == *"_"*
        #${ISPUB} == *"D"*
        #${INPARA} == *"D"*
        if [ -n "$(echo "$INPARA" | grep "_")" ]; then  #'_'是product_type的子串
            ISPUB=${INPARA%%"_"*}
            if [ -n "$(echo "$ISPUB" | grep "D")" ]; then  #判定'D'是否是子串
                HULINK='HUBDCL'
            else
                HULINK='HUCL'
            fi
        else
            if [ -n "$(echo "$INPARA" | grep "D")" ]; then  #判定'D'是否是子串
                HULINK='HUBDCL'
            else
                HULINK='HUCL'
            fi
        fi

        if [ -z "${INPARA##*UC2W*}" ] #UC2W
        then
            MDLINK='CarPlay'
        elif [ -z "${INPARA##*UC2HW*}" ] #UC2HW
        then
            MDLINK='HiCar'
        elif [ -z "${INPARA##*UC2HC*}" ] #UC2HC
        then
            MDLINK='CarPlay,HiCar'
        elif [ -z "${INPARA##*UC2AW*}" ] #UC2AW
        then
            MDLINK='AndroidAuto'
        elif [ -z "${INPARA##*UC2CA*}" ] #UC2CA
        then
            MDLINK='AndroidAuto,CarPlay'
        elif [ -z "${INPARA##*UC2HP*}" ] #UC2HP
        then
            MDLINK='HiCar'
        fi
    ;;
    O)
        HULINK='HUAA' #车机互联模块
        if [ -z "${INPARA##*O2W*}" ] #O2W
        then
            MDLINK='AndroidAuto'
        fi
    ;;
    H)
        HULINK='HUHC' #车机互联模块
        if [ -z "${INPARA##*H2W*}" ] #H2W
        then
            MDLINK='HiCar'
        fi
    esac
fi
	echo "${STARTMODULE},${USBMODULE},${COMMODULE},${SERMODULE},${UPGMODULE},${HULINK},${MDLINK},${WIFIMODULE},${WEBMODULE},${CUSMODULE}"
