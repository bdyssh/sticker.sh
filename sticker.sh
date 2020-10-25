#!/bin/bash

# Dot-for-dot print ytility for Brother laminated label printers.
# Network (LPD+SNMP) and USB mode are tested. 
# Serial RS232 mode is planned. TODO (Ask me for it)
# Written by: bdyssh.ru, started at: 2018.

#	PT-1230PC	180 dpi		64 px
#	PT-2430PC	180 dpi		128 px
#	PT-9800PCN	360 dpi		384 px
#	PT-P950NW	360 dpi		454 px (virt. 560 px?)

# Name, take it from 'system-config-printer' or so:
printer="PT-P950"
#printer="PT-9800PCN"
#printer="PT-2430PC"

# https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
# saner programming env: these switches turn some bugs into errors
#set -o errexit -o pipefail -o noclobber -o nounset
set -o errexit -o pipefail -o nounset

! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
	echo "I'm sorry, getopt --test failed in this environment."
	exit 1
fi

if [ "$#" = 0 ]; then
	echo "Hello, this is artificial intelligence. Expect many weird errors from me."
	echo "Utility for industrial dot-for-dot printing for Brother laminated tape printers."
	echo " Support: 3.5 to 36 mm tape, USB and IP/SNMP units, "
	echo "          partial cut, stacked printing, N copies, "
	echo " Example of IP conn.: lpd://192.168.10.12/BINARY_P1"
	echo " Example of USB conn.: usb://Brother/PT-2430PC?serial=G2Z98859"
	echo " Version: 0.01"
	echo " Date: 23.10.2020"
	echo " Author: www.bdyssh.ru"
	echo "Usage: $0 -i image.img"
	echo "$0 -t1 'text1' -t2 'text2'    # planned, TODO"
	echo "$0 -i img.img --tape 3.5mm --copies 2"
	echo "$0 -i big_image.img --tape 12mm --split"
	echo "Other: -t, --tape TAPE; -v, --verbose; -s, --split; -c, --copies INT; -e, --enlarge INT."
	exit 1
fi

OPTIONS=i:T1:T2:t:c:e:vyfs
LONGOPTS=image:,Text1:,Text2:,tape:,verbose,yes,force,split,copies,enlarge

# -use ! and PIPESTATUS to get exit code with errexit set
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out --options)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
	# e.g. return value is 1
	#  then getopt has complained about wrong arguments to stdout
	exit 2
fi
# read getopt's output this way to handle the quoting right:
eval set -- "$PARSED"

verbose=0 yes=0 split=0 img="" text1="" text2="" force=0 installed_tape="" copies=1 enlarge=1

while true; do
	case "$1" in
		-i|--image)
			img="$2"
			shift 2
			;;
		-T1|--Text1)
			text1="$2"
			shift 2
			;;
		-T2|--Text2)
			text2="$2"
			shift 2
			;;
		-t|--tape)
			installed_tape="$2"
			shift 2
			;;
		-c|--copies)
			copies="$2"
			shift 2
			;;
		-e|--enlarge)
			enlarge="$2"
			shift 2
			;;
		-v|--verbose)
			verbose=1
			shift
			;;
		-y|--yes)
			yes=1
			shift
			;;
		-f|--force)
			force=1
			shift
			;;
		-s|--split)
			split=1
			shift
			;;
		--)
			shift
			break
			;;
		*)
			echo "Programming error"
			exit 3
			;;
	esac
done

if (($verbose>0)); then
	echo " Printer: $printer, img: $img, texts: '$text1' '$text2'"
fi


# We need to determine current tape width in order to prolong print head
# life by not to print outside tape surface. This is most hard, but important
# part for industrial utility.
# This is possible for network printer via SNMP. But for USB, talking to printer
# is still not implemented nowhere at 24.10.2020.
# The nearest prject to talk with USB printer is like libinklevel-0.9.3.tar.gz.
# but still, request to receive status is unknown and can be known
# only from rev.eng. of USB flow from Windows(r) driver.
# "Appendix A: USB Specifications" at "Raster Command Reference" says nothing new.
# Also may be USB-ETH wrapper can be born in future somewhere.
# So currently we will ask user for installed tape width for USB printer.

