#!/bin/bash

#------------------user config-----------------------
#device_id="00008101-001169A13490001E" #iphone12(no use wifi connect)
device_id="00008110-000458D63AB8801E" #iphone13(no use wifi connect)
codec_type="h265"
#work space
docker_container_name="ios_test_2"
bundle_name="FFmpeg_iOS"
bundle_id="VideoEncode"
main_file="EncodeH264.m"
tar_dir="${HOME}/Desktop/${bundle_name}"
controller_file=${tar_dir}/${bundle_name}/ViewController.m
target_edit_file=${tar_dir}/${bundle_name}/encode/${main_file}
#------------------default config-----------------------
compare_patterns="ffmpeg" #example -> ffmpeg|wztool
is_auto_backup=1
max_wait_time=20
src="src.mp4"
out_mp4="dst.mp4"
data_dir="test"
parameters_config_file="config.data"
compare_result_file="compare_result.txt"
#auto generate file
out_file="video.${codec_type}"
compare_target_files="default_video.${codec_type}"
src_same_frames="${src%.*}_same_frames"
video_info_file="${src%.*}.info"
#ffmpeg
is_info_ffmpeg="-loglevel quiet"
mffmpeg="ffmpeg ${is_info_ffmpeg}"
mffprobe="ffprobe ${is_info_ffmpeg}"
#other file
#music_file="${HOME}/Music/网易云音乐/demo.flac"
batch_running_log="${HOME}/Desktop/foot_sh_start_error_log.md"
#flag
restore_flag="reset"
add_paramenters_flag="==========free zone=========="
encode_compare_flag="==========comple convert=========="
#------------------dynamic init-----------------------
unset is_start
unset is_justlaunch
unset is_upload
unset is_encode_time_out
unset docker_container_id

###################
#  control level  #
###################
main(){
	check_compart_patterns
	clean
	if [ ! $is_upload ];then
		check_yuv_file_is_upload
	fi
	if [ $is_start ];then
		if [ ! -f ${tar_dir}/${bundle_name}/encode/${main_file}_bck ];then
			if [ $is_auto_backup == 1 ];then
				cp ${tar_dir}/${bundle_name}/encode/${main_file} ${tar_dir}/${bundle_name}/encode/${main_file}_bck
			else
				log "I need sample file ,format name -> ${tar_dir}/${bundle_name}/encode/${main_file}_bck"; exit;
			fi
		fi
		if [ ! -f $parameters_config_file ];then
			log "I need a config.data file";exit;fi
		while read line;do kernel "$line";done < $parameters_config_file
	else
		kernel
	fi
}

