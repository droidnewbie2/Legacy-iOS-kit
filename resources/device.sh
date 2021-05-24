#!/bin/bash

CheckDeviceState() {
    # CheckDeviceState - Checks the device state (depending on device, must be in normal, recovery, or DFU mode)
    # Detected device state will be set to variable DeviceState
    
    Log "Finding device in normal mode..."
    ideviceinfo2=$($ideviceinfo -s)
    if [[ $? != 0 ]]; then
        Log "Finding device in DFU/recovery mode..."
        DeviceState="$($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-)" # Changed irecovery2 to DeviceState
    else
        DeviceState="Normal"
    fi
}

FindDevice() {
    # FindDevice - Function to find and wait for device in DFU/recovery
    # Argument ($1) should be either "DFU" or "Recovery"
    # When detected, device state will be set to variable DeviceState
    
    local USB
    [[ $1 == "DFU" ]] && USB=1227 || USB=1281
    
    Log "Finding device in $1 mode..."
    while [[ $DeviceState != "DFU" ]]; do
        [[ $platform == "linux" ]] && DeviceState=$(lsusb | grep -c $USB)
        [[ $platform == "macos" && $($irecovery -q 2>/dev/null | grep "MODE" | cut -c 7-) == "$1" ]] && DeviceState=1
        [[ $DeviceState == 1 ]] && DeviceState="$1"
        sleep 1
    done
    Log "Found device in $1 mode."
}