printer_device=$(lpstat -v $printer)
if (($verbose>0)); then
	echo " Device string  $printer_device"
fi

use_snmp=0

case "$printer_device" in
	*lpd://*) # wildcards / partial match / substring match
		use_snmp=1
		;;
	*usb://*) # wildcards / partial match / substring match
		use_snmp=0
		;;
	*)
		echo "Unknown printer connection type $printer_device. Please examine it via lpstat -v and fix me, or try to use other printer connection type."
		exit 5
		;;
esac

if (($verbose>0)); then
	echo " Use SNMP:  $use_snmp"
fi

if (($use_snmp>0)); then

	printer_ip=$(grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' <<< "$printer_device")
	if (($verbose>0)); then
		echo " Printer_IP  $printer_ip"
	fi	
	
# 1.3.6.1.2.1.25.3.2.1.3.1 = STRING: "Brother PT-9800PCN"
	printer_type=$(snmpget -Oqv -v 1 -c public $printer_ip 1.3.6.1.2.1.25.3.2.1.3.1)
	if (($verbose>0)); then
		echo " Type  $printer_type"
	fi

# 1.3.6.1.2.1.43.16.5.1.2.1.1
# also status as integer: 1.3.6.1.2.1.43.18.1.1.6.1.1 = INTEGER: 10001 (good), or others.
	printer_status=$(snmpget -Oqv -v 1 -c public $printer_ip 1.3.6.1.2.1.43.16.5.1.2.1.1)
	if (($verbose>0)); then
		echo " Status  $printer_status"
	fi
# wildcards / partial match - looks like work. 23.10.2020
# https://stackoverflow.com/questions/2237080/how-to-compare-strings-in-bash
	if [[ "$printer_status" == *READY* ]]; then  
	if (($verbose>0)); then
		echo "OK, we continue."
	fi
	else
		echo "Printer error: "$printer_status
		exit 1
	fi

# now, only when it ready, get tape width will work correctly:
# ex. 1.3.6.1.2.1.43.8.2.1.12.1.1 = STRING: "36mm / 1-1/2\""
	installed_tape=$(snmpget -Oqv -v 1 -c public $printer_ip 1.3.6.1.2.1.43.8.2.1.12.1.1)
	if (($verbose>0)); then
		echo " Tape width  $installed_tape"
	fi

	if [[ "$installed_tape" == *HG* ]]; then  
		if (($force == 0)); then
			echo "HG tapes are not reliable, due to they force unavoidable high-speed print, and it eating pixels. But, 24 mm ones can be easily fixed by drilling 3rd index hole at back side: (other widths also, just compare index holes to same width non-HG)"
			echo "       |"
			echo "   () o|"
			echo "    o  |"
			echo "  x    |    <-- drill where 'x' shown."
			echo "-------/"
			echo "Please fix it or replace tape to non-HG. Well, -f (--force) overrides it."
			exit 4
		fi
	fi
else	# if (($use_snmp>0)); then
# For USB, we use its system name here, so we related to correct user naming 
# for their printers via 'system-config-printer' or so. 
	printer_type=$printer
# Tape width may be provided via command line. If not, we must ask.
	if [[ "$installed_tape" == "" ]]; then  
		read -p "Enter tape width like '12mm', '3.5mm' (without space): " installed_tape
	fi
fi 	# if (($use_snmp>0)); then

dpi_div=1
need_extra_header=0
case "$printer_type" in
	*1230*) # wildcards / partial match / substring match
		printhead_dots=64
		dpi_div=1/2
		;;
	*2430*) # wildcards / partial match / substring match
		printhead_dots=128
		dpi_div=1/2
		;;
	*9800PCN*) # wildcards / partial match / substring match
		printhead_dots=384
		need_extra_header=1
		;;
	*P950*) # wildcards / partial match / substring match
