#!/bin/bash
#Checkout is install
check_cmd(){
	local obj="ios-deploy"
	if [ ! -x "$(command -v $obj)" ];then
		echo "$obj installing ....."
		brew install $obj
	fi

	local obj="idevicesyslog"
	if [ ! -x "$(command -v $obj)" ];then
		echo "$obj installing ....."
		brew install libimobiledevice
	fi

	local obj="ffmpeg"
	if [ ! -x "$(command -v $obj)" ];then
		echo "$obj installing ....."
		brew install $obj
	fi
}
check_cmd
if [ ! -d FFmpeg_iOS ];then
	unzip FFmpeg_iOS.zip
fi
echo -e "\033[32mInstall Success\033[0m"