##########################
#  kernel process level  #
##########################
kernel(){
	local line=$1
	if [[ ! -z "$line" && "$line" == $restore_flag ]];then
		pushd ${tar_dir}/${bundle_name}/encode ;cp ${main_file}_bck ${main_file};popd
		log "$restore_flag"
		return 1 #continue while loop
	fi

	if [ ! -f  $video_info_file ];then
#====================view source video file metadata====================
		eecho "$(sed -n $(expr $LINENO - 1)p $0)" "33"
		${mffprobe} -select_streams v -show_streams $src > $video_info_file
		local width=$(grep "^width" $video_info_file | awk -F "=" '{print $2}')
		local height=$(grep "^height" $video_info_file | awk -F "=" '{print $2}')
		local frameNum=$(grep "^nb_frames" $video_info_file | awk -F "=" '{print $2}')
		local codec_name=$(grep "^codec_name" $video_info_file | awk -F "=" '{print $2}')
		local duration=$(grep "duration=" $video_info_file | awk -F "=" '{print $2}')
		local r_frame_rate=$(grep "r_frame_rate" $video_info_file | awk -F "=" '{print $2}')
		eecho "${src} -> codec_name:$codec_name" "0"
		inject_video_info "int width =" $width
		inject_video_info "int height =" $height
		inject_video_info "int frameNum =" $((frameNum-1))
		inject_video_info "double duration =" $duration
		inject_video_info "double r_frame_rate =" $r_frame_rate

		local value=0
		if [ $codec_type == "h265" ];then value=1;fi
		inject_video_info "int IS_H264_OR_H265 =" $value
	fi

	if [[ $is_upload && $is_justlaunch ]];then
#====================decompose MP4 source files into YUV frame sequences====================
		eecho "$(sed -n $(expr $LINENO - 1)p $0)" "33"
		update_yuv
	fi

	if [ ! -z "$line" ];then #Not empty string
#1.update parameters
		eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
		#Parameters1 -> will modify parameters key
		local parameters_key=$(echo $line | awk -F ":" '{print $1}')
		#Parameters2 -> new parameters value
		local new_value=$(echo $line | awk -F ":" '{print $2}')
		#Parameters3 -> operation type
		local op_type=$(echo $line | awk -F ":" '{print $3}')
		if [[ -z "$parameters_key" || -z "$new_value" || -z "$op_type" ]];then
			log "wrong format of parameter file"
			exit
		fi
		eecho "parameters_key -> $parameters_key"
		if [ "$op_type" == "add" ];then
			replace "$parameters_key" "$new_value"
		elif [ "$op_type" == "dele" ];then
			dele "$parameters_key"
		fi
	fi

#2.build project
	eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
	pushd $tar_dir
	xcodebuild -target $bundle_name
	if [ "$?" == "65" ];then
		log "xcodebuild faild....try compile again"
		exit
	fi

#3.launch App && and start encode
	eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
	ios-deploy -W --justlaunch --bundle ./build/Release-iphoneos/${bundle_id}.app
	popd

#4.wait encode done
	eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
	wait_encode_done
	if [ "$is_encode_time_out" == 1 ];then is_encode_time_out=0;return 1;fi

#5.dump [out].h264/h265
	eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
	local old_md5=$(md5 Documents/${out_file})
	ios-deploy -W --download=/Documents/${out_file} --bundle_id $bundle_id --to .
	local new_md5=$(md5 Documents/${out_file})
	eecho "$old_md5 \n$new_md5 "
	if [[ "$new_md5" == "$old_md5" && $is_start ]];then
		eecho "\n\n====================\n  hasn't changed data,skip:\n$line\n====================\n\n" "32"
		echo "-------------------------$line -->> skip" >> $compare_result_file
		return 1;
	fi

#6.from [out].h264/h265 file convert MP4 file
	eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
	${mffmpeg} -i Documents/$out_file -c copy ${out_mp4} -y < /dev/null
	uniform_frames

#7.use wztool to compare the coding result (into docker)
	eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
	if [ "$compare_patterns" == "wztool" ];then
		into_docker_compaer_video
	else
		ffmpeg_vmaf
	fi
}

################
#  data level  #
################
# Used to delete parameters
dele(){
	local parameters_key=$1
	eecho "delete_key-> $parameters_key"
	sed -i "" "/${parameters_key}/d" ${target_edit_file}
}

# Used to modify parameters
replace(){
	local parameters_key=$1
	local new_value=$2
	if [[ -z "$parameters_key" || -z "$new_value" ]];then
		log "replace -> parameters error";exit;
	fi
	local parameters_value=$(grep "$parameters_key" ${target_edit_file} | awk -F "," '{print $3}')
	local code_line=$(grep -n "$parameters_key" ${target_edit_file} | awk -F ":" '{print $1}')
	if [[ ! -z "$parameters_value" && ! -z "$code_line" ]];then
		#repace * -> \*
		parameters_value=$(echo $parameters_value | sed "s#\*#\\\*#")
		eecho "code_line -> $code_line"
		eecho "parmeters_value -> $parameters_value"
		eecho "new_value-> $new_value"
		sed -i "" "${code_line}s/${parameters_value}/${new_value});/" ${target_edit_file}
	else
		add "$parameters_key" "$new_value"
	fi
}