# Defined by specs:
#		printhead_dots=454
# But, with 454 not work (shifted). Rev.eng. of cups printouts also show strange "G" (0x47) codes.
# "Raster Command Reference" says: total number of pins (560)! What is true?
		printhead_dots=560 # now almost centered...
		need_extra_header=1
		;;
	*)
		echo "Unknown printer type $printer_type. Please examine it via 'system-config-printer' or SNMP, and fix its name (or fix me), or try to use other printer. We must know head dots quantity."
		exit 5
		;;
esac

if (($verbose>0)); then
	echo " Dots  $printhead_dots"
fi

# 'tape_pixels' matched to 360 dpi. For other dpi, recalculate below.
case "$installed_tape" in
# 36mm should be before 6mm
*36mm*) # wildcards / partial match / substring match
	tape_width="36"
	tape_pixels=454 # from table
#	tape_pixels=42 debug
	;;
*3.5mm*) # wildcards / partial match / substring match
	tape_width="3.5"
	tape_pixels=48
	;;
*6mm*) # wildcards / partial match / substring match
	tape_width="6"
	tape_pixels=64
	;;
*9mm*) # wildcards / partial match / substring match
	tape_width="9"
	tape_pixels=106 # from table
	;;
*12mm*) # wildcards / partial match / substring match
	tape_width="12"
	tape_pixels=150 # from table
#	tape_pixels=152 # from table and corrected to 8*INT
#	tape_pixels=160 # tested, do not change.
	;;
*18mm*) # wildcards / partial match / substring match
	tape_width="18"
	tape_pixels=234 # from table
#	tape_pixels=232 # from table and corrected to 8*INT
#	tape_pixels=248 # tested, do not change.
	;;
*24mm*) # wildcards / partial match / substring match
	tape_width="24"
#	tape_pixels=168 debug
#	tape_pixels=336 # tested with 9800PCN, do not change.
# For P950NW, there is auto internal limit for all widths, here 
# it is 320 px. Extra pixels are eaten and thrown away. It is bad, but
# saves head when possible tape skews. So better to use 320 (as from table).
	tape_pixels=320
	;;
*)
	echo "Unknown installed tape description $installed_tape. Please examine it via snmp or printer specs, and fix me, or try to use other tape."
	exit 3
	;;
esac

# Some printers are have less than 360 dpi
tape_pixels=$(( $tape_pixels * $dpi_div ))

# Check if tape is wider than head 
if (($tape_pixels>$printhead_dots)); then
 if (($verbose>0)); then
	echo " Trimmed max tape pixels from $tape_pixels to $printhead_dots due to print head capability."
 fi
	tape_pixels=$printhead_dots
fi

margin=$(( ($printhead_dots - $tape_pixels)/2 ))
printhead_bytes=$(( ($printhead_dots + 7) / 8 ))

if (($verbose>0)); then
	echo " Tape width (parsed) $tape_width ($tape_pixels px), head dots $printhead_dots (bytes $printhead_bytes), margin $margin."
fi

# Main job: prepare print file with raw binary data.

echo "" > pt.prn

# resets any prev. transfer (include incomplete) if any; min. 200 zeroes.
for((i=0; i<255; i++)); do echo -n -e \\x00 >> pt.prn; done;

if (($need_extra_header>0)); then
# clear buffer and transferred lines q'ty.
	echo -n -e \\x1b\\x40 >> pt.prn		
# unknown, but required for 9800PCN at least. And for P950NW also.
	echo -n -e \\x1b\\x69\\x61\\x01 >> pt.prn 
