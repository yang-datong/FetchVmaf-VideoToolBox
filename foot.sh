#!/bin/bash

#device_id="00008110-000458D63AB8801E" #iphone13(no use wifi connect)
#device_id="00008101-001169A13490001E" #iphone12
devide_id="00008101-000E51A21A20001E" #iphone12 min
bundle_id="VideoEncode-demo"
#------------------user config-----------------------
#work space
codec_type="h264"
app_name="VideoEncode"
bundle_name="FFmpeg_iOS"
main_file="EncodeH264.m"
docker_container_name="centos/wztool"
compare_patterns="libvmaf" #example -> libvmaf|wztool
tar_dir="${HOME}/home/k客观画质测试/IOS_test/${bundle_name}"
controller_file=${tar_dir}/${bundle_name}/ViewController.m
target_edit_file=${tar_dir}/${bundle_name}/encode/${main_file}
#------------------default config-----------------------
is_auto_backup=1
is_need_save_video=1
is_local_upload_yuv=0
is_parameters_verbose=0
max_wait_time=30
src="src.mp4"
out_mp4="dst.mp4"
dst_dir="out_video"
data_dir="test"
language_type="int" #objc->int swift->let
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
unset is_loop
unset loop_video_name
unset docker_container_id

###################
#  control level  #
###################
main(){
	check_compart_patterns
	clean
	if [ ! $is_upload ];then check_yuv_file_is_upload;fi
	if [ $is_start ];then
		check_is_need_auto_backup
		check_parameters_config_file
		while read line;do kernel "$line";done < $parameters_config_file
	else
		kernel
	fi
}
upload_loop(){
	if [ ! -d source ];then	log "I need source dir!!!"; exit;fi
	if [ $(ls source | wc -l) -gt 5 ];then
		eecho "current number of videos checked is $(ls source | wc -l | sed s/[[:space:]]//g)" "33"
		eecho "mused video format name -> [video].MP4_done ,ok? [y/n]"
		read tmp
	fi
	for file in `ls source | grep -e ".MP4\|.mp4"`;do
		loop_video_name="source/$file"
		cp ${loop_video_name} ${src}
		eecho "prepare video -> ${loop_video_name}"
		main
		mv ${loop_video_name} ${loop_video_name}_done
	done
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
		update_video_info
	fi

	if [[ $is_upload && $is_justlaunch ]];then
#====================decompose MP4 source files into YUV frame sequences====================
		eecho "$(sed -n $(expr $LINENO - 1)p $0)" "33"
		if [ "$is_local_upload_yuv" == 1 ];then local_decode_yuv
		else ios_decode_yuv ;fi
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
			log "wrong format of parameter file";exit
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
	ios-deploy -W --justlaunch --bundle ./build/Release-iphoneos/${app_name}.app
	popd

#4.wait encode done
	eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
	local old_date=$(date +"%Y%m%d%H%M%S")
	wait_encode_done
	local date=$(date +"%Y%m%d%H%M%S")
	local time=$(echo "$date - $old_date" | bc)
	echo "decode time : $time" >> $compare_result_file
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
	if [ "$is_parameters_verbose" == 1 ];then
		echo "${out_mp4}-ffmpeg copy bitrate:" >> $compare_result_file
		ffmpeg -i Documents/$out_file -c copy ${out_mp4} -y < /dev/null 2>&1 | grep "bitrate=" >> $compare_result_file
	else
		${mffmpeg} -i Documents/$out_file -c copy ${out_mp4} -y < /dev/null
	fi
	uniform_frames

#7.use wztool to compare the coding result (into docker)
	eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
	if [ "$compare_patterns" == "wztool" ];then
		into_docker_compaer_video
	else
		ffmpeg_vmaf
	fi

#8.get bitrate value
	eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
	get_bitrate_value

	if [ "$is_need_save_video" == 1 ];then
#9.save compare video[same_frames_video,out_mp4]
		eecho "$(sed -n $(expr $LINENO - 1)p $0)......." "33"
		save_video
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
		log "replace -> parameters error";exit;fi
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

#############################
#  environment check level  #
#############################
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

check_is_need_auto_backup(){
	if [ ! -f ${tar_dir}/${bundle_name}/encode/${main_file}_bck ];then
		if [ "$is_auto_backup" == 1 ];then
			cp ${tar_dir}/${bundle_name}/encode/${main_file} ${tar_dir}/${bundle_name}/encode/${main_file}_bck
		else
			log "I need sample file ,format name -> ${tar_dir}/${bundle_name}/encode/${main_file}_bck"; exit;
		fi
	fi
}

check_parameters_config_file(){
	if [ ! -f $parameters_config_file ];then
		log "I need a config.data file";exit;fi
}


########################
#  code extract level  #
########################

#Used save video
save_video(){
	if [ ! -d $dst_dir ];then mkdir $dst_dir;fi
	eecho $loop_video_name
	local file=$(basename $loop_video_name)
	mv $out_mp4 ${dst_dir}/out_$file
	mv ${src_same_frames}.mp4 ${dst_dir}/same_frames_$file
}

#Used update ios project video info
update_video_info(){
	${mffprobe} -select_streams v -show_streams $src > $video_info_file
	local width=$(grep "^width" $video_info_file | awk -F "=" '{print $2}')
	local height=$(grep "^height" $video_info_file | awk -F "=" '{print $2}')
	local frameNum=$(grep "^nb_frames" $video_info_file | awk -F "=" '{print $2}')
	local codec_name=$(grep "^codec_name" $video_info_file | awk -F "=" '{print $2}')
	local duration=$(grep "duration=" $video_info_file | awk -F "=" '{print $2}')
	local r_frame_rate=$(grep "r_frame_rate" $video_info_file | awk -F "=" '{print $2}')
	eecho "${src} -> codec_name:$codec_name" "0"
	inject_video_info "${language_type} width =" "$width" $target_edit_file
	inject_video_info "${language_type} height =" "$height" $target_edit_file
	inject_video_info "${language_type} frameNum =" "$((frameNum-1))" $target_edit_file
	inject_video_info "double duration =" "$duration" $target_edit_file
	inject_video_info "double r_frame_rate =" "$r_frame_rate" $target_edit_file
	inject_video_info "${language_type} is_decodeYUV =" "0" $controller_file  #default not open decode
	local value=0
	if [ $codec_type == "h265" ];then value=1;fi
	inject_video_info "${language_type} IS_H264_OR_H265 =" "$value" $target_edit_file
}

#Use to write video info[width,height,framesNum] into inject code
inject_video_info(){
	local str=$1
	local new_value=$2
	local file=$3
	local old_info=$(grep "$str" $file)
	if [ -z "$old_info" ];then
		log "no string -> $str";exit;fi
	eecho "old_info -> $old_info" "0"
	local new_info="$str ${new_value};"
	sed -i "" "s#${old_info}#${new_info}#" $file
}

#Use wait phone encode done
wait_encode_done(){
	idevicesyslog -u $device_id -p $app_name > is_compele_convert &
	local thread_id=$!
	local time=0
	while(true);do
		sleep 1
		cat is_compele_convert | grep "$encode_compare_flag"
		if [ $? -ne 0 ];then
			((time++)); eecho "wait iphone convert complete[${time}]..."
			if [ $time == $max_wait_time ];then
				echo "$loop_video_name" >>  $batch_running_log
				log "bad -> $loop_video_name"
				log "encode timeout"
				is_encode_time_out=1
				break
			fi
		else
			kill $thread_id;break;fi
	done
}

#Use call ios project decode
ios_decode_yuv(){
	ios-deploy -W --bundle_id $bundle_id -X /Documents/${data_dir}
	ios-deploy -W --bundle_id $bundle_id --upload $src --to Documents/$src
	inject_video_info "int is_decodeYUV =" "1" $controller_file
}

#Use update into phone yuv data
local_decode_yuv(){
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
		if [ "$is_parameters_verbose" == 1 ];then
			echo "${src} -ffmpeg copy bitrate:" >> $compare_result_file
			ffmpeg -i $src -c copy -frames:v $compare_frame_num ${src_same_frames}.mp4 < /dev/null 2>&1 | grep "bitrate=" >> $compare_result_file
		else
			${mffmpeg} -i $src -c copy -frames:v $compare_frame_num ${src_same_frames}.mp4 < /dev/null;fi
	fi
}

#Use get vmaf data
ffmpeg_vmaf(){
	if [[ $is_start || $is_loop ]];then
		if [ $is_loop ];then
			echo "-------------------------$loop_video_name" >> $compare_result_file
		else
			echo "-------------------------$line" >> $compare_result_file
		fi
		vmaf_score=$(ffmpeg -i ${src_same_frames}.mp4 -i ${out_mp4} -lavfi libvmaf="log_path=output.xml:psnr=1:ssim=1:log_fmt=json" -f null - < /dev/null 2>&1 | grep "VMAF score:")
		echo $vmaf_score >> $compare_result_file
		#cat output.xml >> $compare_result_file
	else
		ffmpeg -i ${src_same_frames}.mp4 -i ${out_mp4} -lavfi libvmaf="log_path=output.xml:psnr=1:ssim=1:log_fmt=json" -f null - < /dev/null
	fi
}

#Use get vmaf data
into_docker_compaer_video(){
	docker cp ${src_same_frames}.mp4 ${docker_container_id}:/root/src.mp4
	docker cp $out_mp4 ${docker_container_id}:/root/dst.mp4
	if [[ $is_start || $is_loop ]];then
		if [ $is_loop ];then
			echo "-------------------------$loop_video_name" >> $compare_result_file
		else
			echo "-------------------------$line" >> $compare_result_file
		fi
		docker exec ${docker_container_id} /bin/bash /root/calc-vmaf.sh >> $compare_result_file
	else
		docker exec ${docker_container_id} /bin/bash /root/calc-vmaf.sh >& 2
	fi
}

#Use get bitrate data
get_bitrate_value(){
	local out_bit_rare=$(${mffprobe} -select_streams v -show_streams $out_mp4 | grep ^bit_rate | awk -F "=" '{print $2}')
	local src_same_bit_rare=$(${mffprobe} -select_streams v -show_streams ${src_same_frames}.mp4 | grep ^bit_rate | awk -F "=" '{print $2}')
	local src_bit_rare=$(${mffprobe} -select_streams v -show_streams $src | grep ^bit_rate | awk -F "=" '{print $2}')
	echo "${out_mp4}-ffprobe info bitrate: ${out_bit_rare}" >> $compare_result_file
	#echo "${src_same_frames}.mp4-ffprobe info bitrate: ${src_same_bit_rare}" >> $compare_result_file
	#echo "${src}-ffprobe info bitrate: ${src_bit_rare}" >> $compare_result_file
}


################
#  util level  #
################
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

#Use to dump iphone in [out].file[h264\h265\mp4]
dump(){
	check_compart_patterns
	local old_md5=$(md5 Documents/${out_file})
	ios-deploy -W --download=/Documents/${out_file} --bundle_id $bundle_id --to .
	local new_md5=$(md5 Documents/${out_file})
	eecho "$old_md5 \n$new_md5 "
	${mffmpeg} -i Documents/$out_file -c copy ${out_mp4} -y < /dev/null
	uniform_frames
	eecho "use $compare_patterns ..."
	if [ "$compare_patterns" == "wztool" ];then
		into_docker_compaer_video
	else
		ffmpeg_vmaf
	fi
}

#Use to format log file
format(){
	local flag="y"
	local format_file="${compare_result_file%.*}.format"
	if [ "$compare_patterns" != "wztools" ];then
		eecho "are you sure you are using wztools for comparison?[y/n]" "33";read flag;fi
	if [ "$flag" == "n" ];then	exit;fi
	if [ -f ${compare_result_file} ];then
		cat ${compare_result_file} >> ${compare_result_file%.*}_history.txt
		rm ${compare_result_file}
	fi
	if [ "$compare_patterns" == "wztools" ];then
		cat ${compare_result_file%.*}_history.txt | grep -e "-ffprobe\|------------------------\|PSNR\|SSIM\|^vmaf" > $format_file
	else
		cat ${compare_result_file%.*}_history.txt | grep -e "-ffprobe\|------------------------\|PSNR\|SSIM\|VMAF" > $format_file
	fi
	sed -i '' "s/.\[1;3.m//" $format_file
	eecho "done,out data into ${format_file}" "32"
	calculate_average
}

#calculate bitrate and vmaf average
calculate_average(){
	local file_line=""
	local all_vmaf=""
	local all_bitrate=$(cat $format_file | grep "bitrate" | awk -F ":" '{print $2}')
	if [ "$compare_patterns" == "wztools" ];then
		file_line=$(cat $format_file | grep "^vmaf" | wc -l )
		all_vmaf=$(cat $format_file | grep "^vmaf" | awk -F ":" '{print $2}')
	else
		file_line=$(cat $format_file | grep "VMAF" | wc -l )
		all_vmaf=$(cat $format_file | grep "VMAF" | awk -F ":" '{print $2}')
	fi

	local sum=0
	for i in $all_bitrate;do sum=$(echo "$sum + $i" | bc) ;echo "bitrate : $i";done
	log "average : $(echo "scale=2; $sum / $file_line" | bc )"

	sum=0
	for i in $all_vmaf;do sum=$(echo "$sum + $i" | bc) ;echo "vmaf : $i";done
	log "average : $(echo "scale=2; $sum / $file_line" | bc )"
}

#fail time play music
play_music(){
	ffplay ${music_file} &
	local thread_id=$!
	sleep $max_wait_time
	kill $thread_id
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
	local tmp_file=$(ls | grep -v "foot.sh\|src.mp4\|VideoEncode_rel\|config.data\|compare_result_history.txt\|Documents\|generate_foot_arg.sh\|README.md\|source\|out_video")
	if [ -z "$tmp_file" ];then
		eecho "alreadly been cleaned"
	else
		mv $tmp_file ${dir}/
	fi
}

#hugely print conlose
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
	shift;shift;
	if [ -z "$flag" ];then
		echo $* -e "\033[31m${info}\033[0m" >& 2
	else
		echo $* -e "\033[${flag}m${info}\033[0m" >& 2
	fi
}

