#!/bin/bash

help() {
    echo "options:"
    echo "-h    Print a usage statement and exit."
    echo "-m method     Use the given method to perform the backup. Valid methods are 'dd' and 'rsync'; default is 'dd'."
    echo "-v volume-id  Use the given volume instead of creating a new one."
}

log() {
    if [ -n "$EC2_BACKUP_VERBOSE" ]; then
        echo $1
    fi
}

clean() {
    if [ "$SSHFLAG" == "0" ]; then
        # delete key pair
        key=`aws ec2 describe-key-pairs | grep ec2-backup-key`
        if [ -n "$key"  ]; then
            aws ec2 delete-key-pair --key-name ec2-backup-key
        fi
        # delete pem file 
        if [ -d "$pemfile" ]; then
            rm -f $pemfile 
        fi
        log `aws ec2 delete-security-group --group-name ec2-backup-sg`
        log `aws ec2 detach-volume --volume-id $VOLID`
        log `aws ec2 terminate-instances --instance-ids $instanceId`     
    fi
}

# init 
METHOD="dd"
VOLFLAG="0"
SSHFLAG="1"
KEYNAME="ec2-backup-key"
DIR="/MyBackUp"
backupDir="/ec2-back-up"
AvailFLAG="0"

check_available()
{
    count=0
    export availableSpace
    if [ -z $EC2_BACKUP_VERBOSE ];then
        ssh -q -t -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} "sudo mkfs.ext4 /dev/xvdf;"
    fi
    while :
    do
        [ -n "${EC2_BACKUP_VERBOSE}"  ] && echo "make file..." >&2
        sleep 3
        availableSpace=$(ssh -q -t -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} "df | grep $DIR | awk '{print($4)}'")
        if [ availableSpace -gt dirSize ];then
            AvailFLAG="1"
        fi
        if [ $? -eq 0 ];then
            break
        fi
        count=$(($count+1))
        if [ $cnt -eq 30  ];then
            return 2
        fi
    done
    echo "check available completed"
}

make_file()
{
    count=0
    while :
    do
        [ -n "${EC2_BACKUP_VERBOSE}"  ] && echo "make file..." >&2
        sleep 3
        ssh -q -t -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} "sudo mkfs.ext4 /dev/xvdf;"
        AvailFLAG="1"
        if [ $? -eq 0  ];then
            break
        fi
            count=$(($count+1))
        if [ $cnt -eq 30  ];then
            return 2
        fi
    done
    echo "make file completed"
}

mount_DIR()
{
    if [ $VOLFLAG -eq 0  ];then
    count=0
    while :
    do
        [ -n "${EC2_BACKUP_VERBOSE}"  ] && echo "mount..." >&2
        sleep 3
        ssh -q -t -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} "sudo mkdir $DIR"
        ssh -q -t -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} "sudo mount /dev/xvdf $DIR"
        if [ $? -eq 0  ];then
            break
        fi
        count=$(($count+1))
        if [ $count -eq 30  ];then
            return 2
        fi
    done
    fi
    echo "mount completed"
}

umount_DIR()
{
    count=0
    while :
    do
        [ -n "${EC2_BACKUP_VERBOSE}"  ] && echo "umount..." >&2
        sleep 3
        ssh -q -t -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} "sudo umount $DIR"
        if [ $? -eq 0  ];then
            break
        fi
        count=$(($count+1))
        if [ $cnt -eq 30  ];then
            return 2
        fi
    done
    echo "umount completed"
}

back_up_dd()
{
    count=0
    time=$(date | sed "s/ /-/g")
    while :
    do
        [ -n "${EC2_BACKUP_VERBOSE}"  ] && echo "backing up! (dd)..." >&2
        sleep 3
        ssh -t -q -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} "    sudo mkdir $DIR/$time/"
        temp_name=$(echo $origin_dir |  sed "s/\//_/g")
        tar -cPf - "$origin_dir" | ssh -q -t -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} sudo dd of=$DIR/$time/$temp_name.tar.gz >/dev/null 2>&1
        if [ $? -eq 0  ];then
            break
        fi
        count=$(($count+1))
        if [ $count -eq 30  ];then
            return 2
        fi
    done
    echo "back-dd completed"
}

back_up_rsync()
{
    count=0
    time=$(date | sed "s/ /-/g")
    while :
        do
        [ -n "${EC2_BACKUP_VERBOSE}"  ] && echo "mkfs and mount on $addr..." >&2
        sleep 3
        rsync -azP "$origin_dir" ubuntu@${INSTANCE_ADDRESS}:/home/ubuntu$backupDir -e "ssh ${EC2_BACKUP_FLAGS_SSH}" >/dev/null 2>&1
        if [ $? -eq 0  ];then
            break
        fi
    count=$(($count+1))
    if [ $count -eq 30  ];then
            return 2
    fi
    done
    ssh -t -q -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} "sudo mkdir $DIR/$time/"
    ssh -t -q -oStrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@${INSTANCE_ADDRESS} "sudo mv /home/ubuntu$backupDir/* $DIR/$time/"
    echo "back-rsync completedï"
}


# extract command line options with getopt
while getopts :hm:v: opt
do
    case "$opt" in
    h) help ;;
    m) METHOD=$OPTARG
       if [ "$METHOD" != "dd" -a "$METHOD" != "rsync" ]; then
           echo "error: invalid method"
           exit 127
       fi;;
    v) VOLFLAG="1"
       VOLID=$OPTARG ;;
    *) echo "Unknown option: $opt" ;;   
    esac
done
shift `expr $OPTIND - 1`