# Its work,  set (zero) margins
#	echo -n -e \\x1b\\x69\\x64\\x00\\x00 >> pt.prn  
# set cut mode.
	echo -n -e \\x1b\\x69\\x4b\\x0c >> pt.prn
fi

convert -quiet "$img" -resize "$enlarge"00% -flop -rotate 90 temp1.png

img_w=`identify -ping -format '%w' temp1.png`
# min img_h at 360 dpi = 57 px, max = 14173 px, check it later. TODO
img_h=`identify -ping -format '%h' temp1.png`
pages=$(( ($img_w-1) / $tape_pixels + 1 ))
if (($verbose>0)); then
	echo " Image w, h; pages (for split prints):  $img_w, $img_h, $pages"
fi

if (($split==0)); then
	pages=1
	if (($img_w>$tape_pixels)); then
		echo "ERROR: Image width $img_w more than tape width $tape_pixels."
		echo "Either use -s,--split to multi pieces print, or reduce image width."
		exit 1
	fi
fi

total_width=$(( $tape_pixels * $pages ))

# make one whole image, centered either on tape, 
# or on multiple tapes tiled together after print (split printing).
convert -quiet temp1.png -background white -gravity center -extent "$total_width"x temp2.png

for((copy=0; copy<$copies; copy++)); do 
  for((page=0; page<$pages; page++)); do 
	first_middle_last_page=1 # middle
	if ((copy == 0)); then
		if ((page == 0)); then
			first_middle_last_page=0 # first
		fi
	fi
	if ((copy == $copies-1)); then
		if ((page == $pages-1)); then
			first_middle_last_page=2 # last or single page
		fi
	fi
  
	if (($need_extra_header>0)); then
# Clear buffer and transferred lines q'ty. It is important for every 'page'.
		echo -n -e \\x1b\\x40 >> pt.prn		
# This ESC seq. required for PT-P9100/900W/950NW (and maybe PT-P910BT); 
#  are others like 9800PCN can live with it ?! TODO Added: Yes, 9800PCN not fear it.
		h_lsbyte=$(( $img_h % 256 ))
		h_msbyte=$(( $img_h / 256 ))
		echo -n -e \\x1b\\x69\\x7a\\x80\\x00\\x00\\x00\\x$(printf %x "$h_lsbyte")\\x$(printf %x "$h_msbyte")\\x00\\x00\\x$(printf %x "$first_middle_last_page")\\x00 >> pt.prn 
# Will transfer bitmap after it.
		echo -n -e \\x4d\\x00 >> pt.prn
		echo -n -e \\x1b\\x69\\x52\\x01 >> pt.prn
	fi

	shift=$(( $tape_pixels * page ))
	convert -quiet temp2.png -crop "$tape_pixels"x+"$shift"+0 temp3.png # debug: temp3"$page".png
	if (($verbose>0)); then
		echo " Page, shift:  $page, $shift"
	fi

	convert -quiet temp3.png -background white -gravity center -extent "$printhead_dots"x -monochrome -colors 2 -depth 1 -negate r:img.raw

	for((i=0; i<$img_h; i++)); do 
		echo -n -e "G"\\x$(printf %x "$printhead_bytes")\\x00 >> pt.prn; 
		dd if=img.raw of=pt.prn bs=$printhead_bytes count=1 skip=$i oflag=append conv=notrunc > /dev/null 2>&1; 
	done; 

# This works for both USB and network printers, and maybe some others.
	eop_marker="\\x0c" # page feed (+ half cut if possible).
	if (($first_middle_last_page == 2)); then
		eop_marker="\\x1a" # done print job (cut tape).
	fi
	echo -n -e "$eop_marker" >> pt.prn; 
  done; 
done; 

if (($yes==0)); then
	echo "Now all is prepared and ready to print."
	echo "But do you really need to print that? Use '--yes' then."
	exit 0
fi	

lpr -C "$img" -P "$printer" -o raw pt.prn

echo "Done."
exit 0