GetDeviceValues() {
    # GetDeviceValues - Get the device values using irecovery and/or ideviceinfo
    # Also set baseband and other values depending on the detected device
    # It is also used to check if the device is supported or not
    # This is used on the Main function
    
    CheckDeviceState
    
    if [[ $DeviceState == "DFU" || $DeviceState == "Recovery" ]]; then
        ProductType=$($irecovery -q | grep "PTYP" | cut -c 7-)
        
        # If not on Linux, user must enter ProductType manually
        # todo automate this for macs as well
        if [[ ! $ProductType ]]; then
            while [[ ! $ProductType ]]; do
                read -p "$(Input 'Enter ProductType (eg. iPad2,1):')" ProductType
            done
        fi
        UniqueChipID=$((16#$(echo $($irecovery -q | grep "ECID" | cut -c 7-) | cut -c 3-)))
        ProductVer="Unknown"
    else
        ProductType=$(echo "$ideviceinfo2" | grep "ProductType" | cut -c 14-)
        [[ ! $ProductType ]] && ProductType=$($ideviceinfo | grep "ProductType" | cut -c 14-)
        ProductVer=$(echo "$ideviceinfo2" | grep "ProductVer" | cut -c 17-)
        VersionDetect=$(echo $ProductVer | cut -c 1)
        UniqueChipID=$(echo "$ideviceinfo2" | grep "UniqueChipID" | cut -c 15-)
        UniqueDeviceID=$(echo "$ideviceinfo2" | grep "UniqueDeviceID" | cut -c 17-)
    fi
    
    if [[ ! $ProductType ]]; then
        Error "No device detected. Please put the device in normal mode before proceeding" \
        "Recovery or DFU mode is also applicable depending on your device (see the README)"
    fi
    
    Baseband=0
    BasebandURL=$(cat $Firmware/13G37/url 2>/dev/null) # iOS 9.3.6
    Firmware=resources/firmware/$ProductType
    
    if [[ $ProductType == "iPad2,2" ]]; then
        BasebandURL=$(cat $Firmware/13G36/url) # iOS 9.3.5
        Baseband="ICE3_04.12.09_BOOT_02.13.Release.bbfw"
        BasebandSHA1="e6f54acc5d5652d39a0ef9af5589681df39e0aca"
        
    elif [[ $ProductType == "iPad2,3" ]]; then
        Baseband="Phoenix-3.6.03.Release.bbfw"
        BasebandSHA1="8d4efb2214344ea8e7c9305392068ab0a7168ba4"
        
    elif [[ $ProductType == "iPad2,6" || $ProductType == "iPad2,7" ]]; then
        Baseband="Mav5-11.80.00.Release.bbfw"
        BasebandSHA1="aa52cf75b82fc686f94772e216008345b6a2a750"
        
    elif [[ $ProductType == "iPad3,2" || $ProductType == "iPad3,3" ]]; then
        Baseband="Mav4-6.7.00.Release.bbfw"
        BasebandSHA1="a5d6978ecead8d9c056250ad4622db4d6c71d15e"
        
    elif [[ $ProductType == "iPhone4,1" ]]; then
        Baseband="Trek-6.7.00.Release.bbfw"
        BasebandSHA1="22a35425a3cdf8fa1458b5116cfb199448eecf49"
        
    elif [[ $ProductType == "iPad3,5" || $ProductType == "iPad3,6" ||
            $ProductType == "iPhone5,1" || $ProductType == "iPhone5,2" ]]; then
        BasebandURL=$(cat $Firmware/14G61/url) # iOS 10.3.4
        Baseband="Mav5-11.80.00.Release.bbfw"
        BasebandSHA1="8951cf09f16029c5c0533e951eb4c06609d0ba7f"
        
    elif [[ $ProductType == "iPad4,2" || $ProductType == "iPad4,3" || $ProductType == "iPad4,5" ||
            $ProductType == "iPhone6,1" || $ProductType == "iPhone6,2" ]]; then
        BasebandURL=$(cat $Firmware/14G60/url)
        Baseband="Mav7Mav8-7.60.00.Release.bbfw"
        BasebandSHA1="f397724367f6bed459cf8f3d523553c13e8ae12c"
        
    elif [[ $ProductType != "iPad2"* && $ProductType != "iPad3"* && $ProductType != "iPad4,1" &&
            $ProductType != "iPad4,4" && $ProductType != "iPod5,1" && $ProductType != "iPhone5"* ]]; then
        Error "Your device $ProductType is not supported."
    fi
    
    if [[ $ProductType == "iPad2"* || $ProductType == "iPad3,1" || $ProductType == "iPad3,2" ||
          $ProductType == "iPad3,3" || $ProductType == "iPhone4,1" || $ProductType == "iPod5,1" ]]; then
        DeviceProc=5
    elif [[ $ProductType == "iPad3,4" || $ProductType == "iPad3,5" ||
            $ProductType == "iPad3,6" || $ProductType == "iPhone5"* ]]; then
        DeviceProc=6
    elif [[ $ProductType == "iPhone6"* || $ProductType == "iPad4"* ]]; then
        DeviceProc=7
    fi
    
    HWModel=$(cat $Firmware/hwmodel)
    
    if [[ $ProductType == "iPod5,1" ]]; then
        iBSS="${HWModel}ap"
        iBSSBuildVer='10B329'
    elif [[ $ProductType == "iPad3,1" ]]; then
        iBSS="${HWModel}ap"
        iBSSBuildVer='11D257'
    elif [[ $ProductType == "iPhone6"* ]]; then
        iBSS="iphone6"
    elif [[ $ProductType == "iPad4"* ]]; then
        iBSS="ipad4"
    else
        iBSS="$HWModel"
        iBSSBuildVer="12H321"
    fi
    iBEC="iBEC.$iBSS.RELEASE"
    iBECb="iBEC.${iBSS}b.RELEASE"
    iBSSb="iBSS.${iBSS}b.RELEASE"
    iBSS="iBSS.$iBSS.RELEASE"
    SEP="sep-firmware.$HWModel.RELEASE.im4p"
}

Recovery() {
    local RecoveryDFU
    
    if [[ $DeviceState != "Recovery" ]]; then
        Log "Entering recovery mode..."
        $ideviceenterrecovery $UniqueDeviceID >/dev/null
        FindDevice "Recovery"
    fi
    
    Log "Get ready to enter DFU mode."
    read -p "$(Input 'Select Y to continue, N to exit recovery (Y/n)')" RecoveryDFU
    if [[ ${RecoveryDFU^} == N ]]; then
        Log "Exiting recovery mode."
        $irecovery -n
        exit
    fi
    
    Echo "* Hold POWER and HOME button for 8 seconds."
    for i in {08..01}; do
        echo -n "$i "
        sleep 1
    done
    echo -e "\n$(Echo '* Release POWER and hold HOME button for 8 seconds.')"
    for i in {08..01}; do
        echo -n "$i "
        sleep 1
    done
    
    FindDevice "DFU"
    if [[ $DeviceState == "DFU" ]]; then
        CheckM8
    else
        Error "Failed to detect device in DFU mode. Please run the script again"
    fi
}

CheckM8() {
    local pwnDFUTool
    
    DFUManual=1
    [[ $platform == macos ]] && pwnDFUTool="iPwnder32" || pwnDFUTool="ipwndfu"
    Log "Entering pwnDFU mode with $pwnDFUTool..."
    if [[ $pwnDFUTool == "ipwndfu" ]]; then
        cd resources/ipwndfu
        sudo $python ipwndfu -p
    elif [[ $pwnDFUTool == "iPwnder32" ]]; then
        $ipwnder32 -p
        cd resources/ipwndfu
    fi
    
    if [[ $DeviceProc == 7 ]]; then
        Log "Running rmsigchks.py..."
        sudo $python rmsigchks.py
        pwnDFUDevice=$?
        Echo $pwnDFUDevice
        cd ../..
    else
        cd ../..
        [[ $pwnDFUTool == "ipwndfu" ]] && kDFU iBSS || echo
        pwnDFUDevice=$?
    fi
    
    if [[ $pwnDFUDevice == 1 ]] || [[ $pwnDFUDevice == 255 ]]; then
        echo -e "\n${Color_R}[Error] Failed to enter pwnDFU mode. Please run the script again: ./restore.sh Downgrade ${Color_N}"
        echo "${Color_Y}* This step may fail a lot, especially on Linux, and unfortunately there is nothing I can do about the low success rates. ${Color_N}"
        echo "${Color_Y}* The only option is to make sure you are using an Intel device, and to try multiple times ${Color_N}"
        exit 1
    elif [[ $pwnDFUDevice == 0 ]]; then
        Log "Device in pwnDFU mode detected."
    fi
}

kDFU() {
    if [[ ! -e saved/$ProductType/$iBSS.dfu ]]; then
        Log "Downloading iBSS..."
        $partialzip $(cat $Firmware/$iBSSBuildVer/url) Firmware/dfu/$iBSS.dfu $iBSS.dfu
        mkdir -p saved/$ProductType 2>/dev/null
        mv $iBSS.dfu saved/$ProductType
    fi
    
    if [[ ! -e saved/$ProductType/$iBSS.dfu ]]; then
        Error "Failed to save iBSS. Please run the script again"
    fi
    
    Log "Patching iBSS..."
    $bspatch saved/$ProductType/$iBSS.dfu tmp/pwnediBSS resources/patches/$iBSS.patch
    
    if [[ $1 == iBSS ]]; then
        cd resources/ipwndfu
        Log "Sending iBSS..."
        sudo $python ipwndfu -l ../../tmp/pwnediBSS
        ret=$?
        cd ../..
        return $ret
    fi
    
    [[ $VersionDetect == 1 ]] && kloader="kloader_hgsp"
    [[ $VersionDetect == 5 ]] && kloader="kloader5"
    [[ ! $kloader ]] && kloader="kloader"
    
    # todo change iproxy stuff
    [ ! $(which $iproxy) ] && Error "iproxy cannot be found. Please re-install dependencies and try again" "./restore.sh Install"
    $iproxy 2222 22 &
    iproxyPID=$!
    
    Log "Copying stuff to device via SSH..."
    Echo "* Make sure OpenSSH/Dropbear is installed on the device and running!"
    Echo "* Dropbear is only needed for devices on iOS 10"
    Echo "* To make sure that SSH is successful, try these steps:"
    Echo "* Reinstall OpenSSH/Dropbear, reboot and rejailbreak, then reinstall them again"
    echo
    Input "Enter the root password of your iOS device when prompted, default is 'alpine'"
    $SCP -P 2222 resources/tools/$kloader tmp/pwnediBSS root@127.0.0.1:/tmp
    if [ $? == 1 ]; then
        Log "Cannot connect to device via USB SSH."
        Echo "* Please try the steps above to make sure that SSH is successful"
        Input "Press Enter/Return to continue anyway (or press Ctrl+C to cancel and try again)"
        read -s
        Log "Will try again with Wi-Fi SSH..."
        Echo "* Make sure that the device and your PC/Mac are on the same network!"
        Echo "* You can check for your device's IP Address in: Settings > WiFi/WLAN > tap the 'i' next to your network name"
        read -p "$(Input 'Enter the IP Address of your device:')" IPAddress
        Log "Copying stuff to device via SSH..."
        $SCP resources/tools/$kloader tmp/pwnediBSS root@$IPAddress:/tmp
        [ $? == 1 ] && Error "Cannot connect to device via SSH." "Please try the steps above to make sure that SSH is successful"
        $SSH root@$IPAddress "/tmp/$kloader /tmp/pwnediBSS" &
    else
        $SSH -p 2222 root@127.0.0.1 "/tmp/$kloader /tmp/pwnediBSS" &
    fi
    Log "Entering kDFU mode..."
    echo
    Echo "* Press POWER or HOME button when screen goes black on the device"
    FindDevice "DFU"
    kill $iproxyPID
}