# Used to add parameters
add(){
	local parameters_key=$1
	local new_value=$2
	eecho "add_value-> $new_value"
	sed -i "" "/${add_paramenters_flag}/a\ 
	status = VTSessionSetProperty(encodeSesion, ${parameters_key}, ${new_value});
" ${target_edit_file}
}

########################
#  code extract level  #
########################
#Use to annotation code
annotation(){
	local code_line=$1
	local status=$2
	if [ "$status" == "on" ];then
		sed -i "" "${code_line}s/\/\/status/status/g" $target_edit_file
	elif [ "$status" == "off" ];then
		sed -i "" "${code_line}s/status/\/\/status/g" $target_edit_file
	else
		log "annotation -> format error[on\off]";exit;
	fi
}

#Use to write video info[width,height,framesNum] into inject code
inject_video_info(){
	local str=$1
	local new_value=$2
	local old_info=$(grep "$str" $target_edit_file)
	if [ -z "$old_info" ];then
		log "no string -> $str";exit
	fi
	eecho "old_info -> $old_info" "0"
	local new_info="$str ${new_value};"
	sed -i "" "s#${old_info}#${new_info}#" $target_edit_file
}

#Use wait phone encode done
wait_encode_done(){
	idevicesyslog -u $device_id -p $bundle_id > is_compele_convert &
	local thread_id=$!
	local time=0
	while(true)
	do
		sleep 1
		cat is_compele_convert | grep "$encode_compare_flag"
		if [ $? -ne 0 ];then
			((time++))
			eecho "wait iphone convert complete[${time}]..."
			if [ $time == $max_wait_time ];then
#				echo "$video:$1" >>  $batch_running_log
#				log "bad -> $video"
				log "encode timeout"
				is_encode_time_out=1
				break
			fi
		else
			kill $thread_id
			break
		fi
	done
}

#Use update into phone yuv data
update_yuv(){
	if [ -d $data_dir ];then	rm -rf $data_dir;fi
	mkdir $data_dir
	${mffmpeg} -i $src -f segment -segment_time 0.01 ${data_dir}/frames%d.yuv  < /dev/null
	#${mffmpeg} -i $src -pix_fmt yuv420p -f segment -segment_time 0.01 ${data_dir}/frames%d.yuv  < /dev/null
	ios-deploy -W --bundle_id $bundle_id -X /Documents/${data_dir}
	ios-deploy -W --bundle_id $bundle_id --upload $data_dir --to Documents/${data_dir}
}

#Use uniform [input].video and [out].video frames
uniform_frames(){
	if [ ! -f ${src_same_frames}.mp4 ];then
#====================uniform number of frames====================
		eecho "$(sed -n $(expr $LINENO - 1)p $0)" "33"
		#get out_file frames num
		local compare_frame_num=$(${mffprobe} -select_streams v -show_streams $out_mp4 | grep "^nb_frames" |  awk -F "=" '{print $2}')
		#convert : extract mp4 frames -> new mp4
		${mffmpeg} -i $src -c copy -frames:v $compare_frame_num ${src_same_frames}.mp4 < /dev/null
	fi
}

#Use get vmaf data
ffmpeg_vmaf(){
	if [ $is_start ];then
		echo "-------------------------$line" >> $compare_result_file
		${mffmpeg} -i ${src_same_frames}.mp4 -i ${out_mp4} -lavfi libvmaf=log_path=output.xml -f null - < /dev/null
		cat output.xml >> $compare_result_file
	else
		${mffmpeg} -i ${src_same_frames}.mp4 -i ${out_mp4} -lavfi libvmaf=log_path=output.xml -f null - < /dev/null
	fi
}

#Use get vmaf data
into_docker_compaer_video(){
	docker cp ${src_same_frames}.mp4 ${docker_container_id}:/root/src.mp4
	docker cp $out_mp4 ${docker_container_id}:/root/dst.mp4
	if [ $is_start ];then
		echo "-------------------------$line" >> $compare_result_file
		docker exec ${docker_container_id} /bin/bash /root/calc-vmaf.sh >> $compare_result_file
	else
		docker exec ${docker_container_id} /bin/bash /root/calc-vmaf.sh >& 2
	fi
}