#print use help info
menu(){
	echo -e "\033[33m"
	echo -e "Target file -> ${target_edit_file}\033[0m\nexample:"
	echo -e "\033[31m"
	echo "./foot.sh start > /dev/null" >& 2
	echo "./foot.sh upload > /dev/null" >& 2
	echo "./foot.sh upload loop > /dev/null" >& 2
	echo "./foot.sh annotation [code_line] [on\off]" >& 2
	echo "./foot.sh justlaunch > /dev/null" >& 2
	echo "./foot.sh dump > /dev/null" >& 2
	echo "./foot.sh clean" >& 2
	echo -e "./foot.sh format \033[0m      ###format compare_result_file data and calculate the average\033[31m" >& 2
	echo -e "\033[0m"
}

if [ "$1" == help ];then
	menu
elif [ "$1" == start ];then
	is_start=1;main
elif [ "$1" == upload ];then
	is_justlaunch=1;is_upload=1
	if [ "$2" == loop ];then is_loop=1 ;upload_loop
	else main;fi
elif [ "$1" == annotation ];then
	annotation $2 $3
elif [ "$1" == justlaunch ];then
	is_justlaunch=1;main
elif [ "$1" == dump ];then
	dump
elif [ "$1" == format ];then
	format
elif [ "$1" == clean ];then
	clean
else
	menu
fi