# check directory
origin_dir=$1
if [ ! -d "$origin_dir" ]; then
    echo "error: directory $origin_dir does not exist."
    exit 1
fi
    

# create a new security group for ec2 backup
# check if the group ec2-backup exists
group=`aws ec2 describe-security-groups | grep ec2-backup-sg`
if [ -z "$group" ]; then 
    log `aws ec2 create-security-group --group-name ec2-backup-sg --description "ec2 backup group"`
    log `aws ec2 authorize-security-group-ingress --group-name ec2-backup-sg --protocol -1 --cidr 0.0.0.0/0`
    #echo "delete back up sg if it exists" 
    #aws ec2 delete-security-group --group-name ec2-backup-sg   
fi
groupID=`aws ec2 describe-security-groups --group-name ec2-backup-sg | grep "GroupId" | awk -F'"' '{print($4)}'` 


# check if $EC2_BACKUP_FLAGS_SSH has set up 
if [ -z "$EC2_BACKUP_FLAGS_SSH" ]; then
    # create a new key for ec2 backup
    # check if the key pair exist
    key=`aws ec2 describe-key-pairs | grep $KEYNAME`
    if [ -n "$key"  ]; then
        info=`aws ec2 delete-key-pair --key-name $KEYNAME` 
    fi
    # if the pem file exists, remove it first
    pemFile="./$KEYNAME.pem"
    if [ ! -d "$pemFile" ]; then
        rm -f $pemFile 
    fi
    aws ec2 create-key-pair --key-name $KEYNAME --query 'KeyMaterial' --output text > $pemFile
    chmod 400 $pemFile
    SSHFLAG="0"
    EC2_BACKUP_FLAGS_SSH="-i "$pemFile
else
    #check if the pem file exist
    pemFile=`echo $EC2_BACKUP_FLAGS_SSH | awk '{print($2)}'`
    if [ -d "$pemFile" ]; then
        echo "error: pem file does not exist"   
        exit 1
    fi
    #get fingerprint from private key and find the name of the fingerprint
    fingerprint=`ec2-fingerprint-key $pemFile`
    KEYNAME=`aws ec2 describe-key-pairs | grep $fingerprint -B 1 | awk -F'"' '{print($4)}'`
    KEYNAME=`echo $KEYNAME | awk '{print($1)}'` 
    if [ -z "$KEYNAME" ]; then
        echo "error: the key pair does not exist"
        exit 1
    fi
fi


# create instance
if [ -z "$EC2_BACKUP_FLAGS_AWS" ]; then
    instanceId=`aws ec2 run-instances --image-id ami-fce3c696 --security-group-ids "$groupID" --count 1 --instance-type t2.micro --key-name $KEYNAME --query 'Instances[0].InstanceId' | awk -F'"' '{print($2)}'`
else
    instanceId=`aws ec2 run-instances --image-id ami-fce3c696 --security-group-ids "$groupID    " --count 1 $EC2_BACKUP_FLAGS_AWS --key-name $KEYNAME --query 'Instances[0].InstanceId' | awk -F'"' '{print($2)}'`
fi
sleep 5
INSTANCE_ADDRESS=`aws ec2 describe-instances --instance-ids $instanceId --query 'Reservations[0].Instances[0].PublicIpAddress' | awk -F'"' '{print($2)}'`


# calculate directory size
dirSize=`du -s $origin_dir | awk '{print($1)}'`
volSize=`echo "$dirSize 524288" | awk '{print($1/$2)}'`
volSize=`echo volSize | awk '{print int($1)==$1?$1:int(int($1*10/10+1))}'`
avaiZone=`aws ec2 describe-instances --instance-ids $instanceId --query 'Reservations[0].Instances[0].Placement.AvailabilityZone'`
if [ "$VOLFLAG" == "0" ]; then
    # create a new volume
    avaiZone=`echo $avaiZone | awk -F'"' '{print($2)}'`
    VOLID=`aws ec2 create-volume --size $volSize --availability-zone $avaiZone --volume-type gp2 | grep VolumeId | awk -F'"' '{print($4)}'`
    echo $VOLID
else
    #check avaiable zone and volume size
    curZone=`aws ec2 describe-volumes --volume-id $VOLID --query 'Volumes[0].AvailabilityZone'`
    if [ "$avaiZone" != "$curZone" ]; then
        echo "the avaiable zone of volume does not match you"
        exit 1
    fi
    curSize=`aws ec2 describe-volumes --volume-id $VOLID --query 'Volumes[0].Size'`
    if [ $volSize -gt $curSize ]; then
        echo "The size of the volume is not enough" 
        exit 1
    fi
fi


# wait for instance initializing
status=""
while [ "$status" != '"ok"' ]
do
    log "wait for instance initializing. status: $status"
    status=`aws ec2 describe-instance-status --instance-ids $instanceId --query 'InstanceStatuses[0].InstanceStatus.Status'`
    sleep 15
done    
log "initializing ok" 


# attach-volume
info=`aws ec2 attach-volume --volume-id $VOLID --instance-id $instanceId --device /dev/sdf`
sleep 5 
log "attached"


# if use the new volume then make_file
if [ $VOLFLAG -eq 0 ];then
    make_file
else
# if use
    check_available
fi
if [ $AvailFLAG -eq 0 ];then
    exit 3
else
    mount_DIR
fi
if !([ $METHOD == "dd" ] || [ $METHOD == "rsync" ])
then
    echo "ERROR: Illegal method"
    echo "Valid methods are 'dd' and 'rsync'; default is 'dd'."
usage
exit 1
fi

if [ $METHOD == "dd" ];then
    back_up_dd
else
    back_up_rsync
fi
umount_DIR


# close instance
clean

exit 0