dump(){
	check_compart_patterns
	ios-deploy -W --download=/Documents/${out_file} --bundle_id $bundle_id --to .
	${mffmpeg} -i Documents/$out_file -c copy ${out_mp4} -y < /dev/null
	uniform_frames
	if [ "$compare_patterns" == "wztool" ];then
		into_docker_compaer_video
	else
		ffmpeg_vmaf
	fi
}

#fail time play music
play_music(){
	ffplay ${music_file} &
	local thread_id=$!
	sleep $max_wait_time
	kill $thread_id
}

check_yuv_file_is_upload(){
	#check the project is empty
	yuv_file=$(ios-deploy -1 $bundle_id --list | grep "/Documents/${data_dir}" | grep ".yuv$")
	if [ -z "$yuv_file" ];then
		log "yuv data is empty!!! , try \"./foot.sh upload > /dev/null\"" ;exit;
	fi
}

#check docker is running
check_compart_patterns(){
	if [ "$compare_patterns" == "wztool" ];then
		docker_container_id=$(docker ps | grep "$docker_container_name" | awk '{print $1}')
		if [ -z "$docker_container_id" ];then
			log "docker run faild";exit;fi
	fi
}

#Use init env .clear project space
clean(){
	#current time
	tmp_date=$(date +"%Y%m%d_%H%M%S")
	dir=/tmp/ios_test_tmp_${tmp_date}
	mkdir $dir
	#save data content
	if [ -f $compare_result_file ];then
		echo $tmp_date >> ${compare_result_file%.*}_history.txt
		cat $compare_result_file >>  ${compare_result_file%.*}_history.txt
	fi
	#clear
	rm -rf $data_dir #add clear yuv file
	local tmp_file=$(ls | grep -v "foot.sh\|src.mp4\|VideoEncode_rel\|config.data\|compare_result_history.txt\|Documents\|generate_foot_arg.sh\|README.md")
	if [ -z "$tmp_file" ];then
		eecho "alreadly been cleaned"
	else
		mv $tmp_file ${dir}/
	fi
}


log(){
	if [ $# -gt 1 ];then
		printf "\033[31mParameter can only be one!!!" >& 2;exit;fi
	tty_wid=$(tput cols)
	line=$(printf "\033[33m%00${tty_wid}d\n" 0 | tr "0" "=")
	string_len=$(echo $1 | wc -c)

	((tty_wid -= string_len))
	((tty_wid /= 2))

	eecho $line
	printf "%00${tty_wid}d" 0 | tr "0" " " >& 2
	printf "\033[91m$1\n" >& 2
	eecho $line
}

#print conlose
eecho(){
	local info=$1
	local flag=$2
	if [ -z "$flag" ];then
		echo -e "\033[31m${info}\033[0m" >& 2
	else
		echo -e "\033[${flag}m${info}\033[0m" >& 2
	fi
}

#print use help info
menu(){
	echo -e "\033[33m"
	echo -e "Target file -> ${target_edit_file}\033[0m\nexample:"
	echo -e "\033[31m"
	echo "./foot.sh start" >& 2
	echo "./foot.sh upload" >& 2
	echo "./foot.sh annotation [code_line] [on\off]" >& 2
	echo "./foot.sh justlaunch" >& 2
	echo "./foot.sh dump" >& 2
	echo "./foot.sh clean" >& 2
	echo -e "\033[0m"
}

if [ "$1" == help ];then
	menu
elif [ "$1" == start ];then
	is_start=1
	main
elif [ "$1" == upload ];then
	is_justlaunch=1
	is_upload=1
	main
elif [ "$1" == annotation ];then
	annotation $2 $3
elif [ "$1" == justlaunch ];then
	is_justlaunch=1
	main
elif [ "$1" == dump ];then
	dump
elif [ "$1" == clean ];then
	clean
else
	menu
fi
